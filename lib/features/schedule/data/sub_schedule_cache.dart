import "dart:convert";

import "package:shared_preferences/shared_preferences.dart";

import "../domain/models.dart";

/// Кэш под-расписаний по ссылкам (кабинет/преподаватель/предмет).
class SubScheduleCache {
  SubScheduleCache(this._prefs);

  final SharedPreferences _prefs;
  static const _ttlHours = 24;

  String _key(String college, String file) => "sub_${college}_$file";
  String _tsKey(String college, String file) => "sub_ts_${college}_$file";

  void save(List<DaySchedule> schedule, String file, String college) {
    if (file.isEmpty || college.isEmpty || schedule.isEmpty) return;
    final json = jsonEncode(schedule.map((e) => e.toJson()).toList());
    _prefs.setString(_key(college, file), json);
    _prefs.setInt(_tsKey(college, file), DateTime.now().millisecondsSinceEpoch);
  }

  List<DaySchedule>? load(String file, String college) {
    if (file.isEmpty || college.isEmpty) return null;
    final ts = _prefs.getInt(_tsKey(college, file)) ?? 0;
    if (ts <= 0) return null;
    final age = (DateTime.now().millisecondsSinceEpoch - ts) / (1000 * 60 * 60);
    if (age > _ttlHours) return null;
    final raw = _prefs.getString(_key(college, file));
    if (raw == null || raw.isEmpty) return null;
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => DaySchedule.fromJson(e as Map<String, dynamic>))
          .toList();
      return list.isEmpty ? null : list;
    } catch (_) {
      return null;
    }
  }
}

