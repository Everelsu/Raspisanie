import "dart:async";
import "dart:convert";
import "dart:io";

import "package:connectivity_plus/connectivity_plus.dart";
import "package:crypto/crypto.dart";
import "package:flutter/foundation.dart";
import "package:http/http.dart" as http;
import "package:package_info_plus/package_info_plus.dart";
import "package:path_provider/path_provider.dart";
import "package:shared_preferences/shared_preferences.dart";

import "app_update_service.dart";
import "update_manifest.dart";
import "version_utils.dart";

/// Стадия обновления: найдено (нужно скачать) или APK уже скачан и проверен.
enum AppUpdateStage { available, downloaded }

/// Контроллер обновлений приложения.
///
/// Держит состояние всего цикла обновления: проверка манифеста из ветки
/// `updater` → автозагрузка APK в фоне (только Wi-Fi/Ethernet) → проверка
/// sha256 → установка. Диалог обновления подписывается на контроллер и
/// показывает актуальную стадию; повторные напоминания ограничены
/// снооз-состоянием (см. [shouldPrompt] / [snoozePrompt]).
class AppUpdateController extends ChangeNotifier {
  AppUpdateController._();
  static final AppUpdateController instance = AppUpdateController._();

  static const String _promptStateKey = "app_update_prompt_state";
  static const String _autoDownloadKey = "auto_download_app_update";
  static const Duration promptSnoozeDelay = Duration(hours: 24);

  UpdateManifest? _available;
  bool _downloading = false;
  double _progress = 0;
  String? _apkPath;
  String? _error;
  bool _checking = false;

  /// Найденное обновление (версия новее текущей) или null.
  UpdateManifest? get available => _available;
  bool get downloading => _downloading;

  /// Прогресс загрузки APK, 0.0..1.0.
  double get progress => _progress;
  String? get error => _error;
  AppUpdateStage get stage =>
      _apkPath != null ? AppUpdateStage.downloaded : AppUpdateStage.available;

  /// Проверяет наличие новой версии. Если найдена и разрешена автозагрузка —
  /// сразу начинает качать APK в фоне (только на безлимитной сети).
  /// Возвращает найденное обновление или null.
  Future<UpdateManifest?> check({bool autoDownload = true}) async {
    if (_checking) return _available;
    _checking = true;
    try {
      final info = await PackageInfo.fromPlatform();
      final manifest = await fetchUpdateManifest();
      if (manifest == null) return _available;
      if (compareVersions(info.version, manifest.version) >= 0) {
        if (_available != null) {
          _available = null;
          _apkPath = null;
          notifyListeners();
        }
        return null;
      }
      if (_available?.version != manifest.version) {
        _available = manifest;
        _apkPath = null;
        _progress = 0;
        _error = null;
        notifyListeners();
      }
      if (autoDownload &&
          Platform.isAndroid &&
          _apkPath == null &&
          !_downloading &&
          await _autoDownloadAllowed()) {
        unawaited(download());
      }
      return _available;
    } finally {
      _checking = false;
    }
  }

  Future<bool> _autoDownloadAllowed() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (!(sp.getBool(_autoDownloadKey) ?? true)) return false;
      final results = await Connectivity().checkConnectivity();
      return results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet);
    } catch (e) {
      if (kDebugMode) debugPrint("Connectivity check error: $e");
      return false;
    }
  }

  Future<bool>? _downloadTask;

  /// Скачивает APK найденного обновления и проверяет sha256.
  /// Возвращает true, когда файл готов к установке. Повторный вызов во время
  /// активной загрузки возвращает ту же Future (дожидается её завершения).
  Future<bool> download() {
    final update = _available;
    if (update == null || !Platform.isAndroid) return Future.value(false);
    if (_apkPath != null) return Future.value(true);
    return _downloadTask ??= _runDownload(update).whenComplete(() {
      _downloadTask = null;
    });
  }

  Future<bool> _runDownload(UpdateManifest update) async {
    _downloading = true;
    _error = null;
    _progress = 0;
    notifyListeners();
    try {
      final path = await _downloadAndVerify(update);
      if (path == null) {
        _error = "Не удалось скачать обновление";
        return false;
      }
      _apkPath = path;
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint("Update download error: $e");
      _error = "Не удалось скачать обновление";
      return false;
    } finally {
      _downloading = false;
      notifyListeners();
    }
  }

  Future<String?> _downloadAndVerify(UpdateManifest update) async {
    final dir = await getTemporaryDirectory();
    final file = File("${dir.path}/update_${update.version}.apk");

    // Файл мог остаться от прошлого запуска — переиспользуем, если он цел.
    if (await file.exists() && await _matchesManifest(file, update)) {
      _progress = 1;
      notifyListeners();
      return file.path;
    }

    final client = http.Client();
    try {
      final request = http.Request("GET", Uri.parse(update.apkUrl));
      final response = await client.send(request);
      if (response.statusCode != 200) return null;
      final total = response.contentLength ?? update.size ?? 0;
      var received = 0;
      final digestSink = _DigestSink();
      final hashSink = sha256.startChunkedConversion(digestSink);
      final sink = file.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          hashSink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            final next = received / total;
            // Не дёргаем слушателей на каждый чанк — только на ~1% прогресса.
            if (next - _progress >= 0.01 || next >= 1) {
              _progress = next;
              notifyListeners();
            }
          }
        }
      } finally {
        await sink.close();
      }
      hashSink.close();
      final digest = digestSink.value?.toString();
      if (update.sha256 != null &&
          update.sha256!.isNotEmpty &&
          digest != update.sha256) {
        if (kDebugMode) {
          debugPrint("APK sha256 mismatch: $digest != ${update.sha256}");
        }
        await file.delete();
        return null;
      }
      return file.path;
    } finally {
      client.close();
    }
  }

  Future<bool> _matchesManifest(File file, UpdateManifest update) async {
    try {
      if (update.size != null && await file.length() != update.size) {
        return false;
      }
      if (update.sha256 == null || update.sha256!.isEmpty) {
        // Без эталонного хэша повторно не доверяем недокачанному файлу.
        return update.size != null;
      }
      final digestSink = _DigestSink();
      final hashSink = sha256.startChunkedConversion(digestSink);
      await for (final chunk in file.openRead()) {
        hashSink.add(chunk);
      }
      hashSink.close();
      return digestSink.value?.toString() == update.sha256;
    } catch (_) {
      return false;
    }
  }

  /// Запускает установщик скачанного APK.
  Future<bool> install() async {
    final path = _apkPath;
    if (path == null) return false;
    return installApk(path);
  }

  // --- Снооз-состояние диалога -------------------------------------------
  // Диалог для конкретной версии и стадии показывается сразу, а после
  // «Позже» — не раньше чем через [promptSnoozeDelay]. Смена версии или
  // переход available → downloaded сбрасывает отсрочку.

  /// Пора ли показывать диалог для текущего обновления.
  Future<bool> shouldPrompt() async {
    final update = _available;
    if (update == null) return false;
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_promptStateKey);
      if (raw == null) return true;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data["version"] != update.version || data["stage"] != stage.name) {
        return true;
      }
      final until = (data["snoozedUntil"] as num?)?.toInt() ?? 0;
      return DateTime.now().millisecondsSinceEpoch >= until;
    } catch (_) {
      return true;
    }
  }

  /// Откладывает следующее напоминание об этом обновлении на сутки.
  Future<void> snoozePrompt() async {
    final update = _available;
    if (update == null) return;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        _promptStateKey,
        jsonEncode({
          "version": update.version,
          "stage": stage.name,
          "snoozedUntil": DateTime.now()
              .add(promptSnoozeDelay)
              .millisecondsSinceEpoch,
        }),
      );
    } catch (e) {
      if (kDebugMode) debugPrint("Snooze state write error: $e");
    }
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
