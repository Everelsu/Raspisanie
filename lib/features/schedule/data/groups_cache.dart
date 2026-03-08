import "dart:convert";

import "package:shared_preferences/shared_preferences.dart";

import "../domain/models.dart";

class GroupsCache {
  GroupsCache(this._prefs);

  final SharedPreferences _prefs;
  static const _ttlHours = 24;

  String _key(String college, String scope) => "groups_cache_${scope}_$college";
  String _tsKey(String college, String scope) => "groups_ts_${scope}_$college";

  void save(String college, List<Group> groups, {String scope = "groups"}) {
    final json = jsonEncode(groups.map((g) => g.toJson()).toList());
    _prefs.setString(_key(college, scope), json);
    _prefs.setInt(_tsKey(college, scope), DateTime.now().millisecondsSinceEpoch);
  }

  List<Group>? load(String college, {String scope = "groups"}) {
    final ts = _prefs.getInt(_tsKey(college, scope)) ?? 0;
    if (ts <= 0) return null;
    final age = (DateTime.now().millisecondsSinceEpoch - ts) / (1000 * 60 * 60);
    if (age > _ttlHours) return null;
    final raw = _prefs.getString(_key(college, scope));
    if (raw == null || raw.isEmpty) return null;
    return (jsonDecode(raw) as List)
        .map((e) => Group.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  void clear(String college, {String scope = "groups"}) {
    _prefs.remove(_key(college, scope));
    _prefs.remove(_tsKey(college, scope));
  }

  void clearAll() {
    final keys = _prefs.getKeys().toList();
    for (final key in keys) {
      if (key.startsWith("groups_cache_") || key.startsWith("groups_ts_")) {
        _prefs.remove(key);
      }
    }
  }

  /// Оставляет только [maxEntries] последних записей (college+scope) по времени.
  void trimToMaxEntries(int maxEntries) {
    final keys = _prefs.getKeys();
    final timestamps = <String, int>{};
    for (final key in keys) {
      if (key.startsWith("groups_ts_")) {
        final ts = _prefs.getInt(key);
        if (ts != null) timestamps[key] = ts;
      }
    }
    if (timestamps.length <= maxEntries) return;
    final sorted = timestamps.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (var i = maxEntries; i < sorted.length; i++) {
      final tsKey = sorted[i].key;
      final suffix = tsKey.substring("groups_ts_".length);
      final scopeCollege = suffix.split("_");
      if (scopeCollege.length >= 2) {
        final scope = scopeCollege[0];
        final college = scopeCollege.sublist(1).join("_");
        clear(college, scope: scope);
      }
    }
  }
}
