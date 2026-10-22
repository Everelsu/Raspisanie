import "dart:convert";

import "package:flutter/foundation.dart";

import "../../../core/database/schedule_database.dart";
import "../../../core/network/http_client.dart";
import "../../../core/parsing/encoding_decoder.dart";
import "../../../core/parsing/express_parser.dart";
import "../../../core/parsing/statistics_parser.dart";
import "../domain/models.dart";
import "groups_cache.dart";
import "schedule_cache.dart";
import "statistics_cache.dart";
import "sub_schedule_cache.dart";

class ExpressScheduleRepository {
  ExpressScheduleRepository({
    HttpClientService? client,
    this.scheduleCache,
    this.groupsCache,
    this.statisticsCache,
    this.subScheduleCache,
  }) : _client = client ?? HttpClientService();

  final HttpClientService _client;
  final ScheduleCache? scheduleCache;
  final GroupsCache? groupsCache;
  final StatisticsCache? statisticsCache;
  final SubScheduleCache? subScheduleCache;
  final Map<String, Future<List<DaySchedule>>> _inflightSchedule = {};
  final Set<String> _backgroundRefreshing = {};
  final Map<String, DateTime> _lastBackgroundRefresh = {};
  final Map<String, String> _lastSnapshotJson = {};
  Map<String, String> _customBaseUrls = const {};
  static const _backgroundRefreshThrottle = Duration(minutes: 2);

  /// Свежее расписание из фонового обновления — после того как
  /// [fetchSchedule] уже отдал кэш. Без него новые данные оседали только
  /// в кэше, и экран показывал старое до ручного pull-to-refresh.
  void Function(String groupFile, String college, List<DaySchedule> days)?
      onBackgroundSchedule;

  static const baseUrls = <String, String>{
    "chtotib": "https://www.chtotib.ru/schedule_gl/",
    "zabgc": "https://bbb.zabgc.ru/",
  };

  void setCustomBaseUrls(Map<String, String> urls) {
    _customBaseUrls = Map<String, String>.from(urls);
  }

  String baseUrlFor(String college) =>
      _customBaseUrls[college] ?? baseUrls[college] ?? baseUrls["chtotib"]!;

  Future<List<Group>> fetchGroups({
    required String college,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = groupsCache?.load(college, scope: "groups");
      if (cached != null && cached.isNotEmpty) return cached;
    }

    final base = baseUrlFor(college);
    for (final page in ["cg.htm", "bg.htm"]) {
      try {
        final response = await _client.getBytes("$base$page");
        if (response.statusCode < 200 || response.statusCode >= 300) continue;
        final groups = await compute(
            _parseGroupsIsolate, (response.bodyBytes, response.headers, base));
        if (groups.isNotEmpty) {
          groupsCache?.save(college, groups, scope: "groups");
          return groups;
        }
      } catch (_) {}
    }

    throw StateError("Не удалось получить список групп.");
  }

  Future<List<DaySchedule>> fetchSchedule({
    required String groupFile,
    required String college,
    bool useCache = true,
  }) async {
    final key = "$college::$groupFile";
    final running = _inflightSchedule[key];
    if (running != null) return running;

    Future<List<DaySchedule>> loader() async {
      if (useCache) {
        final cached = scheduleCache?.load(groupFile, college);
        if (cached != null && cached.isNotEmpty) {
          _refreshInBackground(groupFile, college);
          return cached;
        }
      }

      return _fetchFromNetwork(groupFile, college);
    }

    final future = loader();
    _inflightSchedule[key] = future;
    try {
      return await future;
    } finally {
      _inflightSchedule.remove(key);
    }
  }

  bool _scheduleChanged = false;
  bool get scheduleChanged => _scheduleChanged;
  void clearChangedFlag() => _scheduleChanged = false;

  Future<List<DaySchedule>> _fetchFromNetwork(
      String groupFile, String college) async {
    final base = baseUrlFor(college);
    final url = "$base$groupFile";

    final response = await _client.getBytes(url);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError("HTTP ${response.statusCode} при загрузке расписания.");
    }

    final (days, daysJson) = await compute(
        _parseScheduleJsonIsolate, (response.bodyBytes, response.headers));
    if (days.isEmpty) {
      final cached = scheduleCache?.loadAllowingExpired(groupFile, college);
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
      throw StateError("Не удалось распознать расписание с сайта.");
    }
    if (days.isNotEmpty) {
      final oldCached = scheduleCache?.load(groupFile, college);
      if (oldCached != null && oldCached.isNotEmpty) {
        _scheduleChanged = _fingerprint(oldCached) != _fingerprint(days);
      }
      scheduleCache?.save(days, groupFile, college, encodedDays: daysJson);
      // Тот же ответ, что в прошлый раз (автообновление, фоновый рефреш) —
      // в SQLite не пишем: снапшот был бы точной копией предыдущего.
      final snapKey = "$college::$groupFile";
      if (_lastSnapshotJson[snapKey] != daysJson) {
        await ScheduleDatabase.instance.saveScheduleSnapshot(
          groupFile,
          college,
          daysJson,
          parsedDays: days,
        );
        _lastSnapshotJson[snapKey] = daysJson;
      }
    }
    return days;
  }

  Future<GroupStatistics?> fetchStatistics({
    required String groupFile,
    required String college,
  }) async {
    final cached = statisticsCache?.load(groupFile, college);
    if (cached != null) {
      // Тихо обновим статистику в фоне, чтобы кэш не устаревал.
      _refreshStatisticsInBackground(groupFile: groupFile, college: college);
      return cached;
    }
    final base = baseUrlFor(college);
    String statsFile;
    if (groupFile.startsWith("cp")) {
      statsFile = groupFile.replaceFirst("cp", "vp");
    } else if (groupFile.startsWith("cg")) {
      statsFile = groupFile.replaceFirst("cg", "vg");
    } else if (groupFile.startsWith("bg")) {
      statsFile = groupFile.replaceFirst("bg", "vg");
    } else {
      statsFile = "vg${groupFile.replaceAll(RegExp(r'^[a-z]+'), '')}";
    }
    final url = "$base$statsFile";

    try {
      final response = await _client.getBytes(url);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final parsed = await compute(
          _parseStatsIsolate, (response.bodyBytes, response.headers));
      if (parsed != null) {
        statisticsCache?.save(parsed, groupFile, college);
      }
      return parsed;
    } catch (_) {
      return null;
    }
  }

  Future<List<Group>> fetchTeachers({
    required String college,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = groupsCache?.load(college, scope: "teachers");
      if (cached != null && cached.isNotEmpty) return cached;
    }
    final base = baseUrlFor(college);
    try {
      final response = await _client.getBytes("${base}cp.htm");
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError("HTTP ${response.statusCode}");
      }
      final teachers = await compute(
          _parseTeachersIsolate, (response.bodyBytes, response.headers, base));
      if (teachers.isNotEmpty) {
        groupsCache?.save(college, teachers, scope: "teachers");
      }
      return teachers;
    } catch (_) {
      throw StateError("Не удалось получить список преподавателей.");
    }
  }

  Future<List<DaySchedule>> fetchSubSchedule({
    required String file,
    required String college,
  }) async {
    final base = baseUrlFor(college);
    final url = "$base$file";
    final response = await _client.getBytes(url);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError("HTTP ${response.statusCode}");
    }
    final days = await compute(
        _parseScheduleIsolate, (response.bodyBytes, response.headers));
    if (days.isEmpty) {
      throw StateError("Не удалось распознать подрасписание.");
    }
    subScheduleCache?.save(days, file, college);
    return days;
  }

  void _refreshStatisticsInBackground({
    required String groupFile,
    required String college,
  }) {
    final key = "stats::$college::$groupFile";
    final now = DateTime.now();
    final lastStartedAt = _lastBackgroundRefresh[key];
    if (lastStartedAt != null &&
        now.difference(lastStartedAt) < _backgroundRefreshThrottle) {
      return;
    }
    if (_backgroundRefreshing.contains(key)) return;
    _backgroundRefreshing.add(key);
    _lastBackgroundRefresh[key] = now;
    () async {
      try {
        await fetchStatistics(groupFile: groupFile, college: college);
      } catch (_) {}
      _backgroundRefreshing.remove(key);
    }();
  }

  Future<void> _refreshInBackground(String groupFile, String college) async {
    final key = "$college::$groupFile";
    final now = DateTime.now();
    final lastStartedAt = _lastBackgroundRefresh[key];
    if (lastStartedAt != null &&
        now.difference(lastStartedAt) < _backgroundRefreshThrottle) {
      return;
    }
    if (_backgroundRefreshing.contains(key)) return;

    _backgroundRefreshing.add(key);
    _lastBackgroundRefresh[key] = now;
    try {
      final days = await _fetchFromNetwork(groupFile, college);
      onBackgroundSchedule?.call(groupFile, college, days);
    } catch (_) {
    } finally {
      _backgroundRefreshing.remove(key);
    }
  }

  static int _fingerprint(List<DaySchedule> days) {
    var hash = days.length;
    for (final d in days) {
      hash = hash ^ d.date.hashCode ^ d.day.hashCode ^ d.items.length;
      for (final i in d.items) {
        hash = hash ^
            i.lessonNumber ^
            (i.subject?.hashCode ?? 0) ^
            (i.classroom?.hashCode ?? 0) ^
            (i.teacher?.hashCode ?? 0) ^
            (i.subgroup ?? 0);
      }
    }
    return hash;
  }

  // Декодирование cp1251 и разбор HTML — в отдельном изоляте: страницы
  // колледжа большие, в главном потоке это были десятки мс фриза UI.
  static String _html((List<int>, Map<String, String>) page) =>
      EncodingDecoder().decode(bytes: page.$1, headers: page.$2).html;

  static List<DaySchedule> _parseScheduleIsolate(
          (List<int>, Map<String, String>) page) =>
      ExpressScheduleParser().parseSchedulePage(_html(page));

  /// Разбор + сериализация в JSON для кэша и SQLite — тоже вне UI-потока.
  static (List<DaySchedule>, String) _parseScheduleJsonIsolate(
      (List<int>, Map<String, String>) page) {
    final days = _parseScheduleIsolate(page);
    return (days, jsonEncode(days.map((e) => e.toJson()).toList()));
  }

  static GroupStatistics? _parseStatsIsolate(
          (List<int>, Map<String, String>) page) =>
      StatisticsPageParser().parse(_html(page));

  static List<Group> _parseGroupsIsolate(
          (List<int>, Map<String, String>, String) page) =>
      ExpressScheduleParser()
          .parseGroupList(_html((page.$1, page.$2)), page.$3);

  static List<Group> _parseTeachersIsolate(
          (List<int>, Map<String, String>, String) page) =>
      ExpressScheduleParser()
          .parseTeacherList(_html((page.$1, page.$2)), page.$3);

  void dispose() => _client.dispose();
}
