import "package:home_widget/home_widget.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../../features/schedule/data/lesson_times.dart";
import "../../features/schedule/domain/models.dart";

class HomeWidgetService {
  static const _androidProviderFull =
      "com.example.raspiflutter.ScheduleWidgetProvider";
  static const _androidProviderShort = "ScheduleWidgetProvider";
  static const _iosWidgetKind = "ScheduleWidget";
  static const _appGroupId = "group.com.example.raspiflutter";
  static const _itemSeparator = "\u241E";
  static const _fieldSeparator = "\u241F";

  static Future<void> init() async {
    try {
      await HomeWidget.setAppGroupId(_appGroupId);
    } catch (_) {}
    try {
      await _saveWidgetFont();
    } catch (_) {}
  }

  static Future<void> updateWidget({
    required List<DaySchedule> schedule,
    required String groupName,
    required String themeKey,
    required double fontScale,
    String college = "chtotib",
    int? accentColorValue,
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
      // Пары на сегодня уже закончились — полезнее показать следующий
      // учебный день, чем список целиком «прошедших» пар.
      if (displayDay != null && _dayIsOver(displayDay, college, now)) {
        final startOfToday = DateTime(now.year, now.month, now.day);
        final upcoming = _firstWhereOrNull(sortedDays, (d) {
          final date = _tryParseDate(d.date);
          return date != null &&
              date.isAfter(startOfToday) &&
              d.items.isNotEmpty;
        });
        displayDay = upcoming ?? displayDay;
      }
      displayDay ??= _firstWhereOrNull(sortedDays, (d) => d.items.isNotEmpty);
      displayDay ??= _firstWhereOrNull(sortedDays, (d) => d.date == today);
      displayDay = displayDay ?? (sortedDays.isEmpty ? null : sortedDays.first);

      final items = (displayDay?.items ?? const <ScheduleItem>[]).toList()
        ..sort((a, b) {
          final cn = a.lessonNumber.compareTo(b.lessonNumber);
          if (cn != 0) return cn;
          return (a.subgroup ?? 0).compareTo(b.subgroup ?? 0);
        });

      final grouped = <int, List<ScheduleItem>>{};
      for (final item in items) {
        grouped.putIfAbsent(item.lessonNumber, () => []).add(item);
      }
      final lessonNumbers = grouped.keys.toList()..sort();

      final title = groupName.isEmpty ? "Расписание" : groupName;
      final subtitle = displayDay == null
          ? "На сегодня нет данных"
          : "${_capitalize(displayDay.day)}, ${displayDay.date}";

      String primary = "Нет пар";
      String secondary = "Свободный день";
      String countLabel = "";
      String dayItemsPayload = "";
      if (displayDay == null) {
        primary = "Нет данных";
        secondary = "Откройте приложение для обновления";
      }

      if (lessonNumbers.isNotEmpty) {
        countLabel =
            "${lessonNumbers.length} ${_lessonWord(lessonNumbers.length)}";
        dayItemsPayload = lessonNumbers
            .map((n) => _blockRowForWidget(n, grouped[n]!, college))
            .join(_itemSeparator);
      }

      final now2 = DateTime.now();
      final footer =
          "Обновлено ${now2.hour.toString().padLeft(2, "0")}:${now2.minute.toString().padLeft(2, "0")}";

      await HomeWidget.saveWidgetData<String>("widget_title", title);
      await HomeWidget.saveWidgetData<String>("widget_subtitle", subtitle);
      await HomeWidget.saveWidgetData<String>("widget_primary", primary);
      await HomeWidget.saveWidgetData<String>("widget_secondary", secondary);
      await HomeWidget.saveWidgetData<String>("widget_footer", footer);
      await HomeWidget.saveWidgetData<String>("widget_count_label", countLabel);
      await HomeWidget.saveWidgetData<String>(
          "widget_date", displayDay?.date ?? "");
      await HomeWidget.saveWidgetData<String>("widget_day_items", dayItemsPayload);
      await HomeWidget.saveWidgetData<String>("widget_theme", themeKey);
      if (accentColorValue != null) {
        await HomeWidget.saveWidgetData<String>("widget_accent_color", accentColorValue.toString());
      } else {
        await HomeWidget.saveWidgetData<String>("widget_accent_color", "");
      }
    } catch (_) {}
    // Отдельные try/catch ниже: сбой на любом из шагов выше (например,
    // saveWidgetData для расписания) не должен блокировать применение
    // шрифта и обновление виджета — иначе ошибка молча "съедала" бы их.
    try {
      await _saveWidgetFontScale(fontScale);
    } catch (_) {}
    try {
      await _saveWidgetFont();
    } catch (_) {}
    try {
      await _saveWidgetDisplayFlags();
    } catch (_) {}
    try {
      await _bumpWidgetRefreshToken();
    } catch (_) {}
    await _forceRefreshWidget();
  }

  static Future<void> updateWidgetTheme({
    required String themeKey,
    required double fontScale,
    int? accentColorValue,
  }) async {
    try {
      await HomeWidget.saveWidgetData<String>("widget_theme", themeKey);
      if (accentColorValue != null) {
        await HomeWidget.saveWidgetData<String>("widget_accent_color", accentColorValue.toString());
      } else {
        await HomeWidget.saveWidgetData<String>("widget_accent_color", "");
      }
    } catch (_) {}
    try {
      await _saveWidgetFontScale(fontScale);
    } catch (_) {}
    try {
      await _saveWidgetFont();
    } catch (_) {}
    try {
      await _saveWidgetDisplayFlags();
    } catch (_) {}
    try {
      await _bumpWidgetRefreshToken();
    } catch (_) {}
    await _forceRefreshWidget();
  }

  /// Копирует флаги отображения из настроек приложения в хранилище виджета:
  /// показывать ли время пар, детали (ауд./преподаватель) и строку «Обновлено».
  static Future<void> _saveWidgetDisplayFlags() async {
    final sp = await SharedPreferences.getInstance();
    await HomeWidget.saveWidgetData<String>(
      "widget_show_time",
      (sp.getBool("widget_show_time") ?? true) ? "1" : "0",
    );
    await HomeWidget.saveWidgetData<String>(
      "widget_show_details",
      (sp.getBool("widget_show_details") ?? true) ? "1" : "0",
    );
    await HomeWidget.saveWidgetData<String>(
      "widget_show_footer",
      (sp.getBool("widget_show_footer") ?? true) ? "1" : "0",
    );
  }

  /// Передаёт виджету шрифт приложения. Виджет рисует текст сам через
  /// WidgetTextRenderer (Bitmap) и умеет все шрифты, для которых в
  /// android/app/src/main/res/font/ есть .ttf-файл — см. WidgetTextRenderer.typeface.
  static Future<void> _saveWidgetFont() async {
    final sp = await SharedPreferences.getInstance();
    final selected = sp.getString("selected_font") ?? "";
    final key = switch (selected) {
      "spaceGrotesk" || "spaceGroteskLocal" => "grotesk",
      "ndot77" => "ndot",
      "nunito" => "nunito",
      "jost" => "jost",
      "manrope" => "manrope",
      "robotoSlab" => "robotoSlab",
      _ => "",
    };
    await HomeWidget.saveWidgetData<String>("widget_font", key);
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

  /// Одна строка списка виджета: номер, время начала/конца, предмет и детали
  /// через U+241F. Kotlin-сторона (ScheduleWidgetFactory) парсит эти поля и
  /// сама подсвечивает текущую пару по времени.
  static String _blockRowForWidget(
    int lessonNumber,
    List<ScheduleItem> block,
    String college,
  ) {
    final sorted = block.toList()
      ..sort((a, b) => (a.subgroup ?? 0).compareTo(b.subgroup ?? 0));
    final subject = (sorted.first.subject ?? "—").trim();
    final time = LessonTimes.getTime(lessonNumber, college: college);
    final details = _blockDetailsForWidget(sorted);
    return [
      "$lessonNumber",
      time?.startTime ?? "",
      time?.endTime ?? "",
      subject,
      details,
    ].map(_sanitizeField).join(_fieldSeparator);
  }

  /// Разделители полей/строк не должны встречаться в пользовательских данных.
  static String _sanitizeField(String s) =>
      s.replaceAll(_fieldSeparator, " ").replaceAll(_itemSeparator, " ");

  /// Закончилась ли последняя пара дня (по временам пар колледжа).
  static bool _dayIsOver(DaySchedule day, String college, DateTime now) {
    var lastEndMinutes = -1;
    for (final item in day.items) {
      final t = LessonTimes.getTime(item.lessonNumber, college: college);
      if (t == null) continue;
      final end = LessonTimes.parseTimeToMinutes(t.endTime);
      if (end > lastEndMinutes) lastEndMinutes = end;
    }
    if (lastEndMinutes < 0) return false;
    return now.hour * 60 + now.minute >= lastEndMinutes;
  }

  static String _blockDetailsForWidget(List<ScheduleItem> block) {
    final lines = <String>[];
    for (final item in block) {
      final sg = item.subgroup;
      final detailParts = <String>[
        if (item.classroom?.isNotEmpty == true) "Ауд. ${item.classroom}",
        if (item.teacher?.isNotEmpty == true) item.teacher!,
      ];
      final detailStr = detailParts.join(" · ");
      if (sg != null) {
        lines.add("$sg п/г: ${detailStr.isEmpty ? "—" : detailStr}");
      } else if (detailStr.isNotEmpty) {
        lines.add(detailStr);
      }
    }
    return lines.join("\n");
  }
}
