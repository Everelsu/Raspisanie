import "dart:convert";

import "package:shared_preferences/shared_preferences.dart";

import "../domain/models.dart";

/// Кэш расписания в SharedPreferences.
///
/// Формат **v2** (`sched_v2_`): один ключ с JSON `{"t": мс, "d": [DaySchedule…]}` —
/// меньше фрагментации и одно чтение вместо отдельной строки расписания.
/// Старый формат (`schedule_` + `timestamp_`) поддерживается при загрузке.
class ScheduleCache {
  ScheduleCache(this._prefs);

  final SharedPreferences _prefs;
  static const _expiryHours = 7 * 24;

  String _scheduleKey(String college, String groupFile) =>
      "schedule_${college}_$groupFile";

  String _bundleKey(String college, String groupFile) =>
      "sched_v2_${college}_$groupFile";

  String _firstDayKey(String college, String groupFile) =>
      "schedule_first_${college}_$groupFile";

  String _timestampKey(String college, String groupFile) =>
      "timestamp_${college}_$groupFile";

  bool _isExpired(int tsMs) {
    if (tsMs <= 0) return true;
    final ageHours =
        (DateTime.now().millisecondsSinceEpoch - tsMs) / (1000 * 60 * 60);
    return ageHours > _expiryHours;
  }

  /// [encodedDays] — уже готовый JSON-массив дней (сериализован в изоляте
  /// вместе с разбором), чтобы не кодировать расписание в UI-потоке.
  void save(List<DaySchedule> schedules, String groupFile, String college,
      {String? encodedDays}) {
    if (groupFile.isEmpty || college.isEmpty || schedules.isEmpty) return;
    final t = DateTime.now().millisecondsSinceEpoch;
    final daysJson =
        encodedDays ?? jsonEncode(schedules.map((e) => e.toJson()).toList());
    final payload = '{"t":$t,"d":$daysJson}';
    _prefs.setString(_bundleKey(college, groupFile), payload);
    _prefs.remove(_scheduleKey(college, groupFile));
    try {
      final first = _pickFirstDayForFastPreview(schedules);
      _prefs.setString(
        _firstDayKey(college, groupFile),
        jsonEncode(first.toJson()),
      );
    } catch (_) {}
    _prefs.setInt(_timestampKey(college, groupFile), t);
  }

  DaySchedule? loadFirstDay(String groupFile, String college) {
    if (groupFile.isEmpty || college.isEmpty) return null;
    final ts = _prefs.getInt(_timestampKey(college, groupFile)) ?? 0;
    if (_isExpired(ts)) {
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
    // При просрочке возвращаем null, но данные НЕ удаляем — они пригодятся
    // как аварийный фолбэк при отсутствии сети (см. loadAllowingExpired).
    // Реальная очистка — в StorageCleanup.
    if (_isExpired(ts)) return null;

    return _loadRaw(groupFile, college);
  }

  /// Возвращает кэш даже если он просрочен.
  /// Используется как крайний фолбэк когда сеть недоступна.
  List<DaySchedule>? loadAllowingExpired(String groupFile, String college) {
    if (groupFile.isEmpty || college.isEmpty) return null;
    final ts = _prefs.getInt(_timestampKey(college, groupFile)) ?? 0;
    if (ts <= 0) return null;
    return _loadRaw(groupFile, college);
  }

  List<DaySchedule>? _loadRaw(String groupFile, String college) {
    final bundled = _prefs.getString(_bundleKey(college, groupFile));
    if (bundled != null && bundled.isNotEmpty) {
      final days = _decodeBundleDays(bundled);
      if (days != null && days.isNotEmpty) return days;
    }

    final raw = _prefs.getString(_scheduleKey(college, groupFile));
    if (raw == null || raw.isEmpty) return null;
    final list = _decodeDaysList(raw);
    return list.isEmpty ? null : list;
  }

  List<DaySchedule> _decodeDaysList(String raw) {
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => DaySchedule.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const <DaySchedule>[];
    }
  }

  List<DaySchedule>? _decodeBundleDays(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final list = map["d"] as List?;
      if (list == null) return null;
      return list
          .map((e) => DaySchedule.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  bool hasValid(String groupFile, String college) {
    if (groupFile.isEmpty || college.isEmpty) return false;
    final ts = _prefs.getInt(_timestampKey(college, groupFile)) ?? 0;
    if (ts <= 0) return false;
    return !_isExpired(ts);
  }

  void clear(String groupFile, String college) {
    _prefs.remove(_bundleKey(college, groupFile));
    _prefs.remove(_scheduleKey(college, groupFile));
    _prefs.remove(_firstDayKey(college, groupFile));
    _prefs.remove(_timestampKey(college, groupFile));
    _prefs.remove("history_${college}_$groupFile");
  }

  void clearAll() {
    final keys = _prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith("sched_v2_") ||
          key.startsWith("schedule_") ||
          key.startsWith("timestamp_") ||
          key.startsWith("history_")) {
        _prefs.remove(key);
      }
    }
  }

  /// Удаляет записи, у которых кэш старше удвоенного срока ([_expiryHours] × 2).
  /// Вызывается из StorageCleanup, а не из [load] — чтобы данные оставались
  /// доступными как аварийный фолбэк при отсутствии сети.
  void clearExpiredEntries() {
    final keys = _prefs.getKeys().toList();
    for (final key in keys) {
      if (!key.startsWith("timestamp_")) continue;
      final ts = _prefs.getInt(key) ?? 0;
      final ageHours =
          (DateTime.now().millisecondsSinceEpoch - ts) / (1000 * 60 * 60);
      // Удаляем только то, что в два раза старше нормального срока
      if (ageHours <= _expiryHours * 2) continue;
      final suffix = key.substring("timestamp_".length);
      final sep = suffix.lastIndexOf("_");
      if (sep <= 0) continue;
      final college = suffix.substring(0, sep);
      final groupFile = suffix.substring(sep + 1);
      clear(groupFile, college);
    }
  }

  /// Раньше каждая загрузка из сети дописывала полную копию расписания в
  /// `history_*` (до 15 на группу), но читать их было некому — история в
  /// SQLite. SharedPreferences на Android целиком парсятся в память при
  /// старте, так что эти мегабайты тормозили каждый запуск. Удаляем остатки.
  void dropLegacyHistory() {
    for (final key in _prefs.getKeys().toList()) {
      if (key.startsWith("history_")) _prefs.remove(key);
    }
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
    final todayNonEmpty =
        schedules.where((d) => d.date == today && d.items.isNotEmpty);
    if (todayNonEmpty.isNotEmpty) return todayNonEmpty.first;
    final anyNonEmpty = schedules.where((d) => d.items.isNotEmpty);
    if (anyNonEmpty.isNotEmpty) return anyNonEmpty.first;
    return schedules.first;
  }
}
