import "dart:convert";

import "package:shared_preferences/shared_preferences.dart";

import "../domain/models.dart";

class StatisticsCache {
  StatisticsCache(this._prefs);

  final SharedPreferences _prefs;
  static const _ttlHours = 24;

  String _key(String college, String groupFile) =>
      "stats_${college}_$groupFile";
  String _tsKey(String college, String groupFile) =>
      "stats_ts_${college}_$groupFile";

  void save(GroupStatistics stats, String groupFile, String college) {
    if (groupFile.isEmpty || college.isEmpty) return;
    final json = jsonEncode(stats.toJson());
    _prefs.setString(_key(college, groupFile), json);
    _prefs.setInt(_tsKey(college, groupFile), DateTime.now().millisecondsSinceEpoch);
  }

  GroupStatistics? load(String groupFile, String college) {
    if (groupFile.isEmpty || college.isEmpty) return null;
    final ts = _prefs.getInt(_tsKey(college, groupFile)) ?? 0;
    if (ts <= 0) return null;
    final age = (DateTime.now().millisecondsSinceEpoch - ts) / (1000 * 60 * 60);
    if (age > _ttlHours) return null;
    final raw = _prefs.getString(_key(college, groupFile));
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return GroupStatistics.fromJson(map);
    } catch (_) {
      return null;
    }
  }
}

