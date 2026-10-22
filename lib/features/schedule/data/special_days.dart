import "dart:convert";

import "holidays.dart";
import "lesson_times.dart";

/// Особый день из Firebase Remote Config (`special_days`): сокращённый день
/// со своим временем пар, праздник, каникулы — на дату или диапазон дат,
/// для всех техникумов или только для перечисленных.
class SpecialDay {
  const SpecialDay({
    required this.from,
    required this.to,
    required this.kind,
    required this.title,
    this.note,
    this.emoji,
    this.color,
    this.colleges,
    this.times = const {},
    this.noClasses = false,
  });

  final DateTime from;
  final DateTime to;

  /// `short` — сокращённый день, `holiday` — праздник/выходной, `info` — просто
  /// пометка (например, «Пары по расписанию субботы»).
  final String kind;
  final String title;
  final String? note;
  final String? emoji;
  final int? color;

  /// null — для всех техникумов.
  final Set<String>? colleges;

  /// Время пар этого дня по техникумам; ключ null — для всех.
  final Map<String?, Map<int, LessonTime>> times;
  final bool noClasses;

  bool covers(DateTime date, String college) {
    final d = DateTime(date.year, date.month, date.day);
    if (d.isBefore(from) || d.isAfter(to)) return false;
    return colleges == null || colleges!.contains(college);
  }

  Map<int, LessonTime>? timesFor(String college) =>
      times[college] ?? times[null];

  /// Для карточки дня — в том же виде, что и встроенные праздники.
  Holiday asHoliday(DateTime date) => Holiday(
        day: date.day,
        month: date.month,
        name: title,
        emoji: emoji ??
            switch (kind) {
              "short" => "⏱️",
              "holiday" => "🎉",
              _ => "📌",
            },
        color: color ??
            switch (kind) {
              "short" => 0xFFFF9F1C,
              "holiday" => 0xFFFF5A5F,
              _ => 0xFF5AC8FA,
            },
        note: note ?? (noClasses ? "Пар нет" : null),
      );
}

/// Реестр особых дней: заполняется из Remote Config (через prefs, чтобы
/// фоновые изоляты — воркер и виджет — тоже его видели).
abstract final class SpecialDays {
  static List<SpecialDay> _days = const [];

  static void load(List<SpecialDay> days) => _days = days;

  static SpecialDay? forDate(DateTime date, String college) {
    for (final d in _days) {
      if (d.covers(date, college)) return d;
    }
    return null;
  }

  /// Дата расписания в любом из форматов сайтов (`DD.MM.YYYY`, `YYYY-MM-DD`).
  static SpecialDay? forRawDate(String? raw, String college) {
    if (raw == null) return null;
    final date = Holidays.parseRawDate(raw);
    return date == null ? null : forDate(date, college);
  }

  /// Плашка для карточки дня: особый день из Remote Config (всегда — это
  /// важная информация), иначе встроенный праздник, если они включены.
  static Holiday? cardFor(String rawDate, String college,
      {required bool builtInHolidays}) {
    final date = Holidays.parseRawDate(rawDate);
    if (date == null) return null;
    final special = forDate(date, college);
    if (special != null) return special.asHoliday(date);
    return builtInHolidays ? Holidays.forDate(date) : null;
  }

  /// Разбор значения `special_days`. Ключ — дата `YYYY-MM-DD` или диапазон
  /// `YYYY-MM-DD..YYYY-MM-DD`; ключ `presets` — именованные наборы времени.
  /// Битые записи пропускаются, а не роняют всё. Примеры всех форматов —
  /// `tool/remote_config/README.md`.
  ///
  /// ```json
  /// {
  ///   "2026-12-31": {
  ///     "kind": "short", "title": "Сокращённый день", "note": "Пары по 1 часу",
  ///     "colleges": ["chtotib"],
  ///     "times": { "1": { "start": "08:15", "end": "09:15" } }
  ///   },
  ///   "2026-12-29..2027-01-11": {
  ///     "kind": "holiday", "title": "Зимние каникулы", "noClasses": true
  ///   }
  /// }
  /// ```
  static const presetsKey = "presets";

  static List<SpecialDay> parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const [];
    }
    if (decoded is! Map<String, dynamic>) return const [];
    // Именованные наборы времени (например, сокращёнка по астрономическому
    // часу): задаются один раз, дни ссылаются на них `"times": "имя"`.
    final presets = <String, Map<String?, Map<int, LessonTime>>>{};
    final presetsRaw = decoded[presetsKey];
    if (presetsRaw is Map<String, dynamic>) {
      for (final p in presetsRaw.entries) {
        presets[p.key] = _parseTimes(p.value);
      }
    }
    final out = <SpecialDay>[];
    for (final e in decoded.entries) {
      if (e.key == presetsKey) continue;
      final v = e.value;
      if (v is! Map<String, dynamic>) continue;
      final range = _parseRange(e.key);
      if (range == null) continue;
      final title = (v["title"] as String?)?.trim();
      if (title == null || title.isEmpty) continue;
      final colleges = (v["colleges"] as List?)
          ?.whereType<String>()
          .map((c) => c.trim().toLowerCase())
          .toSet();
      out.add(SpecialDay(
        from: range.$1,
        to: range.$2,
        kind: (v["kind"] as String?)?.trim() ?? "info",
        title: title,
        note: (v["note"] as String?)?.trim(),
        emoji: (v["emoji"] as String?)?.trim(),
        color: _parseColor(v["color"]),
        colleges: (colleges == null || colleges.isEmpty) ? null : colleges,
        times: v["times"] is String
            ? (presets[v["times"]] ?? const {})
            : _parseTimes(v["times"]),
        noClasses: v["noClasses"] == true,
      ));
    }
    // Узкие записи (один день) важнее широких (каникулы) — проверяем первыми.
    out.sort(
        (a, b) => a.to.difference(a.from).compareTo(b.to.difference(b.from)));
    return out;
  }

  static (DateTime, DateTime)? _parseRange(String key) {
    final parts = key.split("..");
    final from = _strictDate(parts.first);
    final to = parts.length > 1 ? _strictDate(parts[1]) : from;
    if (from == null || to == null || to.isBefore(from)) return null;
    return (from, to);
  }

  /// Дата без «переноса»: DateTime(2026, 31, 12) молча дал бы июль 2028,
  /// и перепутанные день с месяцем показали бы особый день не в ту дату.
  static DateTime? _strictDate(String raw) {
    final d = Holidays.parseRawDate(raw);
    if (d == null) return null;
    final nums = raw.trim().split(RegExp(r"[.-]")).map(int.tryParse).toList();
    if (nums.length != 3 || nums.contains(null)) return null;
    final iso = raw.contains("-");
    final (y, m, day) =
        iso ? (nums[0]!, nums[1]!, nums[2]!) : (nums[2]!, nums[1]!, nums[0]!);
    return (d.year == y && d.month == m && d.day == day) ? d : null;
  }

  /// `times` — либо сразу номера пар (для всех техникумов дня), либо по
  /// техникумам: `{ "chtotib": { "1": {…} } }`.
  static Map<String?, Map<int, LessonTime>> _parseTimes(Object? raw) {
    if (raw is! Map<String, dynamic> || raw.isEmpty) return const {};
    final flat = raw.keys.every((k) => int.tryParse(k) != null);
    if (flat) {
      final t = LessonTimes.parseTimes(raw);
      return t.isEmpty ? const {} : {null: t};
    }
    return {
      for (final e in LessonTimes.parseByCollege(raw).entries) e.key: e.value,
    };
  }

  static int? _parseColor(Object? raw) {
    if (raw is! String) return null;
    final hex = raw.trim().replaceFirst("#", "");
    final v = int.tryParse(hex, radix: 16);
    if (v == null) return null;
    return hex.length <= 6 ? 0xFF000000 | v : v;
  }
}
