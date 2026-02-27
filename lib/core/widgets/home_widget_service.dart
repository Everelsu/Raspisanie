import "package:home_widget/home_widget.dart";

import "../../features/schedule/domain/models.dart";

class HomeWidgetService {
  static const _androidProviderFull =
      "com.example.raspiflutter.ScheduleWidgetProvider";
  static const _androidProviderShort = "ScheduleWidgetProvider";
  static const _iosWidgetKind = "ScheduleWidget";
  static const _appGroupId = "group.com.example.raspiflutter";
  static const _itemSeparator = "\u241E";

  static Future<void> init() async {
    try {
      await HomeWidget.setAppGroupId(_appGroupId);
    } catch (_) {}
  }

  static Future<void> updateWidget({
    required List<DaySchedule> schedule,
    required String groupName,
    required String themeKey,
    required double fontScale,
  }) async {
    try {
      final now = DateTime.now();
      final today = _dateKey(now);

      final sortedDays = schedule.toList()
        ..sort((a, b) {
          final da = _tryParseDate(a.date) ?? DateTime(1970);
          final db = _tryParseDate(b.date) ?? DateTime(1970);
          return da.compareTo(db);
        });

      DaySchedule? displayDay;
      displayDay =
          _firstWhereOrNull(sortedDays, (d) => d.date == today && d.items.isNotEmpty);
      displayDay ??= _firstWhereOrNull(sortedDays, (d) => d.items.isNotEmpty);
      displayDay ??= _firstWhereOrNull(sortedDays, (d) => d.date == today);
      displayDay = displayDay ?? (sortedDays.isEmpty ? null : sortedDays.first);

      final items = (displayDay?.items ?? const <ScheduleItem>[]).toList()
        ..sort((a, b) => a.lessonNumber.compareTo(b.lessonNumber));

      final title = groupName.isEmpty ? "Расписание" : groupName;
      final subtitle = displayDay == null
          ? "На сегодня нет данных"
          : "${_capitalize(displayDay.day)}, ${displayDay.date}";

      String primary = "Нет занятий";
      String secondary = "Откройте приложение для обновления";
      String footer = "Raspisanie";
      String dayItemsPayload = "";

      if (items.isNotEmpty) {
        final first = items.first;
        primary = "${first.lessonNumber}. ${first.subject ?? "—"}";
        final details = <String>[
          if (first.classroom?.isNotEmpty == true) "Ауд. ${first.classroom}",
          if (first.teacher?.isNotEmpty == true) first.teacher!,
          if (first.subgroup != null) "${first.subgroup} п/г",
        ];
        secondary = details.isEmpty ? "Без деталей" : details.join(" · ");
        footer = "${items.length} ${_lessonWord(items.length)} • нажмите для открытия";
        dayItemsPayload = items.map(_lineForWidget).join(_itemSeparator);
      }

      await HomeWidget.saveWidgetData<String>("widget_title", title);
      await HomeWidget.saveWidgetData<String>("widget_subtitle", subtitle);
      await HomeWidget.saveWidgetData<String>("widget_primary", primary);
      await HomeWidget.saveWidgetData<String>("widget_secondary", secondary);
      await HomeWidget.saveWidgetData<String>("widget_footer", footer);
      await HomeWidget.saveWidgetData<String>("widget_day_items", dayItemsPayload);
      await HomeWidget.saveWidgetData<String>("widget_theme", themeKey);
      await _saveWidgetFontScale(fontScale);
      await _bumpWidgetRefreshToken();
      await _forceRefreshWidget();
    } catch (_) {}
  }

  static Future<void> updateWidgetTheme({
    required String themeKey,
    required double fontScale,
  }) async {
    try {
      await HomeWidget.saveWidgetData<String>("widget_theme", themeKey);
    } catch (_) {}
    try {
      await _saveWidgetFontScale(fontScale);
    } catch (_) {}
    try {
      await _bumpWidgetRefreshToken();
    } catch (_) {}
    await _forceRefreshWidget();
  }

  static Future<void> _saveWidgetFontScale(double value) async {
    final normalized = value.clamp(0.9, 1.35).toStringAsFixed(2);
    // String payload is the most compatible across plugin/platform versions.
    await HomeWidget.saveWidgetData<String>("widget_font_scale", normalized);
  }

  static Future<void> _bumpWidgetRefreshToken() async {
    await HomeWidget.saveWidgetData<String>(
      "widget_refresh_token",
      DateTime.now().microsecondsSinceEpoch.toString(),
    );
  }

  static DateTime? _lastRefresh;
  static const _minRefreshInterval = Duration(seconds: 3);

  static Future<void> _forceRefreshWidget() async {
    final now = DateTime.now();
    if (_lastRefresh != null &&
        now.difference(_lastRefresh!) < _minRefreshInterval) {
      return;
    }
    _lastRefresh = now;
    await _updateWidgetByKnownNames();
    await Future<void>.delayed(const Duration(milliseconds: 220));
    await _updateWidgetByKnownNames();
  }

  static Future<void> _updateWidgetByKnownNames() async {
    try {
      await HomeWidget.updateWidget(
        androidName: _androidProviderFull,
        iOSName: _iosWidgetKind,
      );
    } catch (_) {}
    try {
      await HomeWidget.updateWidget(
        androidName: _androidProviderShort,
        iOSName: _iosWidgetKind,
      );
    } catch (_) {}
  }

  static String _dateKey(DateTime d) =>
      "${d.day.toString().padLeft(2, "0")}.${d.month.toString().padLeft(2, "0")}.${d.year}";

  static DateTime? _tryParseDate(String raw) {
    try {
      final p = raw.split(".");
      if (p.length != 3) return null;
      return DateTime(
        int.parse(p[2]),
        int.parse(p[1]),
        int.parse(p[0]),
      );
    } catch (_) {
      return null;
    }
  }

  static T? _firstWhereOrNull<T>(Iterable<T> list, bool Function(T) test) {
    for (final item in list) {
      if (test(item)) return item;
    }
    return null;
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _lessonWord(int n) {
    if (n % 10 == 1 && n % 100 != 11) return "пара";
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) {
      return "пары";
    }
    return "пар";
  }

  static String _lineForWidget(ScheduleItem i) {
    final parts = <String>[
      "${i.lessonNumber}. ${(i.subject ?? "—").trim()}",
      if (i.classroom?.isNotEmpty == true) "Ауд. ${i.classroom}",
      if (i.teacher?.isNotEmpty == true) i.teacher!,
      if (i.subgroup != null) "${i.subgroup} п/г",
    ];
    return parts.join(" · ");
  }
}
