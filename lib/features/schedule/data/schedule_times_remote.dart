import "dart:convert";

import "package:crypto/crypto.dart";

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
    final root = (decoded["colleges"] is Map<String, dynamic>)
        ? decoded["colleges"]
        : decoded;
    if (root is! Map<String, dynamic>) {
      throw const FormatException("Поле colleges должно быть объектом");
    }
    final byCollege = LessonTimes.parseByCollege(root);

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

  String _fingerprint(List<int> bytes) => sha1.convert(bytes).toString();
}
