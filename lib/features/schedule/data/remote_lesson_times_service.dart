import "dart:convert";

import "../../../core/network/http_client.dart";
import "lesson_times.dart";

class RemoteLessonTimesData {
  const RemoteLessonTimesData({
    required this.byCollege,
    required this.fingerprint,
  });

  final Map<String, Map<int, LessonTime>> byCollege;
  final String fingerprint;
}

class RemoteLessonTimesService {
  RemoteLessonTimesService({HttpClientService? client})
      : _client = client ?? HttpClientService();

  final HttpClientService _client;

  Future<RemoteLessonTimesData> fetch(String url) async {
    final response = await _client.getBytes(url);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError("HTTP ${response.statusCode}");
    }
    final raw = utf8.decode(response.bodyBytes);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException("JSON должен быть объектом");
    }

    final byCollege = <String, Map<int, LessonTime>>{};

    // Supported formats:
    // 1) {"colleges":{"chtotib":{"1":{"start":"08:15","end":"09:15"}}}}
    // 2) {"chtotib":{"1":{"start":"08:15","end":"09:15"}},"zabgc":{...}}
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
    return RemoteLessonTimesData(
      byCollege: byCollege,
      fingerprint: _fingerprint(response.bodyBytes),
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

  // Compact deterministic fingerprint for change detection.
  String _fingerprint(List<int> bytes) {
    var hash = 0xcbf29ce484222325;
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16);
  }
}
