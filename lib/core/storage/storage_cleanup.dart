import "dart:io";

import "package:path_provider/path_provider.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../database/schedule_database.dart";
import "../../features/schedule/data/groups_cache.dart";
import "../../features/schedule/data/schedule_cache.dart";

/// Централизованная очистка кэша и временных данных для уменьшения веса приложения.
class StorageCleanup {
  StorageCleanup._();

  static const _lastCleanupKey = "storage_last_cleanup_at";
  static const _cleanupIntervalHours = 24;
  static const _maxScheduleCachePairs = 10;
  static const _maxGroupsCacheEntries = 8;
  static const _tempFileMaxAgeHours = 24;

  /// Запускает периодическую очистку (темп, кэш расписания/групп, БД).
  /// Не блокирует старт приложения.
  static Future<void> runPeriodicCleanup(SharedPreferences prefs) async {
    try {
      await clearTempDirectory();
      final cache = ScheduleCache(prefs);
      cache.trimToMaxEntries(_maxScheduleCachePairs);
      final groups = GroupsCache(prefs);
      groups.trimToMaxEntries(_maxGroupsCacheEntries);

      final lastMs = prefs.getInt(_lastCleanupKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final hoursSince = (now - lastMs) / (1000 * 60 * 60);
      if (hoursSince >= _cleanupIntervalHours) {
        await ScheduleDatabase.instance.runCleanupIfNeeded();
        await prefs.setInt(_lastCleanupKey, now);
      }
    } catch (_) {}
  }

  /// Удаляет старые файлы из временной директории (APK обновлений, экспорт, шаринг).
  static Future<void> clearTempDirectory() async {
    try {
      final dir = await getTemporaryDirectory();
      final tempDir = Directory(dir.path);
      if (!await tempDir.exists()) return;
      final now = DateTime.now();
      final cutoff = now.subtract(Duration(hours: _tempFileMaxAgeHours));
      await for (final entity in tempDir.list(followLinks: false)) {
        try {
          if (entity is File) {
            final name = entity.uri.pathSegments.last;
            final delete = name.startsWith("update_") && name.endsWith(".apk") ||
                await entity.lastModified().then((t) => t.isBefore(cutoff));
            if (delete) await entity.delete();
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Очищает только кэш расписания в SharedPreferences (расписание + история по группам).
  static void clearScheduleCache(SharedPreferences prefs) {
    ScheduleCache(prefs).clearAll();
    final keys = prefs.getKeys().toList();
    for (final key in keys) {
      if (key.startsWith("history_")) prefs.remove(key);
    }
  }

  /// Очищает кэш списков групп в SharedPreferences.
  static void clearGroupsCache(SharedPreferences prefs) {
    GroupsCache(prefs).clearAll();
  }

  /// Очищает кэш расписания и групп (для кнопки в настройках).
  static void clearAllPrefsCache(SharedPreferences prefs) {
    clearScheduleCache(prefs);
    clearGroupsCache(prefs);
  }
}
