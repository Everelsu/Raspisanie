import "package:html/dom.dart";
import "package:html/parser.dart" as html_parser;

import "../../features/schedule/domain/models.dart";

class ExpressScheduleParser {
  static final _groupHref = RegExp(
    r"^[bch]g(\d+)\.htm",
    caseSensitive: false,
  );
  static final _dateLineRegex = RegExp(
    r"(\d{2}\.\d{2}\.\d{4})\s*([А-Яа-яЁё]+)(?:\s*-\s*(\d{1,2}))?",
  );

  List<Group> parseGroupList(String html, String baseUrl) {
    final doc = html_parser.parse(html);
    final links = doc.querySelectorAll("a[href]");
    final groups = <Group>[];

    for (final a in links) {
      final href = (a.attributes["href"] ?? "").trim().split("?").first;
      final m = _groupHref.firstMatch(href);
      if (m == null) continue;
      final id = int.tryParse(m.group(1)!);
      if (id == null) continue;
      final name = a.text.trim();
      if (name.isEmpty) continue;

      final normalized = baseUrl.endsWith("/") ? baseUrl : "$baseUrl/";
      groups.add(Group(
        id: id,
        name: name,
        fileName: href,
        pageUrl: "$normalized$href",
      ));
    }

    final seen = <int>{};
    groups.retainWhere((g) => seen.add(g.id));
    groups.sort((a, b) => a.name.compareTo(b.name));
    return groups;
  }

  List<DaySchedule> parseSchedulePage(String html) {
    final doc = html_parser.parse(html);
    final table = doc.querySelector("table.inf") ??
        doc.querySelectorAll("table").where((t) {
          final txt = t.text.toLowerCase();
          return txt.contains("день") && txt.contains("пара");
        }).firstOrNull ??
        doc.querySelector("table");
    if (table == null) return const [];

    final rows = table.querySelectorAll("tr");
    final schedules = <DaySchedule>[];

    String? currentDay;
    String? currentDate;
    int currentWeek = 1;
    var dayItems = <ScheduleItem>[];

    for (final row in rows) {
      final cells = row.querySelectorAll("td");
      if (cells.isEmpty) continue;

      final isHeader = cells.any((c) =>
          c.classes.contains("hd") &&
          (c.text.contains("День") || c.text.contains("Пара")));
      if (isHeader) continue;

      if (cells.any((c) => c.classes.contains("hd0"))) continue;

      Element? dayCell;
      for (final c in cells) {
        if (c.attributes.containsKey("rowspan") ||
            _dateLineRegex.hasMatch(c.text.replaceAll("\n", " "))) {
          dayCell = c;
          break;
        }
      }

      var justStartedNew = false;
      if (dayCell != null) {
        final dateText = dayCell.innerHtml
            .replaceAll(RegExp(r"<br\s*/?>", caseSensitive: false), "\n")
            .replaceAll(RegExp(r"<[^>]+>"), "");
        final m = _dateLineRegex.firstMatch(dateText);
        if (m != null) {
          if (currentDay != null) {
            schedules.add(DaySchedule(
              day: currentDay,
              date: currentDate ?? "",
              weekNumber: currentWeek,
              items: List.unmodifiable(dayItems),
            ));
          }
          currentDate = m.group(1)!;
          currentDay = m.group(2)!.trim();
          currentWeek = int.tryParse(m.group(3) ?? "") ?? currentWeek;
          dayItems = [];
          justStartedNew = true;
        }
      }

      if (currentDay == null) continue;
      if (dayCell != null && !justStartedNew) continue;

      int? lessonNumber;
      int lessonCellIdx = -1;

      for (var i = 0; i < cells.length; i++) {
        final c = cells[i];
        if (c.attributes.containsKey("rowspan")) continue;
        if (c.classes.contains("ur") ||
            c.classes.contains("nul") ||
            c.classes.contains("hd0")) {
          continue;
        }
        final num = _extractLessonNumber(c.text);
        if (num != null) {
          lessonNumber = num;
          lessonCellIdx = i;
          break;
        }
      }

      if (lessonNumber == null || lessonCellIdx < 0) continue;

      final afterLesson = cells.sublist(lessonCellIdx + 1);
      final hasMultiCols = afterLesson.length > 1;

      for (var ci = 0; ci < afterLesson.length; ci++) {
        final cell = afterLesson[ci];
        if (!_looksLikeLessonCell(cell)) continue;
        final info = _parseSubjectCell(cell);
        if (info.subject == null || info.subject!.isEmpty) continue;

        final subgroup = hasMultiCols
            ? ci + 1
            : null;

        dayItems.add(ScheduleItem(
          day: currentDay,
          date: currentDate ?? "",
          weekNumber: currentWeek,
          lessonNumber: lessonNumber,
          subject: info.subject,
          classroom: info.classroom,
          teacher: info.teacher,
          subgroup: subgroup,
          subjectHref: info.subjectHref,
          classroomHref: info.classroomHref,
          teacherHref: info.teacherHref,
        ));
      }
    }

    if (currentDay != null) {
      schedules.add(DaySchedule(
        day: currentDay,
        date: currentDate ?? "",
        weekNumber: currentWeek,
        items: List.unmodifiable(dayItems),
      ));
    }

    return schedules;
  }

  static final _teacherHref = RegExp(
    r"^cp(\d+)\.htm",
    caseSensitive: false,
  );

  List<Group> parseTeacherList(String html, String baseUrl) {
    final doc = html_parser.parse(html);
    final links = doc.querySelectorAll("a[href]");
    final teachers = <Group>[];

    for (final a in links) {
      final href = (a.attributes["href"] ?? "").trim().split("?").first;
      final m = _teacherHref.firstMatch(href);
      if (m == null) continue;
      final id = int.tryParse(m.group(1)!);
      if (id == null) continue;
      final name = a.text.trim();
      if (name.isEmpty) continue;

      final normalized = baseUrl.endsWith("/") ? baseUrl : "$baseUrl/";
      teachers.add(Group(
        id: id,
        name: name,
        fileName: href,
        pageUrl: "$normalized$href",
      ));
    }

    final seen = <int>{};
    teachers.retainWhere((g) => seen.add(g.id));
    teachers.sort((a, b) => a.name.compareTo(b.name));
    return teachers;
  }

  ({
    String? subject,
    String? classroom,
    String? teacher,
    String? subjectHref,
    String? classroomHref,
    String? teacherHref,
  }) _parseSubjectCell(Element cell) {
    final subjectLink = cell.querySelector("a.z1") ??
        cell.querySelectorAll("a").where((a) {
          final href = a.attributes["href"] ?? "";
          return href.startsWith("j") &&
              !href.startsWith("cp") &&
              !href.startsWith("ca");
        }).firstOrNull;

    final classroomLink = cell.querySelector("a.z2") ??
        cell.querySelectorAll("a").where((a) {
          final href = a.attributes["href"] ?? "";
          return href.startsWith("ca");
        }).firstOrNull;

    final teacherLink = cell.querySelector("a.z3") ??
        cell.querySelectorAll("a").where((a) {
          final href = a.attributes["href"] ?? "";
          return href.startsWith("cp");
        }).firstOrNull;

    final rawText = cell.text
        .replaceAll("\u00A0", " ")
        .replaceAll(RegExp(r"\s+"), " ")
        .trim();

    final subject = _extractSubjectText(
      subjectLink: subjectLink,
      classroomLink: classroomLink,
      teacherLink: teacherLink,
      rawText: rawText,
      allLinks: cell.querySelectorAll("a"),
    );
    var classroom = classroomLink?.text.trim();
    if ((classroom == null || classroom.isEmpty) && classroomLink != null) {
      final href = classroomLink.attributes["href"] ?? "";
      final m = RegExp(r"ca([^.]+)\.htm").firstMatch(href);
      if (m != null) classroom = m.group(1);
    }
    final teacher = teacherLink?.text.trim();
    final subjectHref = subjectLink?.attributes["href"]?.trim().split("?").first;

    final classroomHref =
        classroomLink?.attributes["href"]?.trim().split("?").first;
    final teacherHref =
        teacherLink?.attributes["href"]?.trim().split("?").first;

    return (
      subject: subject,
      classroom: classroom,
      teacher: teacher,
      subjectHref: subjectHref,
      classroomHref: classroomHref,
      teacherHref: teacherHref,
    );
  }

  int? _extractLessonNumber(String text) {
    final normalized = text
        .replaceAll("\u00A0", " ")
        .replaceAll(RegExp(r"\s+"), " ")
        .trim();
    if (normalized.isEmpty) return null;
    final exact = int.tryParse(normalized);
    if (exact != null && exact >= 1 && exact <= 12) return exact;
    final m = RegExp(r"\b(1[0-2]|[1-9])\b").firstMatch(normalized);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  bool _looksLikeLessonCell(Element cell) {
    if (cell.classes.contains("nul") ||
        cell.classes.contains("hd") ||
        cell.classes.contains("hd0")) {
      return false;
    }
    if (cell.classes.contains("ur")) return true;
    final links = cell.querySelectorAll("a[href]");
    if (links.any((a) {
      final href = (a.attributes["href"] ?? "").toLowerCase();
      return href.startsWith("j") ||
          href.startsWith("cp") ||
          href.startsWith("ca");
    })) {
      return true;
    }
    final text = cell.text.replaceAll(RegExp(r"\s+"), " ").trim();
    if (text.isEmpty) return false;
    return _extractLessonNumber(text) == null;
  }

  String? _extractSubjectText({
    required Element? subjectLink,
    required Element? classroomLink,
    required Element? teacherLink,
    required String rawText,
    required List<Element> allLinks,
  }) {
    final linkedSubject = subjectLink?.text.trim();
    if (linkedSubject != null && linkedSubject.isNotEmpty) {
      return linkedSubject;
    }

    var candidate = rawText;
    for (final extra in [
      classroomLink?.text.trim(),
      teacherLink?.text.trim(),
    ]) {
      if (extra == null || extra.isEmpty) continue;
      candidate = candidate.replaceAll(extra, " ");
    }
    candidate = candidate
        .replaceAll(RegExp(r"\s*[·|/]\s*"), " ")
        .replaceAll(RegExp(r"\s+-\s+"), " ")
        .replaceAll(RegExp(r"\s+"), " ")
        .trim();
    if (candidate.isNotEmpty && _extractLessonNumber(candidate) == null) {
      return candidate;
    }

    for (final a in allLinks) {
      final href = (a.attributes["href"] ?? "").toLowerCase();
      if (href.startsWith("cp") || href.startsWith("ca")) continue;
      final text = a.text.trim();
      if (text.isNotEmpty) return text;
    }

    return null;
  }

}
