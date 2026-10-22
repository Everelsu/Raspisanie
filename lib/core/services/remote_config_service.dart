import "dart:async";
import "dart:convert";

import "package:firebase_core/firebase_core.dart";
import "package:firebase_remote_config/firebase_remote_config.dart";
import "package:flutter/foundation.dart";

import "../../features/schedule/data/lesson_times.dart";
import "../../features/schedule/data/preferences_manager.dart";

/// Время пар и особые дни из Firebase Remote Config.
///
/// Параметры (JSON, редактируются в консоли Firebase):
/// - `lesson_times` — обычное время пар по техникумам, тот же формат, что
///   поле `colleges` в schedule_times.json. Если задан — главнее GitHub-файла
///   (тот остаётся запасным для веба, где Firebase нет).
/// - `special_days` — сокращённые дни, праздники, каникулы (см. [SpecialDays]).
///
/// Значения кладутся в prefs: их читают и фоновые изоляты (воркер
/// уведомлений, виджет), где Firebase не поднят. Правка в консоли долетает
/// сразу — через real-time listener, без перезапуска приложения.
class RemoteConfigService {
  RemoteConfigService._();
  static final instance = RemoteConfigService._();

  static const lessonTimesKey = "lesson_times";
  static const specialDaysKey = "special_days";

  StreamSubscription<RemoteConfigUpdate>? _updates;
  PreferencesManager? _prefs;
  VoidCallback? _onChanged;

  bool get available => _prefs != null;

  Future<void> start({
    required PreferencesManager prefs,
    required VoidCallback onChanged,
  }) async {
    // Веб и сборки без google-services: Firebase не поднят — работает
    // GitHub-файл, как раньше.
    if (Firebase.apps.isEmpty || _prefs != null) return;
    _prefs = prefs;
    _onChanged = onChanged;
    try {
      final rc = FirebaseRemoteConfig.instance;
      await rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: const Duration(hours: 1),
      ));
      // Сохранённые с прошлого раза значения — сразу, без сети.
      await rc.ensureInitialized();
      _apply(rc);
      _updates = rc.onConfigUpdated.listen(
        (_) async {
          await rc.activate();
          _apply(rc);
        },
        onError: (Object e) => debugPrint("Remote Config realtime: $e"),
      );
      if (await rc.fetchAndActivate()) _apply(rc);
    } catch (e) {
      debugPrint("Remote Config start error: $e");
    }
  }

  /// Принудительная проверка (кнопка «Обновить» у времени пар).
  Future<bool> refresh() async {
    if (_prefs == null) return false;
    try {
      final rc = FirebaseRemoteConfig.instance;
      await rc.fetchAndActivate();
      _apply(rc);
      return true;
    } catch (e) {
      debugPrint("Remote Config refresh error: $e");
      return false;
    }
  }

  void _apply(FirebaseRemoteConfig rc) {
    final prefs = _prefs;
    if (prefs == null) return;
    var changed = false;

    final timesRaw = rc.getString(lessonTimesKey).trim();
    if (timesRaw != prefs.rcLessonTimesRaw) {
      final byCollege = _parseLessonTimes(timesRaw);
      if (byCollege.isNotEmpty) {
        for (final e in byCollege.entries) {
          prefs.setRemoteLessonTimes(e.key, e.value);
        }
        prefs.remoteConfigOwnsLessonTimes = true;
      } else {
        // Параметр убрали из консоли — снова работает GitHub-файл.
        prefs.remoteConfigOwnsLessonTimes = false;
      }
      prefs.rcLessonTimesRaw = timesRaw;
      changed = true;
    }

    final daysRaw = rc.getString(specialDaysKey).trim();
    if (daysRaw != (prefs.specialDaysJson ?? "")) {
      prefs.specialDaysJson = daysRaw.isEmpty ? null : daysRaw;
      changed = true;
    }

    if (!changed) return;
    prefs.lessonTimesRemoteSyncedAt = DateTime.now().millisecondsSinceEpoch;
    prefs.applyStoredLessonTimes();
    _onChanged?.call();
  }

  static Map<String, Map<int, LessonTime>> _parseLessonTimes(String raw) {
    if (raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const {};
      final root = decoded["colleges"];
      return LessonTimes.parseByCollege(
          root is Map<String, dynamic> ? root : decoded);
    } catch (_) {
      return const {};
    }
  }

  @visibleForTesting
  Future<void> dispose() async => _updates?.cancel();
}
