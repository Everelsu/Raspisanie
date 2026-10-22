// Проверка JSON для Firebase Remote Config перед публикацией — тем же
// разбором, что в приложении. Показывает, что приложение поймёт, и что
// пропустит (битая дата, нет title, неизвестный пресет).
//
//   dart run tool/remote_config/check.dart                       # special_days.json
//   dart run tool/remote_config/check.dart путь/к/special_days.json
//   dart run tool/remote_config/check.dart tool/remote_config/lesson_times.json

import "dart:convert";
import "dart:io";

import "package:raspiflutter/features/schedule/data/lesson_times.dart";
import "package:raspiflutter/features/schedule/data/special_days.dart";

void main(List<String> args) {
  final path = args.isEmpty ? "tool/remote_config/special_days.json" : args[0];
  final raw = File(path).readAsStringSync();
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (e) {
    _fail("Не JSON: $e");
  }
  if (decoded is! Map<String, dynamic>) _fail("Корень должен быть объектом {}");

  if (path.contains("lesson_times")) {
    _checkLessonTimes(decoded);
  } else {
    _checkSpecialDays(raw, decoded);
  }
}

void _checkLessonTimes(Map<String, dynamic> decoded) {
  final root = decoded["colleges"] is Map<String, dynamic>
      ? decoded["colleges"] as Map<String, dynamic>
      : decoded;
  final byCollege = LessonTimes.parseByCollege(root);
  if (byCollege.isEmpty) _fail("Не найдено ни одного техникума с временем пар");
  for (final e in byCollege.entries) {
    stdout.writeln("${e.key}:");
    _printTimes(e.value, e.key);
  }
  stdout.writeln("\nOK: ${byCollege.length} техникума(ов)");
}

void _checkSpecialDays(String raw, Map<String, dynamic> decoded) {
  final days = SpecialDays.parse(raw);
  final keys = decoded.keys.where((k) => k != SpecialDays.presetsKey).toList();
  final presets = decoded[SpecialDays.presetsKey];
  final presetNames =
      presets is Map<String, dynamic> ? presets.keys.toSet() : <String>{};

  for (final d in days) {
    final range = d.from == d.to
        ? _date(d.from)
        : "${_date(d.from)} … ${_date(d.to)}";
    stdout.writeln("$range  [${d.kind}] ${d.title}");
    if (d.note != null) stdout.writeln("  подпись: ${d.note}");
    stdout.writeln("  техникумы: ${d.colleges?.join(", ") ?? "все"}");
    if (d.noClasses) stdout.writeln("  пар нет");
    for (final e in d.times.entries) {
      stdout.writeln("  время${e.key == null ? "" : " (${e.key})"}:");
      _printTimes(e.value, e.key ?? d.colleges?.first ?? "chtotib");
    }
    stdout.writeln("");
  }

  final problems = <String>[];
  for (final k in keys) {
    final v = decoded[k];
    final parsedRange = days.any((d) {
      final parts = k.split("..");
      return parts.first.trim() == _date(d.from);
    });
    if (!parsedRange) {
      problems.add("«$k» пропущена: дата не YYYY-MM-DD(..YYYY-MM-DD) "
          "или нет title");
      continue;
    }
    final times = v is Map ? v["times"] : null;
    if (times is String && !presetNames.contains(times)) {
      problems.add("«$k»: пресета «$times» нет в presets");
    }
  }

  if (problems.isNotEmpty) {
    stderr.writeln("Проблемы:");
    for (final p in problems) {
      stderr.writeln("  - $p");
    }
    exit(1);
  }
  stdout.writeln("OK: ${days.length} особых дня(ей), пресетов: "
      "${presetNames.length}");
}

void _printTimes(Map<int, LessonTime> times, String college) {
  final numbers = times.keys.toList()..sort();
  for (var i = 0; i < numbers.length; i++) {
    final t = times[numbers[i]]!;
    stdout.writeln("    ${t.number}. ${t.startTime}–${t.endTime}");
    if (i + 1 < numbers.length) {
      final next = times[numbers[i + 1]]!;
      final gap = LessonTimes.parseTimeToMinutes(next.startTime) -
          LessonTimes.parseTimeToMinutes(t.endTime);
      if (gap >= LessonTimes.lunchGapMinutes) {
        stdout.writeln("       обед ${t.endTime}–${next.startTime}");
      } else if (gap < 0) {
        stdout.writeln("       ⚠ пара ${next.number} начинается раньше, "
            "чем кончается ${t.number}");
      }
    }
  }
}

String _date(DateTime d) =>
    "${d.year}-${d.month.toString().padLeft(2, "0")}-"
    "${d.day.toString().padLeft(2, "0")}";

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
