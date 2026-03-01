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

class ExpressScheduleRepository {
  ExpressScheduleRepository({
    HttpClientService? client,
    EncodingDecoder? decoder,
    ExpressScheduleParser? parser,
    StatisticsPageParser? statsParser,
    this.scheduleCache,
    this.groupsCache,
  })  : _client = client ?? HttpClientService(),
        _decoder = decoder ?? EncodingDecoder(),
        _parser = parser ?? ExpressScheduleParser(),
        _statsParser = statsParser ?? StatisticsPageParser();

  final HttpClientService _client;
  final EncodingDecoder _decoder;
  final ExpressScheduleParser _parser;
  final StatisticsPageParser _statsParser;
  final ScheduleCache? scheduleCache;
  final GroupsCache? groupsCache;
  final Map<String, Future<List<DaySchedule>>> _inflightSchedule = {};
  final Set<String> _backgroundRefreshing = {};
  final Map<String, DateTime> _lastBackgroundRefresh = {};
  Map<String, String> _customBaseUrls = const {};
  static const _backgroundRefreshThrottle = Duration(minutes: 2);

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
        final decoded = _decoder.decode(
            bytes: response.bodyBytes, headers: response.headers);
        final groups = _parser.parseGroupList(decoded.html, base);
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
      throw StateError(
          "HTTP ${response.statusCode} при загрузке расписания.");
    }

    final decoded =
        _decoder.decode(bytes: response.bodyBytes, headers: response.headers);
    final days = await compute(_parseInIsolate, decoded.html);
    if (days.isEmpty) {
      final cached = scheduleCache?.load(groupFile, college);
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
      scheduleCache?.save(days, groupFile, college);
      scheduleCache?.saveToHistory(days, groupFile, college);
      final snapshotJson = jsonEncode(days.map((e) => e.toJson()).toList());
      await ScheduleDatabase.instance.saveScheduleSnapshot(
        groupFile, college, snapshotJson,
        parsedDays: days,
      );
    }
    return days;
  }

  Future<GroupStatistics?> fetchStatistics({
    required String groupFile,
    required String college,
  }) async {
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
      final decoded = _decoder.decode(
          bytes: response.bodyBytes, headers: response.headers);
      return _statsParser.parse(decoded.html);
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
      final decoded = _decoder.decode(
          bytes: response.bodyBytes, headers: response.headers);
      final teachers = _parser.parseTeacherList(decoded.html, base);
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
    final decoded =
        _decoder.decode(bytes: response.bodyBytes, headers: response.headers);
    final days = _parser.parseSchedulePage(decoded.html);
    if (days.isEmpty) {
      throw StateError("Не удалось распознать подрасписание.");
    }
    return days;
  }

  Future<void> _refreshInBackground(
      String groupFile, String college) async {
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
      await _fetchFromNetwork(groupFile, college);
    } catch (_) {}
    finally {
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

  static List<DaySchedule> _parseInIsolate(String html) {
    return ExpressScheduleParser().parseSchedulePage(html);
  }

  void dispose() => _client.dispose();
}
