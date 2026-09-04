/// Праздник с фиксированной датой (день/месяц) — карточка в расписании.
class Holiday {
  const Holiday({
    required this.day,
    required this.month,
    required this.name,
    required this.emoji,
    required this.color,
    this.note,
    this.official = true,
  });

  final int day;
  final int month;
  final String name;
  final String emoji;

  /// ARGB-акцент карточки. Не берём цвет темы: праздники узнаются по цвету.
  final int color;

  /// Короткая подпись под названием.
  final String? note;

  /// Государственный/установленный праздник. У неофициальных карточка
  /// подписывается отдельно, чтобы их не путали с выходными.
  final bool official;

  /// Что писать под названием: своя подпись, иначе пометка неофициального.
  String? get subtitle => note ?? (official ? null : "Неофициальный праздник");
}

/// Календарь праздников для карточек дня.
///
/// Только фиксированные даты — переходящие (Пасха, дни города) считать
/// негде, а ошибиться в них хуже, чем не показать.
class Holidays {
  const Holidays._();

  static const all = <Holiday>[
    Holiday(
      day: 1,
      month: 1,
      name: "Новый год",
      emoji: "🎄",
      color: 0xFF4CAF50,
    ),
    Holiday(
      day: 7,
      month: 1,
      name: "Рождество Христово",
      emoji: "⭐",
      color: 0xFF64B5F6,
    ),
    Holiday(
      day: 25,
      month: 1,
      name: "Татьянин день",
      emoji: "🎓",
      color: 0xFF7E57C2,
      note: "День российского студенчества",
    ),
    Holiday(
      day: 14,
      month: 2,
      name: "День святого Валентина",
      emoji: "❤️",
      color: 0xFFE91E63,
      official: false,
    ),
    Holiday(
      day: 23,
      month: 2,
      name: "День защитника Отечества",
      emoji: "🎖️",
      color: 0xFF43A047,
    ),
    Holiday(
      day: 8,
      month: 3,
      name: "Международный женский день",
      emoji: "🌷",
      color: 0xFFEC407A,
    ),
    Holiday(
      day: 1,
      month: 4,
      name: "День смеха",
      emoji: "🃏",
      color: 0xFFFFA726,
      official: false,
    ),
    Holiday(
      day: 12,
      month: 4,
      name: "День космонавтики",
      emoji: "🚀",
      color: 0xFF3F51B5,
    ),
    Holiday(
      day: 1,
      month: 5,
      name: "Праздник Весны и Труда",
      emoji: "🌿",
      color: 0xFF66BB6A,
    ),
    Holiday(
      day: 9,
      month: 5,
      name: "День Победы",
      emoji: "🎗️",
      color: 0xFFEF5350,
    ),
    Holiday(
      day: 1,
      month: 6,
      name: "День защиты детей",
      emoji: "🎈",
      color: 0xFF29B6F6,
    ),
    Holiday(
      day: 12,
      month: 6,
      name: "День России",
      emoji: "🇷🇺",
      color: 0xFF5C6BC0,
    ),
    Holiday(
      day: 27,
      month: 6,
      name: "День молодёжи",
      emoji: "🎉",
      color: 0xFF26A69A,
    ),
    Holiday(
      day: 1,
      month: 9,
      name: "День знаний",
      emoji: "🎒",
      color: 0xFFFF9800,
      note: "С началом учебного года!",
    ),
    Holiday(
      day: 5,
      month: 10,
      name: "День учителя",
      emoji: "🍎",
      color: 0xFFEF6C00,
    ),
    Holiday(
      day: 2,
      month: 10,
      name: "День профтехобразования",
      emoji: "🛠️",
      color: 0xFF8D6E63,
      note: "Праздник СПО",
    ),
    Holiday(
      day: 6,
      month: 10,
      name: "День разработчика",
      emoji: "💻",
      color: 0xFF00ACC1,
      official: false,
    ),
    Holiday(
      day: 4,
      month: 11,
      name: "День народного единства",
      emoji: "🤝",
      color: 0xFF5E35B1,
    ),
    Holiday(
      day: 17,
      month: 11,
      name: "Международный день студентов",
      emoji: "📚",
      color: 0xFF00897B,
    ),
    Holiday(
      day: 31,
      month: 12,
      name: "Канун Нового года",
      emoji: "🎆",
      color: 0xFF26C6DA,
    ),
  ];

  /// Праздник на дату расписания. Поддерживает оба формата, которые
  /// приходят с сайтов: `DD.MM.YYYY` и `YYYY-MM-DD`.
  static Holiday? forRawDate(String raw) {
    final parsed = parseRawDate(raw);
    return parsed == null ? null : forDate(parsed);
  }

  static Holiday? forDate(DateTime date) {
    for (final holiday in all) {
      if (holiday.day == date.day && holiday.month == date.month) {
        return holiday;
      }
    }
    return null;
  }

  static DateTime? parseRawDate(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    try {
      if (value.contains(".")) {
        final p = value.split(".");
        if (p.length != 3) return null;
        return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
      }
      if (value.contains("-")) {
        final p = value.split("-");
        if (p.length != 3) return null;
        return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
