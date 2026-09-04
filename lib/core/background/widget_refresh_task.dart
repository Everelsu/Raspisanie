import "package:flutter/foundation.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../../features/schedule/data/express_schedule_repository.dart";
import "../../features/schedule/data/groups_cache.dart";
import "../../features/schedule/data/preferences_manager.dart";
import "../../features/schedule/data/schedule_cache.dart";
import "../../features/schedule/data/statistics_cache.dart";
import "../../features/schedule/data/sub_schedule_cache.dart";
import "../widgets/home_widget_service.dart";

/// Хост URI, который шлёт кнопка обновления на домашнем виджете
/// (ScheduleWidgetProvider.ACTION_REFRESH → HomeWidgetBackgroundReceiver).
const String widgetRefreshUriHost = "refresh";

/// Точка входа фонового изолята home_widget: тап по кнопке «Обновить»
/// на домашнем виджете. Регистрируется в main() через
/// `HomeWidget.registerInteractivityCallback`.
@pragma("vm:entry-point")
Future<void> homeWidgetInteractivityCallback(Uri? uri) async {
  if (uri != null && uri.host.isNotEmpty && uri.host != widgetRefreshUriHost) {
    return;
  }
  await runWidgetRefreshTask();
}

/// Тянет расписание из сети и перерисовывает виджет.
///
/// Всегда снимает индикатор «Обновление…» — иначе после ошибки сети виджет
/// завис бы в состоянии загрузки до следующего открытия приложения.
Future<void> runWidgetRefreshTask() async {
  try {
    await HomeWidgetService.init();
  } catch (_) {}

  var updated = false;
  try {
    final sp = await SharedPreferences.getInstance();
    // Изолят мог подняться раньше, чем приложение дописало настройки.
    try {
      await sp.reload();
    } catch (_) {}
    final prefs = PreferencesManager(sp);

    if (!prefs.isGroupSelected) return;

    // Свой/синхронизированный тайминг пар: в этом изоляте кэш LessonTimes
    // пустой, без этого в виджет уехало бы встроенное время.
    prefs.applyStoredLessonTimes();

    final repository = ExpressScheduleRepository(
      scheduleCache: ScheduleCache(sp),
      groupsCache: GroupsCache(sp),
      statisticsCache: StatisticsCache(sp),
      subScheduleCache: SubScheduleCache(sp),
    );
    repository.setCustomBaseUrls(prefs.effectiveCollegeBaseUrls);

    // Тайм-аут короче окна «Обновление…» на Kotlin-стороне: при мёртвой сети
    // виджет вернётся в обычное состояние сам, а не провисит минуту.
    final days = await repository
        .fetchSchedule(
          groupFile: prefs.selectedGroupFile,
          college: prefs.college,
          useCache: false,
        )
        .timeout(const Duration(seconds: 20));
    if (days.isEmpty) return;

    await HomeWidgetService.updateWidget(
      schedule: days,
      groupName: prefs.selectedGroupName,
      themeKey: prefs.effectiveWidgetTheme,
      fontScale: prefs.widgetFontScale,
      college: prefs.college,
      accentColorValue: widgetAccentColorFor(prefs, prefs.effectiveWidgetTheme),
    );
    updated = true;
  } catch (e) {
    if (kDebugMode) debugPrint("Widget refresh from button failed: $e");
  } finally {
    // Данные уехали — updateWidget уже снял флаг и перерисовал виджет.
    // Второй проход только добавил бы лишнюю полную перерисовку.
    if (!updated) await HomeWidgetService.finishRefresh();
  }
}
