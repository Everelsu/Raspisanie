import "dart:convert";

import "package:shared_preferences/shared_preferences.dart";

import "../domain/models.dart";

class ScheduleCache {
  ScheduleCache(this._prefs);

  final SharedPreferences _prefs;
  static const _expiryHours = 7 * 24;

  String _scheduleKey(String college, String groupFile) =>
      "schedule_${college}_$groupFile";

  String _firstDayKey(String college, String groupFile) =>
      "schedule_first_${college}_$groupFile";

  String _timestampKey(String college, String groupFile) =>
      "timestamp_${college}_$groupFile";

  void save(List<DaySchedule> schedules, String groupFile, String college) {
    if (groupFile.isEmpty || college.isEmpty || schedules.isEmpty) return;
    final json = jsonEncode(schedules.map((e) => e.toJson()).toList());
    _prefs.setString(_scheduleKey(college, groupFile), json);
    try {
      final first = _pickFirstDayForFastPreview(schedules);
      _prefs.setString(_firstDayKey(college, groupFile), jsonEncode(first.toJson()));
    } catch (_) {}
    _prefs.setInt(
        _timestampKey(college, groupFile), DateTime.now().millisecondsSinceEpoch);
  }

  DaySchedule? loadFirstDay(String groupFile, String college) {
    if (groupFile.isEmpty || college.isEmpty) return null;
    final ts = _prefs.getInt(_timestampKey(college, groupFile)) ?? 0;
    if (ts <= 0) return null;
    final ageHours =
        (DateTime.now().millisecondsSinceEpoch - ts) / (1000 * 60 * 60);
    if (ageHours > _expiryHours) {
      clear(groupFile, college);
      return null;
    }
    final raw = _prefs.getString(_firstDayKey(college, groupFile));
    if (raw == null || raw.isEmpty) return null;
    try {
      return DaySchedule.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
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
    _prefs.remove(_firstDayKey(college, groupFile));
    _prefs.remove(_timestampKey(college, groupFile));
    _prefs.remove("history_${college}_$groupFile");
  }

  void clearAll() {
    final keys = _prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith("schedule_") || key.startsWith("timestamp_")) {
        _prefs.remove(key);
      }
    }
  }

  static const _maxHistoryEntries = 15;

  void saveToHistory(
      List<DaySchedule> schedules, String groupFile, String college) {
    if (schedules.isEmpty) return;
    final histKey = "history_${college}_$groupFile";
    final existing = _prefs.getStringList(histKey) ?? [];
    final json = jsonEncode(schedules.map((e) => e.toJson()).toList());
    final entry = "${DateTime.now().millisecondsSinceEpoch}|$json";
    existing.add(entry);
    if (existing.length > _maxHistoryEntries) {
      existing.removeRange(0, existing.length - _maxHistoryEntries);
    }
    _prefs.setStringList(histKey, existing);
  }

  /// Оставляет в кэше только [maxPairs] последних пар (college, groupFile) по времени.
  void trimToMaxEntries(int maxPairs) {
    final keys = _prefs.getKeys();
    final timestamps = <String, int>{};
    for (final key in keys) {
      if (key.startsWith("timestamp_")) {
        final ts = _prefs.getInt(key);
        if (ts != null) timestamps[key] = ts;
      }
    }
    if (timestamps.length <= maxPairs) return;
    final sorted = timestamps.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (var i = maxPairs; i < sorted.length; i++) {
      final key = sorted[i].key;
      final suffix = key.substring("timestamp_".length);
      final lastUnderscore = suffix.lastIndexOf("_");
      if (lastUnderscore <= 0) continue;
      final college = suffix.substring(0, lastUnderscore);
      final groupFile = suffix.substring(lastUnderscore + 1);
      clear(groupFile, college);
    }
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

  static DaySchedule _pickFirstDayForFastPreview(List<DaySchedule> schedules) {
    if (schedules.isEmpty) {
      return const DaySchedule(
        day: "",
        date: "",
        weekNumber: 0,
        items: <ScheduleItem>[],
      );
    }
    final now = DateTime.now();
    final today =
        "${now.day.toString().padLeft(2, "0")}.${now.month.toString().padLeft(2, "0")}.${now.year}";
    final todayNonEmpty = schedules.where((d) => d.date == today && d.items.isNotEmpty);
    if (todayNonEmpty.isNotEmpty) return todayNonEmpty.first;
    final anyNonEmpty = schedules.where((d) => d.items.isNotEmpty);
    if (anyNonEmpty.isNotEmpty) return anyNonEmpty.first;
    return schedules.first;
  }
}
