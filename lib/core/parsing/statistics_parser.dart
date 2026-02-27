import "package:html/parser.dart" as html_parser;

import "../../features/schedule/domain/models.dart";

class StatisticsPageParser {
  static final _numberRegex = RegExp(r"(\d+)");

  GroupStatistics? parse(String html) {
    final doc = html_parser.parse(html);

    final h1 = doc.querySelector("h1");
    final groupName = (h1?.text ?? "")
        .replaceAll("Группа:", "")
        .replaceAll("Преподаватель:", "")
        .replaceAll(RegExp(r"группа\s*:?", caseSensitive: false), "")
        .replaceAll(RegExp(r"преподаватель\s*:?", caseSensitive: false), "")
        .trim();

    final tables = doc.querySelectorAll("table");
    final statsTable = doc.querySelector("table.inf") ??
        tables.where((t) {
          final text = t.text.toLowerCase();
          return text.contains("всего") &&
              (text.contains("план") || text.contains("факт")) &&
              text.contains("остаток");
        }).firstOrNull;

    if (statsTable == null) return null;

    final rows = statsTable.querySelectorAll("tr");

    var headerFound = false;
    var numIdx = -1,
        teacherIdx = -1,
        groupIdx = -1,
        discIdx = -1,
        typeIdx = -1,
        totalIdx = -1,
        planIdx = -1,
        factIdx = -1,
        remIdx = -1,
        plan2Idx = -1,
        fact2Idx = -1,
        dateIdx = -1,
        pctIdx = -1;

    final disciplines = <DisciplineStatistics>[];
    var totalSum = 0, planSum = 0, factSum = 0, remSum = 0;

    for (final row in rows) {
      final cells = row.querySelectorAll("td, th");
      if (cells.isEmpty) continue;

      if (!headerFound) {
        final headerText = row.text.toLowerCase();
        if (headerText.contains("№") &&
            (headerText.contains("преподаватель") ||
                headerText.contains("дисциплина"))) {
          headerFound = true;
          for (var i = 0; i < cells.length; i++) {
            final t = cells[i].text.toLowerCase();
            if (t.contains("№") || t.contains("п.п")) numIdx = i;
            if (t.contains("преподаватель")) teacherIdx = i;
            if (t.contains("группа") && !t.contains("подгруппа")) groupIdx = i;
            if (t.contains("дисциплина")) discIdx = i;
            if (t.contains("тип") && t.contains("занят")) typeIdx = i;
            if (t.contains("всего") &&
                (t.contains("час") || t.contains("ч."))) {
              totalIdx = i;
            }
            if (t.contains("план") &&
                t.contains("час") &&
                !t.contains("2 нед")) {
              planIdx = i;
            }
            if (t.contains("факт") &&
                t.contains("час") &&
                !t.contains("2 нед")) {
              factIdx = i;
            }
            if (t.contains("остаток") &&
                (t.contains("час") || t.contains("ч."))) {
              remIdx = i;
            }
            if (t.contains("план") && t.contains("2 нед")) plan2Idx = i;
            if (t.contains("факт") && t.contains("2 нед")) fact2Idx = i;
            if (t.contains("окончание")) dateIdx = i;
            if (t.contains("процент") || t.contains("выполн")) pctIdx = i;
          }
          continue;
        }
      }

      if (headerFound && cells.length > 3) {
        final first = cells.first.text.toLowerCase().trim();
        if (first.contains("№") && first.contains("п.п") ||
            first.contains("преподаватель") ||
            first.isEmpty ||
            first.contains("-----")) {
          continue;
        }

        String cellAt(int idx) =>
            idx >= 0 && idx < cells.length ? cells[idx].text.trim() : "";

        int? intAt(int idx) {
          if (idx < 0 || idx >= cells.length) return null;
          final m = _numberRegex.firstMatch(cells[idx].text);
          return m != null ? int.tryParse(m.group(1)!) : null;
        }

        String? optAt(int idx) {
          if (idx < 0 || idx >= cells.length) return null;
          final t = cells[idx].text.trim();
          return t.isNotEmpty ? t : null;
        }

        final discipline = discIdx >= 0 && discIdx < cells.length
            ? (cells[discIdx].querySelector("a")?.text.trim() ??
                cells[discIdx].text.trim())
            : "";

        String? pctText;
        if (pctIdx >= 0 && pctIdx < cells.length) {
          final t = cells[pctIdx].text.trim();
          if (t.isNotEmpty) {
            pctText = t;
          } else {
            final img = cells[pctIdx].querySelector("img");
            pctText = img?.attributes["alt"];
          }
        }

        if (discipline.isNotEmpty || cellAt(numIdx).isNotEmpty) {
          final total = intAt(totalIdx);
          final plan = intAt(planIdx);
          final fact = intAt(factIdx);
          final rem = intAt(remIdx);

          disciplines.add(DisciplineStatistics(
            number: cellAt(numIdx),
            teacher: cellAt(teacherIdx),
            group: cellAt(groupIdx),
            discipline: discipline,
            lessonType: cellAt(typeIdx),
            totalHours: total,
            plannedHours: plan,
            factHours: fact,
            remainingHours: rem,
            plannedIn2Weeks: optAt(plan2Idx),
            factIn2Weeks: optAt(fact2Idx),
            completionDate: optAt(dateIdx),
            completionPercent: pctText,
          ));

          if (total != null) totalSum += total;
          if (plan != null) planSum += plan;
          if (fact != null) factSum += fact;
          if (rem != null) remSum += rem;
        }
      }
    }

    return GroupStatistics(
      groupName: groupName,
      disciplines: disciplines,
      totalHours: totalSum > 0 ? totalSum : null,
      completedHours: factSum > 0 ? factSum : null,
      remainingHours: remSum > 0 ? remSum : null,
      plannedHours: planSum > 0 ? planSum : null,
    );
  }
}
