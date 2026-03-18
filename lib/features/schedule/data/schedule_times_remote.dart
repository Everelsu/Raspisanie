import "dart:convert";

import "../../../core/update/github_http_client.dart";
import "lesson_times.dart";

/// Подсказки из JSON (`sources.updateHints`).
class ScheduleTimesHints {
  const ScheduleTimesHints({
    this.minIntervalHours = 12,
    this.useEtagIfPossible = true,
  });

  final int minIntervalHours;
  final bool useEtagIfPossible;

  static ScheduleTimesHints fromDecoded(Map<String, dynamic>? decoded) {
    final sources = decoded?["sources"];
    if (sources is! Map<String, dynamic>) {
      return const ScheduleTimesHints();
    }
    final hints = sources["updateHints"];
    if (hints is! Map<String, dynamic>) {
      return const ScheduleTimesHints();
    }
    var hours = 12;
    final h = hints["minIntervalHours"];
    if (h is int) {
      hours = h.clamp(1, 168);
    } else if (h is num) {
      hours = h.toInt().clamp(1, 168);
    }
    final useEtag = hints["useETagIfPossible"] != false;
    return ScheduleTimesHints(
      minIntervalHours: hours,
      useEtagIfPossible: useEtag,
    );
  }
}

class RemoteLessonTimesData {
  const RemoteLessonTimesData({
    required this.byCollege,
    required this.fingerprint,
  });

  final Map<String, Map<int, LessonTime>> byCollege;
  final String fingerprint;
}

/// Результат запроса: 304, тело с данными или ошибка парсинга.
sealed class ScheduleTimesFetchOutcome {}

class ScheduleTimesFetchNotModified extends ScheduleTimesFetchOutcome {
  ScheduleTimesFetchNotModified({required this.hints});
  final ScheduleTimesHints hints;
}

class ScheduleTimesFetchSuccess extends ScheduleTimesFetchOutcome {
  ScheduleTimesFetchSuccess({
    required this.data,
    required this.etag,
    required this.hints,
  });
  final RemoteLessonTimesData data;
  final String? etag;
  final ScheduleTimesHints hints;
}

/// Загрузка и разбор `schedule_times.json` / legacy `lesson_times.json` с GitHub.
class ScheduleTimesRemoteService {
  Future<ScheduleTimesFetchOutcome> fetch(
    String url, {
    String? ifNoneMatch,
    bool sendConditional = true,
  }) async {
    final headers = <String, String>{
      "Accept": "application/json, text/plain, */*",
    };
    if (sendConditional &&
        ifNoneMatch != null &&
        ifNoneMatch.trim().isNotEmpty) {
      headers["If-None-Match"] = ifNoneMatch.trim();
    }

    final response = await GitHubHttpClient.get(url, headers: headers);

    if (response.statusCode == 304) {
      return ScheduleTimesFetchNotModified(hints: const ScheduleTimesHints());
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError("HTTP ${response.statusCode}");
    }

    final raw = utf8.decode(response.bodyBytes);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException("JSON должен быть объектом");
    }

    final hints = ScheduleTimesHints.fromDecoded(decoded);
    final byCollege = <String, Map<int, LessonTime>>{};

    final root =
        (decoded["colleges"] is Map<String, dynamic>) ? decoded["colleges"] : decoded;
    if (root is! Map<String, dynamic>) {
      throw const FormatException("Поле colleges должно быть объектом");
    }

    for (final collegeEntry in root.entries) {
      final collegeKey = collegeEntry.key.trim().toLowerCase();
      final value = collegeEntry.value;
      if (value is! Map<String, dynamic>) continue;
      final parsed = <int, LessonTime>{};

      for (final lessonEntry in value.entries) {
        final lessonNumber = int.tryParse(lessonEntry.key);
        if (lessonNumber == null) continue;
        final lessonRaw = lessonEntry.value;
        if (lessonRaw is! Map<String, dynamic>) continue;
        final start = (lessonRaw["start"] ?? lessonRaw["from"]) as String?;
        final end = (lessonRaw["end"] ?? lessonRaw["to"]) as String?;
        if (!_isValidTime(start) || !_isValidTime(end)) continue;
        parsed[lessonNumber] = LessonTime(lessonNumber, start!, end!);
      }

      if (parsed.isNotEmpty) {
        byCollege[collegeKey] = parsed;
      }
    }

    if (byCollege.isEmpty) {
      throw const FormatException("Не найдено данных по времени пар");
    }

    final etag = response.headers["etag"]?.trim();
    return ScheduleTimesFetchSuccess(
      data: RemoteLessonTimesData(
        byCollege: byCollege,
        fingerprint: _fingerprint(response.bodyBytes),
      ),
      etag: (etag != null && etag.isNotEmpty) ? etag : null,
      hints: hints,
    );
  }

  bool _isValidTime(String? value) {
    if (value == null) return false;
    final m = RegExp(r"^\d{1,2}:\d{2}$").firstMatch(value.trim());
    if (m == null) return false;
    final parts = value.split(":");
    final h = int.tryParse(parts[0]);
    final min = int.tryParse(parts[1]);
    if (h == null || min == null) return false;
    return h >= 0 && h <= 23 && min >= 0 && min <= 59;
  }

  String _fingerprint(List<int> bytes) {
    var hash = 0xcbf29ce484222325;
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16);
  }
}
