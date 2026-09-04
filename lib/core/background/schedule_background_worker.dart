import "dart:io";

import "package:flutter/foundation.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:workmanager/workmanager.dart";

import "../../core/notifications/notification_service.dart";
import "../widgets/home_widget_service.dart";
import "app_update_background_worker.dart";
import "../../features/schedule/data/express_schedule_repository.dart";
import "../../features/schedule/data/groups_cache.dart";
import "../../features/schedule/data/preferences_manager.dart";
import "../../features/schedule/data/schedule_cache.dart";
import "../../features/schedule/data/statistics_cache.dart";
import "../../features/schedule/data/sub_schedule_cache.dart";
import "../../features/schedule/domain/schedule_hash.dart";

class ScheduleBackgroundWorker {
  static const String taskName = "schedule_background_check";
  static const String uniqueName = "schedule_background_check_unique";

  static bool get supported => !kIsWeb && Platform.isAndroid;

  static Future<void> ensureRegisteredIfNeeded({
    required PreferencesManager prefs,
  }) async {
    if (!supported) return;
    if (!prefs.autoRefreshEnabled || !prefs.isGroupSelected) {
      await cancel();
      return;
    }
    await register();
  }

  static Future<void> register() async {
    if (!supported) return;
    await Workmanager().registerPeriodicTask(
      uniqueName,
      taskName,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(networkType: NetworkType.connected),
      frequency: const Duration(minutes: 15),
    );
  }

  static Future<void> cancel() async {
    if (!supported) return;
    await Workmanager().cancelByUniqueName(uniqueName);
  }
}

@pragma("vm:entry-point")
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == AppUpdateBackgroundWorker.taskName) {
      return runAppUpdateBackgroundTask();
    }
    if (task != ScheduleBackgroundWorker.taskName) {
      return true;
    }

    final sp = await SharedPreferences.getInstance();
    final prefs = PreferencesManager(sp);

    if (!prefs.autoRefreshEnabled || !prefs.isGroupSelected) {
      return true;
    }

    // Изолят воркера стартует с пустым кэшем LessonTimes — без этого виджет
    // и напоминания получили бы встроенное время пар вместо своего.
    prefs.applyStoredLessonTimes();

    final repository = ExpressScheduleRepository(
      scheduleCache: ScheduleCache(sp),
      groupsCache: GroupsCache(sp),
      statisticsCache: StatisticsCache(sp),
      subScheduleCache: SubScheduleCache(sp),
    );
    repository.setCustomBaseUrls(prefs.effectiveCollegeBaseUrls);

    try {
      final days = await repository.fetchSchedule(
        groupFile: prefs.selectedGroupFile,
        college: prefs.college,
        useCache: false,
      );

      if (days.isEmpty) return true;

      final newHash = computeScheduleHash(days);
      final oldHash = prefs.lastScheduleHash;

      if (oldHash.isNotEmpty &&
          newHash.isNotEmpty &&
          newHash != oldHash &&
          prefs.notifyScheduleChanges) {
        await NotificationService.instance.init();
        await NotificationService.instance.showScheduleChanged(
          groupName: prefs.selectedGroupName,
          fromBackgroundWorker: true,
        );
      }

      prefs.lastScheduleHash = newHash;

      // Обновляем и домашний виджет: без этого он показывал вчерашние
      // данные и старое «Обновлено», пока пользователь не откроет приложение.
      try {
        await HomeWidgetService.init();
        await HomeWidgetService.updateWidget(
          schedule: days,
          groupName: prefs.selectedGroupName,
          themeKey: prefs.effectiveWidgetTheme,
          fontScale: prefs.widgetFontScale,
          college: prefs.college,
          accentColorValue:
              widgetAccentColorFor(prefs, prefs.effectiveWidgetTheme),
        );
      } catch (e) {
        if (kDebugMode) debugPrint("Widget update from worker failed: $e");
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint("Background schedule check failed: $e");
        debugPrintStack(stackTrace: st);
      }
    }

    return true;
  });
}

