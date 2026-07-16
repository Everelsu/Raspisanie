// Достаёт запись одной версии из CHANGELOG.md, чтобы релизный workflow мог
// использовать её как описание релиза на GitHub и как `notes` в latest.json.
//
// Использование:
//   dart run tool/extract_changelog.dart <версия> [файл-результата]
//
// По умолчанию пишет в RELEASE_BODY.md в текущей директории.

import "dart:io";

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
        "Usage: dart run tool/extract_changelog.dart <version> [output-file]");
    exit(1);
  }
  final version = args[0];
  final output = args.length > 1 ? args[1] : "RELEASE_BODY.md";

  final lines = File("CHANGELOG.md").readAsLinesSync();
  // Заголовок записи: «## 2.0.5 — 2026-07-16» (после версии — разделитель или конец строки).
  final heading = RegExp("^## ${RegExp.escape(version)}(\\s|\$)");
  final start = lines.indexWhere(heading.hasMatch);
  if (start == -1) {
    stderr.writeln("No changelog entry for version $version in CHANGELOG.md");
    exit(1);
  }
  var end = lines.length;
  for (var i = start + 1; i < lines.length; i++) {
    if (lines[i].startsWith("## ")) {
      end = i;
      break;
    }
  }
  final body = lines.sublist(start + 1, end).join("\n").trim();
  if (body.isEmpty) {
    stderr.writeln("Changelog entry for $version is empty");
    exit(1);
  }
  File(output).writeAsStringSync("$body\n");
  stdout.writeln(
      "Wrote ${body.length} chars of changelog for $version -> $output");
}
