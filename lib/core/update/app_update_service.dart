import "dart:io";

import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:path_provider/path_provider.dart";
import "package:http/http.dart" as http;

import "github_update_service.dart";
import "version_utils.dart";

const MethodChannel _channel = MethodChannel("com.example.raspiflutter/install_apk");

/// Проверяет, есть ли новая версия на GitHub. Только Android.
/// Возвращает [GitHubReleaseInfo] если версия на сервере новее текущей, иначе null.
Future<GitHubReleaseInfo?> checkForUpdate() async {
  if (!Platform.isAndroid) return null;
  final info = await PackageInfo.fromPlatform();
  final current = info.version;
  final release = await getLatestGitHubRelease();
  if (release == null) return null;
  if (compareVersions(current, release.version) >= 0) return null;
  return release;
}

/// Скачивает APK по [url] и возвращает путь к файлу. [onProgress] вызывается с 0.0..1.0.
Future<String?> downloadApk(String url, {void Function(double)? onProgress}) async {
  try {
    final dir = await getTemporaryDirectory();
    final name = "update_${DateTime.now().millisecondsSinceEpoch}.apk";
    final file = File("${dir.path}/$name");
    final request = http.Request("GET", Uri.parse(url));
    final client = http.Client();
    final response = await client.send(request);
    if (response.statusCode != 200) return null;
    final total = response.contentLength ?? 0;
    var received = 0;
    final sink = file.openWrite();
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0 && onProgress != null) {
        onProgress(received / total);
      }
    }
    await sink.close();
    client.close();
    return file.path;
  } catch (e) {
    if (kDebugMode) debugPrint("APK download error: $e");
    return null;
  }
}

/// Запускает установку APK по пути. Только Android.
/// После успешного вызова установки удаляет APK из темп-дира, чтобы не занимать место.
Future<bool> installApk(String filePath) async {
  if (!Platform.isAndroid) return false;
  try {
    await _channel.invokeMethod<void>("install", {"path": filePath});
    try {
      final file = File(filePath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
    return true;
  } on PlatformException catch (e) {
    if (kDebugMode) debugPrint("Install APK error: ${e.message}");
    return false;
  }
}
