class LessonTime {
  const LessonTime(this.number, this.startTime, this.endTime);
  final int number;
  final String startTime;
  final String endTime;
}

class LessonTimes {
  static const _chtotib = <int, LessonTime>{
    1: LessonTime(1, "8:15", "9:15"),
    2: LessonTime(2, "9:25", "10:25"),
    3: LessonTime(3, "10:35", "11:35"),
    4: LessonTime(4, "12:15", "13:15"),
    5: LessonTime(5, "13:25", "14:25"),
    6: LessonTime(6, "14:35", "15:35"),
    7: LessonTime(7, "16:05", "17:05"),
    8: LessonTime(8, "17:15", "18:15"),
  };

  static const _zabgc = <int, LessonTime>{
    1: LessonTime(1, "8:30", "10:05"),
    2: LessonTime(2, "10:15", "11:50"),
    3: LessonTime(3, "12:30", "14:05"),
    4: LessonTime(4, "14:15", "15:50"),
    5: LessonTime(5, "16:00", "17:35"),
    6: LessonTime(6, "17:45", "19:20"),
  };

  static const _lunchesChtotib = <int, String>{
    3: "Обед: 11:35 - 12:15",
    6: "Обед: 15:35 - 16:05",
  };

  static const _lunchesZabgc = <int, String>{
    2: "Обед: 11:50 - 12:30",
  };

  static final _breaksChtotib = <(int, int), String>{
    (1, 2): "Перемена: 9:15 - 9:25",
    (2, 3): "Перемена: 10:25 - 10:35",
    (4, 5): "Перемена: 13:15 - 13:25",
    (5, 6): "Перемена: 14:25 - 14:35",
    (7, 8): "Перемена: 17:05 - 17:15",
  };

  static final _breaksZabgc = <(int, int), String>{
    (1, 2): "Перемена: 10:05 - 10:15",
    (3, 4): "Перемена: 14:05 - 14:15",
    (4, 5): "Перемена: 15:50 - 16:00",
    (5, 6): "Перемена: 17:35 - 17:45",
  };

  static Map<int, LessonTime> _forCollege(String college) =>
      college == "zabgc" ? _zabgc : _chtotib;

  static LessonTime? getTime(int lessonNumber, {String college = "chtotib"}) =>
      _forCollege(college)[lessonNumber];

  static String formatTime(int lessonNumber, {String college = "chtotib"}) {
    final t = getTime(lessonNumber, college: college);
    return t != null ? "${t.startTime} - ${t.endTime}" : "";
  }

  static String? getBreakText(int before, int after,
      {String college = "chtotib"}) {
    final breaks = college == "zabgc" ? _breaksZabgc : _breaksChtotib;
    return breaks[(before, after)];
  }

  static String? getLunchText(int afterLesson, {String college = "chtotib"}) {
    final lunches = college == "zabgc" ? _lunchesZabgc : _lunchesChtotib;
    return lunches[afterLesson];
  }

  static int parseTimeToMinutes(String timeStr) {
    final parts = timeStr.split(":");
    if (parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  static LessonStatus getLessonStatus(
    int lessonNumber,
    String college,
    DateTime now,
    String scheduleDate,
  ) {
    try {
      final parts = scheduleDate.split(".");
      if (parts.length != 3) return LessonStatus.none;
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);
      final date = DateTime(year, month, day);
      if (date.year != now.year ||
          date.month != now.month ||
          date.day != now.day) {
        if (date.isBefore(DateTime(now.year, now.month, now.day))) {
          return LessonStatus.past;
        }
        return LessonStatus.future;
      }
    } catch (_) {
      return LessonStatus.none;
    }

    final t = getTime(lessonNumber, college: college);
    if (t == null) return LessonStatus.none;

    final nowMin = now.hour * 60 + now.minute;
    final startMin = parseTimeToMinutes(t.startTime);
    final endMin = parseTimeToMinutes(t.endTime);

    if (nowMin >= startMin && nowMin < endMin) return LessonStatus.current;
    if (nowMin < startMin) {
      final diff = startMin - nowMin;
      if (diff <= 30) return LessonStatus.next;
      return LessonStatus.future;
    }
    return LessonStatus.past;
  }
}

enum LessonStatus { current, next, past, future, none }
