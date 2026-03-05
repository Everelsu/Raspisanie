import "package:flutter/material.dart";

import "../data/lesson_times.dart";
import "../domain/models.dart";
import "schedule_controller.dart";

/// Тип подрасписания: кабинет или преподаватель/группа (предмет).
enum SubScheduleKind {
  classroom,
  teacherOrGroup,
}

Future<void> showSubScheduleSheet({
  required BuildContext context,
  required String file,
  required ScheduleController controller,
  required String title,
  SubScheduleKind kind = SubScheduleKind.teacherOrGroup,
}) async {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardTheme.color,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _SubScheduleContent(
      file: file,
      controller: controller,
      title: title,
      kind: kind,
    ),
  );
}

class _SubScheduleContent extends StatefulWidget {
  const _SubScheduleContent({
    required this.file,
    required this.controller,
    required this.title,
    required this.kind,
  });
  final String file;
  final ScheduleController controller;
  final String title;
  final SubScheduleKind kind;

  @override
  State<_SubScheduleContent> createState() => _SubScheduleContentState();
}

class _SubScheduleContentState extends State<_SubScheduleContent> {
  List<DaySchedule>? _schedule;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await widget.controller.repository.fetchSubSchedule(
        file: widget.file,
        college: widget.controller.college,
      );
      if (mounted) setState(() { _schedule = result; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withAlpha(40),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.title,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_error!,
                                style: TextStyle(
                                    color: theme.colorScheme.error)),
                          ),
                        )
                      : _schedule == null || _schedule!.isEmpty
                          ? Center(
                              child: Text("Нет данных",
                                  style: theme.textTheme.bodyLarge),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.all(16),
                              itemCount: _schedule!.length,
                              itemBuilder: (_, i) => _MiniDayCard(
                                day: _schedule![i],
                                college: widget.controller.college,
                                isTeacherMode: widget.controller.prefs.isTeacherMode,
                                sheetTitle: widget.title,
                                kind: widget.kind,
                              ),
                            ),
            ),
          ],
        );
      },
    );
  }
}

class _MiniDayCard extends StatelessWidget {
  const _MiniDayCard({
    required this.day,
    required this.college,
    required this.isTeacherMode,
    required this.kind,
    this.sheetTitle = "",
  });
  final DaySchedule day;
  final String college;
  final bool isTeacherMode;
  final SubScheduleKind kind;
  /// Заголовок панели (кабинет, преподаватель или группа) — не дублируем в строке.
  final String sheetTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "${day.day} — ${day.date}",
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          ...day.items.map((item) {
            final time = LessonTimes.formatTime(item.lessonNumber,
                college: college);
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      "${item.lessonNumber}.",
                      style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      kind == SubScheduleKind.classroom
                          ? _buildClassroomItemLine(item, time)
                          : _buildTeacherOrGroupItemLine(item, time),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            );
          }),
          const Divider(),
        ],
      ),
    );
  }

  /// Строка пары для подрасписания по кабинету: предмет • преподаватель/группа • время (кабинет не дублируем).
  String _buildClassroomItemLine(ScheduleItem item, String time) {
    final subject = (item.subject ?? "").trim();
    final teacherOrGroup = (item.teacher ?? "").trim();
    final parts = <String>[];
    if (subject.isNotEmpty) parts.add(subject);
    if (teacherOrGroup.isNotEmpty) parts.add(teacherOrGroup);
    if (time.isNotEmpty) parts.add(time);
    if (parts.isEmpty) return "Нет данных";
    return parts.join(" \u2022 ");
  }

  /// Строка пары для подрасписания по преподавателю/группе: предмет • кабинет • время (препода/группу не дублируем).
  String _buildTeacherOrGroupItemLine(ScheduleItem item, String time) {
    final subject = (item.subject ?? "").trim();
    final classroom = (item.classroom ?? "").trim();
    final teacherOrGroup = (item.teacher ?? "").trim();

    final parts = <String>[];
    if (isTeacherMode) {
      if (teacherOrGroup.isNotEmpty && !_titleMatches(teacherOrGroup)) parts.add(teacherOrGroup);
      if (classroom.isNotEmpty) parts.add("Ауд. $classroom");
      if (subject.isNotEmpty && subject != teacherOrGroup && !_titleMatches(subject)) parts.add(subject);
    } else {
      if (subject.isNotEmpty && !_titleMatches(subject)) parts.add(subject);
      if (classroom.isNotEmpty) parts.add("Ауд. $classroom");
      if (teacherOrGroup.isNotEmpty && !_titleMatches(teacherOrGroup)) parts.add(teacherOrGroup);
    }
    if (time.isNotEmpty) parts.add(time);
    if (parts.isEmpty) return "Нет данных";
    return parts.join(" \u2022 ");
  }

  bool _titleMatches(String value) {
    final t = sheetTitle.trim();
    return t.isNotEmpty && (t == value || "Ауд. $value" == t || t == "Ауд. $value");
  }
}
