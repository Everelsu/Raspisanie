import "package:flutter/material.dart";

import "../../../core/widgets/app_action_button.dart";

import "../data/lesson_times.dart";
import "../domain/models.dart";
import "day_share_sheet.dart";
import "schedule_controller.dart";

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
    backgroundColor: Colors.transparent,
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
  bool _isOfflineSnapshot = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cached = widget.controller.repository.subScheduleCache?.load(
      widget.file,
      widget.controller.college,
    );

    if (cached != null && cached.isNotEmpty && mounted) {
      setState(() {
        _schedule = cached;
        _loading = false;
        _error = null;
        _isOfflineSnapshot = false;
      });
    } else if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _isOfflineSnapshot = false;
      });
    }

    try {
      final result = await widget.controller.repository.fetchSubSchedule(
        file: widget.file,
        college: widget.controller.college,
      );
      if (!mounted) return;
      setState(() {
        _schedule = result;
        _loading = false;
        _error = null;
        _isOfflineSnapshot = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (cached != null && cached.isNotEmpty) {
        setState(() {
          _schedule = cached;
          _loading = false;
          _error = null;
          _isOfflineSnapshot = true;
        });
        return;
      }
      setState(() {
        _error = _toHumanError(e);
        _loading = false;
        _isOfflineSnapshot = false;
      });
    }
  }

  static String _toHumanError(Object e) {
    final s = e.toString();
    if (s.contains("SocketException") ||
        s.contains("NetworkException") ||
        s.contains("Connection refused") ||
        s.contains("Failed host lookup")) {
      return "Нет подключения к интернету";
    }
    if (s.contains("TimeoutException") || s.contains("timed out")) {
      return "Сервер не отвечает. Попробуйте позже";
    }
    if (s.contains("HTTP 5") || s.contains("500") || s.contains("503")) {
      return "Ошибка сервера. Попробуйте позже";
    }
    if (s.contains("HTTP 4") || s.contains("404")) {
      return "Данные не найдены";
    }
    return "Не удалось загрузить данные";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final cardColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final isDark = theme.brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.68,
      minChildSize: 0.34,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollController) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: const Alignment(-0.7, -1.0),
              end: const Alignment(0.9, 1.0),
              colors: [
                Color.alphaBlend(
                    primary.withAlpha(isDark ? 30 : 18), cardColor),
                Color.alphaBlend(primary.withAlpha(isDark ? 12 : 6), cardColor),
                cardColor,
              ],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withAlpha(36),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: _HeaderCard(
                    title: widget.title,
                    kind: widget.kind,
                    isTeacherMode: widget.controller.prefs.isTeacherMode,
                    isOfflineSnapshot: _isOfflineSnapshot,
                    isLoaded: _schedule != null && _schedule!.isNotEmpty,
                    isLoading: _loading,
                    onRefresh: _load,
                  ),
                ),
                Expanded(
                  child: _loading && (_schedule == null || _schedule!.isEmpty)
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? _ErrorState(
                              message: _error!,
                              onRetry: _load,
                            )
                          : _schedule == null || _schedule!.isEmpty
                              ? const _EmptyState(
                                  title: "Нет данных",
                                  subtitle:
                                      "Подрасписание на сегодня пока недоступно.",
                                )
                              : ListView.builder(
                                  controller: scrollController,
                                  physics: const BouncingScrollPhysics(
                                    parent: AlwaysScrollableScrollPhysics(),
                                  ),
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                  itemCount: _schedule!.length,
                                  itemBuilder: (_, i) => _MiniDayCard(
                                    day: _schedule![i],
                                    college: widget.controller.college,
                                    isTeacherMode:
                                        widget.controller.prefs.isTeacherMode,
                                    sheetTitle: widget.title,
                                    kind: widget.kind,
                                  ),
                                ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.title,
    required this.kind,
    required this.isTeacherMode,
    required this.isOfflineSnapshot,
    required this.isLoaded,
    required this.isLoading,
    required this.onRefresh,
  });

  final String title;
  final SubScheduleKind kind;

  /// Преподаватель открывает подрасписание группы; студент — преподавателя.
  final bool isTeacherMode;
  final bool isOfflineSnapshot;
  final bool isLoaded;
  final bool isLoading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primary.withAlpha(isDark ? 38 : 24),
            primary.withAlpha(isDark ? 16 : 10),
          ],
        ),
        border: Border.all(
          color: primary.withAlpha(isDark ? 48 : 28),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary.withAlpha(isDark ? 46 : 28),
            ),
            child: Icon(
              kind == SubScheduleKind.classroom
                  ? Icons.meeting_room_outlined
                  : (isTeacherMode
                      ? Icons.groups_outlined
                      : Icons.person_outline_rounded),
              color: primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
  final String sheetTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isToday = _isToday(day.date);
    final cardColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final isDark = theme.brightness == Brightness.dark;
    final items = day.items.toList()
      ..sort((a, b) => a.lessonNumber.compareTo(b.lessonNumber));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onLongPress: () => showDayShareSheet(
            context,
            day: day,
            college: college,
            shareText: _formatMiniDayAsText(items),
            subtitle: sheetTitle,
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: const Alignment(-0.6, -0.8),
                end: const Alignment(0.9, 1.0),
                colors: [
                  Color.alphaBlend(
                    primary.withAlpha(
                        isToday ? (isDark ? 44 : 28) : (isDark ? 20 : 12)),
                    cardColor,
                  ),
                  cardColor,
                ],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: primary.withAlpha(
                  isToday ? (isDark ? 52 : 34) : (isDark ? 24 : 14),
                ),
                width: 0.8,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          "${_capitalize(day.day)} • ${day.date}",
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: isToday ? primary : null,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (isToday)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: primary.withAlpha(isDark ? 42 : 20),
                          ),
                          child: Text(
                            "Сегодня",
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (items.isEmpty)
                    Text(
                      "Нет занятий",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(140),
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else
                    ...items.map((item) {
                      final time = LessonTimes.formatTime(
                        item.lessonNumber,
                        college: college,
                      );
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface
                                .withAlpha(isDark ? 10 : 5),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: primary.withAlpha(isDark ? 40 : 22),
                                ),
                                child: Text(
                                  "${item.lessonNumber}",
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  kind == SubScheduleKind.classroom
                                      ? _buildClassroomItemLine(item, time)
                                      : _buildTeacherOrGroupItemLine(
                                          item, time),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _buildClassroomItemLine(ScheduleItem item, String time) {
    final subject = (item.subject ?? "").trim();
    final teacherOrGroup = (item.teacher ?? "").trim();
    final parts = <String>[];
    if (subject.isNotEmpty) parts.add(subject);
    if (teacherOrGroup.isNotEmpty) parts.add(teacherOrGroup);
    if (time.isNotEmpty) parts.add(time);
    if (parts.isEmpty) return "Нет данных";
    return parts.join(" • ");
  }

  String _buildTeacherOrGroupItemLine(ScheduleItem item, String time) {
    final subject = (item.subject ?? "").trim();
    final classroom = (item.classroom ?? "").trim();
    final teacherOrGroup = (item.teacher ?? "").trim();

    final parts = <String>[];
    if (isTeacherMode) {
      if (teacherOrGroup.isNotEmpty && !_titleMatches(teacherOrGroup)) {
        parts.add(teacherOrGroup);
      }
      if (classroom.isNotEmpty) parts.add("Ауд. $classroom");
      if (subject.isNotEmpty &&
          subject != teacherOrGroup &&
          !_titleMatches(subject)) {
        parts.add(subject);
      }
    } else {
      if (subject.isNotEmpty && !_titleMatches(subject)) parts.add(subject);
      if (classroom.isNotEmpty) parts.add("Ауд. $classroom");
      if (teacherOrGroup.isNotEmpty && !_titleMatches(teacherOrGroup)) {
        parts.add(teacherOrGroup);
      }
    }
    if (item.subgroup != null) parts.add("${item.subgroup} п/г");
    if (time.isNotEmpty) parts.add(time);
    if (parts.isEmpty) return "Нет данных";
    return parts.join(" • ");
  }

  bool _titleMatches(String value) {
    final t = sheetTitle.trim();
    return t.isNotEmpty &&
        (t == value || "Ауд. $value" == t || t == "Ауд. $value");
  }

  bool _isToday(String rawDate) {
    final now = DateTime.now();
    final dotDate =
        "${now.day.toString().padLeft(2, "0")}.${now.month.toString().padLeft(2, "0")}.${now.year}";
    final isoDate =
        "${now.year}-${now.month.toString().padLeft(2, "0")}-${now.day.toString().padLeft(2, "0")}";
    return rawDate == dotDate || rawDate == isoDate;
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  String _formatMiniDayAsText(List<ScheduleItem> items) {
    final lines = <String>[
      "${_capitalize(day.day)}, ${day.date}",
      "",
    ];
    if (items.isEmpty) {
      lines.add("Нет занятий");
      return lines.join("\n");
    }
    for (final item in items) {
      final time = LessonTimes.formatTime(
        item.lessonNumber,
        college: college,
      );
      final line = kind == SubScheduleKind.classroom
          ? _buildClassroomItemLine(item, time)
          : _buildTeacherOrGroupItemLine(item, time);
      lines.add("${item.lessonNumber}. $line");
    }
    return lines.join("\n");
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 34,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 14),
            AppActionButton(
              icon: Icons.refresh_rounded,
              label: "Повторить",
              primary: true,
              onTap: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_busy_outlined,
              size: 34,
              color: theme.colorScheme.primary.withAlpha(180),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(140),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
