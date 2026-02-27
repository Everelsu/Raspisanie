import "dart:convert";

import "package:shared_preferences/shared_preferences.dart";

import "../domain/models.dart";

class ScheduleCache {
  ScheduleCache(this._prefs);

  final SharedPreferences _prefs;
  static const _expiryHours = 7 * 24;

  String _scheduleKey(String college, String groupFile) =>
      "schedule_${college}_$groupFile";

  String _timestampKey(String college, String groupFile) =>
      "timestamp_${college}_$groupFile";

  void save(List<DaySchedule> schedules, String groupFile, String college) {
    if (groupFile.isEmpty || college.isEmpty || schedules.isEmpty) return;
    final json = jsonEncode(schedules.map((e) => e.toJson()).toList());
    _prefs.setString(_scheduleKey(college, groupFile), json);
    _prefs.setInt(
        _timestampKey(college, groupFile), DateTime.now().millisecondsSinceEpoch);
  }

  List<DaySchedule>? load(String groupFile, String college) {
    if (groupFile.isEmpty || college.isEmpty) return null;
    final ts = _prefs.getInt(_timestampKey(college, groupFile)) ?? 0;
    if (ts <= 0) return null;
    final ageHours =
        (DateTime.now().millisecondsSinceEpoch - ts) / (1000 * 60 * 60);
    if (ageHours > _expiryHours) {
      clear(groupFile, college);
      return null;
    }
    final raw = _prefs.getString(_scheduleKey(college, groupFile));
    if (raw == null || raw.isEmpty) return null;
    final list = (jsonDecode(raw) as List)
        .map((e) => DaySchedule.fromJson(e as Map<String, dynamic>))
        .toList();
    return list.isEmpty ? null : list;
  }

  bool hasValid(String groupFile, String college) {
    if (groupFile.isEmpty || college.isEmpty) return false;
    final ts = _prefs.getInt(_timestampKey(college, groupFile)) ?? 0;
    if (ts <= 0) return false;
    final ageHours =
        (DateTime.now().millisecondsSinceEpoch - ts) / (1000 * 60 * 60);
    return ageHours <= _expiryHours;
  }

  void clear(String groupFile, String college) {
    _prefs.remove(_scheduleKey(college, groupFile));
    _prefs.remove(_timestampKey(college, groupFile));
  }

  void clearAll() {
    final keys = _prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith("schedule_") || key.startsWith("timestamp_")) {
        _prefs.remove(key);
      }
    }
  }

  void saveToHistory(
      List<DaySchedule> schedules, String groupFile, String college) {
    if (schedules.isEmpty) return;
    final histKey = "history_${college}_$groupFile";
    final existing = _prefs.getStringList(histKey) ?? [];
    final json = jsonEncode(schedules.map((e) => e.toJson()).toList());
    final entry = "${DateTime.now().millisecondsSinceEpoch}|$json";
    existing.add(entry);
    if (existing.length > 30) {
      existing.removeRange(0, existing.length - 30);
    }
    _prefs.setStringList(histKey, existing);
  }

  List<(DateTime date, List<DaySchedule> schedule)> loadHistory(
      String groupFile, String college) {
    final histKey = "history_${college}_$groupFile";
    final entries = _prefs.getStringList(histKey) ?? [];
    final result = <(DateTime, List<DaySchedule>)>[];
    for (final entry in entries) {
      final sep = entry.indexOf("|");
      if (sep < 0) continue;
      final ts = int.tryParse(entry.substring(0, sep));
      if (ts == null) continue;
      try {
        final json = jsonDecode(entry.substring(sep + 1)) as List;
        final days =
            json.map((e) => DaySchedule.fromJson(e as Map<String, dynamic>)).toList();
        result.add((DateTime.fromMillisecondsSinceEpoch(ts), days));
      } catch (_) {}
    }
    return result;
  }
}
