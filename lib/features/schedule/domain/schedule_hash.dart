import "dart:convert";

import "../domain/models.dart";

String computeScheduleHash(List<DaySchedule> schedule) {
  try {
    final json = jsonEncode(schedule.map((d) => d.toJson()).toList());
    return "${json.length}:${json.hashCode}";
  } catch (_) {
    return "";
  }
}

