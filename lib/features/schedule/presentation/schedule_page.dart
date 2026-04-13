import "package:flutter/material.dart";
import "package:flutter_staggered_animations/flutter_staggered_animations.dart";

import "../../../app/theme.dart";
import "../../../core/services/analytics_service.dart";
import "../../../core/services/font_service.dart";
import "../../../core/widgets/animated_app_bar.dart";
import "package:easy_refresh/easy_refresh.dart";

import "../../../core/widgets/custom_refresh.dart";
import "../../../core/widgets/empty_state_view.dart";
import "../data/lesson_times.dart";
import "../data/preferences_manager.dart";
import "../domain/models.dart";
import "day_share_sheet.dart";
import "schedule_controller.dart";
import "sub_schedule_sheet.dart";

class SchedulePage extends StatelessWidget {
  const SchedulePage({
    super.key,
    required this.controller,
    required this.fontService,
  });
  final ScheduleController controller;
  final FontService fontService;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final schedule = controller.schedule;
        final isLoading = controller.isLoading;
        final error = controller.error;
        final college = controller.college;
        final prefs = controller.prefs;

        Widget body;
        if (schedule.isEmpty && isLoading) {
          body = Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  "Загрузка расписания…",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        } else if (schedule.isEmpty && !isLoading && error == null) {
          body = EmptyStateView(
            icon: Icons.event_note_outlined,
            message: prefs.isGroupSelected
                ? "Потяните вниз для загрузки"
                : (prefs.isTeacherMode
                    ? "Выберите преподавателя в настройках"
                    : "Выберите группу в настройках"),
            subtitle:
                prefs.isGroupSelected ? null : "Перейдите на вкладку Настройки",
          );
        } else if (error != null && schedule.isEmpty) {
          body = EmptyStateView(
            icon: Icons.cloud_off_outlined,
            message: error,
            subtitle: "Потяните вниз для обновления",
            isError: true,
          );
        } else {
          final useAnimations = schedule.length <= 14;
          // Баннер по тексту [error], без геттеров на [ScheduleController] —
          // иначе после hot reload старый инстанс контроллера даёт Lookup failed.
          final showOfflineBanner = error != null &&
              (error.contains("Показаны сохранённые") ||
                  error.contains("Не удалось обновить"));
          final offlineBannerKey =
              showOfflineBanner ? "${prefs.selectedGroupFile}|$error" : "";
          final offlineBannerDismissed = offlineBannerKey.isNotEmpty &&
              prefs.dismissedOfflineBannerKey == offlineBannerKey;

          final listPadding = EdgeInsets.fromLTRB(
            12,
            contentTopUnderAppBar(context),
            12,
            contentBottomPadding(context),
          );
          Widget buildDayItem(int index) {
            final card = _DayCard(
              day: schedule[index],
              college: college,
              prefs: prefs,
              controller: controller,
            );
            if (!useAnimations) return card;
            return AnimationConfiguration.staggeredList(
              position: index,
              duration: const Duration(milliseconds: 300),
              child: SlideAnimation(
                verticalOffset: 30.0,
                child: FadeInAnimation(child: card),
              ),
            );
          }

          final Widget listView;
          if (showOfflineBanner && !offlineBannerDismissed) {
            final lastMs = prefs.lastScheduleNetworkOkMs;
            // Баннер уже содержит верхний отступ под AppBar — список сразу за ним.
            final bannerListPadding = listPadding.copyWith(top: 8);
            // Один CustomScrollView: pull-to-refresh срабатывает и при тяге с баннера,
            // а не только с области списка (Column+Expanded(ListView) ломал жест).
            listView = CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.only(top: contentTopUnderAppBar(context)),
                ),
                const HeaderLocator.sliver(),
                SliverToBoxAdapter(
                  child: _ScheduleOfflineBanner(
                    controller: controller,
                    theme: theme,
                    topPadding: 0,
                    lastSync: lastMs != null
                        ? DateTime.fromMillisecondsSinceEpoch(lastMs)
                        : null,
                    errorHint: error,
                    bannerKey: offlineBannerKey,
                  ),
                ),
                SliverPadding(
                  padding: bannerListPadding.copyWith(top: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => buildDayItem(index),
                      childCount: schedule.length,
                    ),
                  ),
                ),
              ],
            );
          } else {
            listView = CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.only(top: contentTopUnderAppBar(context)),
                ),
                const HeaderLocator.sliver(),
                SliverPadding(
                  padding: listPadding.copyWith(top: 0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => buildDayItem(index),
                      childCount: schedule.length,
                    ),
                  ),
                ),
              ],
            );
          }

          body = useAnimations ? AnimationLimiter(child: listView) : listView;
        }

        // Без прокрутки pull-to-refresh на пустых/загрузочных экранах не срабатывает.
        // Важно: сохранить виджет в отдельную переменную — иначе [body] внутри
        // [LayoutBuilder] указывает на сам LayoutBuilder (рекурсия, нет размера).
        if (schedule.isEmpty) {
          final emptyStateContent = body;
          body = CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.only(top: contentTopUnderAppBar(context)),
              ),
              const HeaderLocator.sliver(),
              SliverFillRemaining(
                hasScrollBody: false,
                child: emptyStateContent,
              ),
            ],
          );
        }

        return CustomRefreshWrapper(
          onRefresh: () async {
            final group = controller.selectedGroup;
            AnalyticsService.instance.logEvent("schedule_refresh", {
              "college": controller.college,
              "group": group?.name,
              "is_teacher_mode": prefs.isTeacherMode,
            });
            await controller.refreshSchedule();
          },
          color: theme.colorScheme.primary,
          appBarExtent: AnimatedAppBarVisuals.totalHeight(context),
          child: body,
        );
      },
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.day,
    required this.college,
    required this.prefs,
    required this.controller,
  });

  final DaySchedule day;
  final String college;
  final PreferencesManager prefs;
  final ScheduleController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = day.items.toList()
      ..sort((a, b) => a.lessonNumber.compareTo(b.lessonNumber));

    final cardColor = theme.cardTheme.color ?? theme.cardColor;
    final primary = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-0.6, -0.8),
              end: Alignment(0.8, 1.0),
              stops: const [0.0, 0.4, 0.75, 1.0],
              colors: [
                Color.alphaBlend(primary.withAlpha(22), cardColor),
                Color.alphaBlend(primary.withAlpha(12), cardColor),
                Color.alphaBlend(primary.withAlpha(6), cardColor),
                cardColor,
              ],
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onLongPress: () => _showShareMenu(context, items),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 20,
                        decoration: BoxDecoration(
                          color: primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _capitalizeDay(day.day),
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _formatDate(day.date),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      if (items.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface.withAlpha(10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "${_lessonCount(items)} ${_lessonsWord(_lessonCount(items))}",
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontSize: 10),
                          ),
                        ),
                    ],
                  ),
                  if (items.isEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      "Нет занятий",
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontStyle: FontStyle.italic),
                    ),
                  ] else ...[
                    const SizedBox(height: 10),
                    ..._buildLessonList(context, items),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showShareMenu(BuildContext context, List<ScheduleItem> items) {
    showDayShareSheet(
      context,
      day: day,
      college: college,
      shareText: _formatDayAsText(items),
      subtitle: prefs.selectedGroupName.trim(),
    );
  }

  String _formatDayAsText(List<ScheduleItem> items) {
    final buf = StringBuffer();
    buf.writeln("${_capitalizeDay(day.day)}, ${_formatDate(day.date)}");
    buf.writeln();
    final sel = prefs.selectedGroupName.trim();
    for (final item in items) {
      buf.write("${item.lessonNumber}. ${item.subject ?? '—'}");
      if (item.subgroup != null) buf.write(" (${item.subgroup} п/г)");
      final skipClassroom = item.classroom != null &&
          item.classroom!.isNotEmpty &&
          (sel == "Ауд. ${item.classroom}".trim() ||
              sel == item.classroom!.trim());
      if (item.classroom != null &&
          item.classroom!.isNotEmpty &&
          !skipClassroom) {
        buf.write(" — ${item.classroom}");
      }
      if (item.teacher != null && item.teacher!.isNotEmpty) {
        buf.write(" — ${item.teacher}");
      }
      buf.writeln();
    }
    return buf.toString().trimRight();
  }

  int _lessonCount(List<ScheduleItem> items) =>
      items.map((item) => item.lessonNumber).toSet().length;

  List<Widget> _buildLessonList(
      BuildContext context, List<ScheduleItem> items) {
    final widgets = <Widget>[];
    final showBreaks = prefs.showBreaks;
    final showLunch = prefs.showLunch;
    final showTime = prefs.showTime;
    final showStatus = prefs.showLessonStatus;
    final now = DateTime.now();

    final grouped = <int, List<ScheduleItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.lessonNumber, () => []).add(item);
    }
    final sortedKeys = grouped.keys.toList()..sort();

    for (var ki = 0; ki < sortedKeys.length; ki++) {
      final lessonNum = sortedKeys[ki];
      final lessonItems = grouped[lessonNum]!;

      LessonStatus status = LessonStatus.none;
      if (showStatus) {
        status = LessonTimes.getLessonStatus(lessonNum, college, now, day.date);
      }

      if (ki > 0) {
        final prevNum = sortedKeys[ki - 1];
        final gap = lessonNum - prevNum;
        if (gap > 1) {
          final gapDetails = <String>[];
          for (var g = prevNum; g < lessonNum; g++) {
            if (showLunch) {
              final lt = LessonTimes.getLunchText(g, college: college);
              if (lt != null) gapDetails.add(lt);
            }
            if (showBreaks && g + 1 < lessonNum) {
              final bt = LessonTimes.getBreakText(g, g + 1, college: college);
              if (bt != null) gapDetails.add(bt);
            }
          }
          widgets.add(_WindowRow(
            from: prevNum + 1,
            to: lessonNum - 1,
            college: college,
            details: gapDetails,
          ));
        } else {
          if (showLunch) {
            final lt = LessonTimes.getLunchText(prevNum, college: college);
            if (lt != null) widgets.add(_InfoRow(text: lt));
          }
          if (showBreaks) {
            final bt =
                LessonTimes.getBreakText(prevNum, lessonNum, college: college);
            if (bt != null) widgets.add(_InfoRow(text: bt));
          }
        }
      }

      widgets.add(_LessonTile(
        lessonNumber: lessonNum,
        items: lessonItems,
        college: college,
        showTime: showTime,
        status: status,
        controller: controller,
      ));
    }

    return widgets;
  }

  String _lessonsWord(int n) {
    if (n % 10 == 1 && n % 100 != 11) return "пара";
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) {
      return "пары";
    }
    return "пар";
  }

  String _capitalizeDay(String d) =>
      d.isEmpty ? d : d[0].toUpperCase() + d.substring(1);

  String _formatDate(String date) {
    try {
      final parts = date.split(".");
      if (parts.length != 3) return date;
      final d = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      const months = [
        "",
        "января",
        "февраля",
        "марта",
        "апреля",
        "мая",
        "июня",
        "июля",
        "августа",
        "сентября",
        "октября",
        "ноября",
        "декабря"
      ];
      if (m < 1 || m > 12) return date;
      return "$d ${months[m]}";
    } catch (_) {
      return date;
    }
  }
}

class _LessonTile extends StatelessWidget {
  const _LessonTile({
    required this.lessonNumber,
    required this.items,
    required this.college,
    required this.showTime,
    required this.status,
    required this.controller,
  });

  final int lessonNumber;
  final List<ScheduleItem> items;
  final String college;
  final bool showTime;
  final LessonStatus status;
  final ScheduleController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCurrent = status == LessonStatus.current;
    final isNext = status == LessonStatus.next;
    final time = LessonTimes.formatTime(lessonNumber, college: college);

    final badgeColor = isCurrent
        ? theme.colorScheme.primary
        : isNext
            ? theme.colorScheme.primary.withAlpha(140)
            : theme.colorScheme.onSurface.withAlpha(18);
    final badgeTextColor = (isCurrent || isNext)
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;

    final hasMultiple = items.length > 1;
    final hasAnySub = items.any((i) => i.subgroup != null);

    Widget content;
    if (!hasMultiple && !hasAnySub) {
      content = _singleLesson(context, theme, items.first);
    } else {
      content = _subgroupLesson(context, theme);
    }

    Widget tile = Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isCurrent
              ? theme.colorScheme.primary.withAlpha(10)
              : theme.colorScheme.onSurface.withAlpha(4),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: badgeColor,
                      boxShadow: isCurrent
                          ? [
                              BoxShadow(
                                color: theme.colorScheme.primary.withAlpha(40),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      "$lessonNumber",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: badgeTextColor,
                      ),
                    ),
                  ),
                  if (isCurrent || isNext)
                    Positioned(
                      top: 1,
                      right: 1,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primary,
                          border: Border.all(
                            color: theme.cardTheme.color ?? theme.cardColor,
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showTime && time.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(time,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontSize: 11)),
                    ),
                  content,
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (isCurrent) {
      tile = Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            stops: const [0.0, 0.3, 0.7, 1.0],
            colors: [
              theme.colorScheme.primary.withAlpha(22),
              theme.colorScheme.primary.withAlpha(12),
              theme.colorScheme.primary.withAlpha(8),
              theme.colorScheme.primary.withAlpha(5),
            ],
          ),
          border: Border(
            left: BorderSide(color: theme.colorScheme.primary, width: 3),
          ),
        ),
        padding: const EdgeInsets.only(left: 6),
        child: tile,
      );
    }

    return tile;
  }

  Widget _singleLesson(
      BuildContext context, ThemeData theme, ScheduleItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _lessonTitle(context, theme, item),
        const SizedBox(height: 2),
        _infoLine(context, theme, item),
      ],
    );
  }

  Widget _subgroupLesson(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.map((item) {
        final sg = item.subgroup;
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _lessonTitle(context, theme, item),
                    _infoLine(context, theme, item),
                  ],
                ),
              ),
              if (sg != null) ...[
                const SizedBox(width: 8),
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: theme.colorScheme.primary.withAlpha(25),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.groups_outlined,
                        size: 13,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "$sg п/г",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _infoLine(BuildContext context, ThemeData theme, ScheduleItem item) {
    final lines = <Widget>[];
    final sel = controller.prefs.selectedGroupName.trim();
    final isViewByClassroom = item.classroom != null &&
        item.classroom!.isNotEmpty &&
        (sel == "Ауд. ${item.classroom}".trim() ||
            sel == item.classroom!.trim());
    final hasClassroomLink =
        item.classroomHref != null && item.classroomHref!.isNotEmpty;
    final showClassroom = item.classroom != null &&
        item.classroom!.isNotEmpty &&
        (!isViewByClassroom || hasClassroomLink);
    if (showClassroom) {
      lines.add(_detailLine(
        context: context,
        theme: theme,
        icon: Icons.meeting_room_outlined,
        text: item.classroom!,
        href: item.classroomHref,
        subScheduleKind: SubScheduleKind.classroom,
      ));
    }
    if (controller.prefs.isTeacherMode) {
      if (item.subject != null && item.subject!.isNotEmpty) {
        lines.add(_detailLine(
          context: context,
          theme: theme,
          icon: Icons.groups_outlined,
          text: item.subject!,
          href: item.subjectHref,
          subScheduleKind: SubScheduleKind.teacherOrGroup,
        ));
      }
    } else if (item.teacher != null && item.teacher!.isNotEmpty) {
      lines.add(_detailLine(
        context: context,
        theme: theme,
        icon: Icons.person_outline_rounded,
        text: item.teacher!,
        href: item.teacherHref,
        subScheduleKind: SubScheduleKind.teacherOrGroup,
      ));
    }
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines,
      ),
    );
  }

  Widget _lessonTitle(
      BuildContext context, ThemeData theme, ScheduleItem item) {
    final isTeacherMode = controller.prefs.isTeacherMode;
    final displayText = isTeacherMode
        ? ((item.teacher?.trim().isNotEmpty ?? false)
            ? item.teacher!.trim()
            : (item.subject?.trim().isNotEmpty ?? false)
                ? item.subject!.trim()
                : "—")
        : (item.subject?.trim().isNotEmpty ?? false)
            ? item.subject!.trim()
            : "—";
    return Text(
      displayText,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _detailLine({
    required BuildContext context,
    required ThemeData theme,
    required IconData icon,
    required String text,
    required String? href,
    SubScheduleKind subScheduleKind = SubScheduleKind.teacherOrGroup,
  }) {
    final tappable = href != null && href.isNotEmpty;
    final textColor = tappable
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withAlpha(150);
    final line = Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor.withAlpha(180)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: textColor,
                decoration: tappable ? TextDecoration.underline : null,
                decorationColor:
                    tappable ? theme.colorScheme.primary.withAlpha(110) : null,
                fontWeight: tappable ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
    if (!tappable) return line;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => showSubScheduleSheet(
        context: context,
        file: href,
        controller: controller,
        title: text,
        kind: subScheduleKind,
      ),
      child: line,
    );
  }
}

class _WindowRow extends StatelessWidget {
  const _WindowRow({
    required this.from,
    required this.to,
    required this.college,
    this.details = const [],
  });
  final int from;
  final int to;
  final String college;
  final List<String> details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = to - from + 1;
    final label = count == 1 ? "Окно ($from пара)" : "Окно ($from–$to пары)";
    final startTime = LessonTimes.getTime(from, college: college);
    final endTime = LessonTimes.getTime(to, college: college);
    final timeLabel = (startTime != null && endTime != null)
        ? "${startTime.startTime} – ${endTime.endTime}"
        : "";

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.colorScheme.onSurface.withAlpha(25),
                width: 1.5,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.free_breakfast_outlined,
                size: 16, color: theme.colorScheme.onSurface.withAlpha(50)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurface.withAlpha(100))),
                if (timeLabel.isNotEmpty)
                  Text(timeLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withAlpha(60))),
                if (details.isNotEmpty)
                  Text(
                    details.join(" · "),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: theme.colorScheme.onSurface.withAlpha(70),
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

class _ScheduleOfflineBanner extends StatefulWidget {
  const _ScheduleOfflineBanner({
    required this.controller,
    required this.theme,
    required this.topPadding,
    required this.lastSync,
    required this.bannerKey,
    this.errorHint,
  });

  final ScheduleController controller;
  final ThemeData theme;
  final double topPadding;
  final DateTime? lastSync;
  final String? errorHint;
  final String bannerKey;

  @override
  State<_ScheduleOfflineBanner> createState() => _ScheduleOfflineBannerState();
}

class _ScheduleOfflineBannerState extends State<_ScheduleOfflineBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: _BannerContent(
          theme: widget.theme,
          topPadding: widget.topPadding,
          lastSync: widget.lastSync,
          errorHint: widget.errorHint,
          onClose: () async {
            widget.controller.prefs.dismissedOfflineBannerKey =
                widget.bannerKey;
            await _ctrl.reverse();
            if (!mounted) return;
            setState(() => _hidden = true);
          },
        ),
      ),
    );
  }
}

class _BannerContent extends StatelessWidget {
  const _BannerContent({
    required this.theme,
    required this.topPadding,
    required this.lastSync,
    required this.onClose,
    this.errorHint,
  });

  final ThemeData theme;
  final double topPadding;
  final DateTime? lastSync;
  final String? errorHint;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    final last = lastSync != null
        ? "${lastSync!.day.toString().padLeft(2, "0")}.${lastSync!.month.toString().padLeft(2, "0")} "
            "${lastSync!.hour.toString().padLeft(2, "0")}:${lastSync!.minute.toString().padLeft(2, "0")}"
        : null;

    // Получаем чистый текст ошибки — убираем префикс «Показаны сохранённые данные. »
    String? hint = errorHint?.trim();
    if (hint != null) {
      const prefix1 = "Показаны сохранённые данные. ";
      const prefix2 = "Не удалось обновить. ";
      if (hint.startsWith(prefix1)) hint = hint.substring(prefix1.length);
      if (hint.startsWith(prefix2)) hint = hint.substring(prefix2.length);
      if (hint.isEmpty) hint = null;
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(12, topPadding + 6, 12, 4),
      child: Container(
        decoration: BoxDecoration(
          color: cs.errorContainer.withAlpha(230),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: cs.error.withAlpha(60),
            width: 0.8,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.wifi_off_rounded,
                  size: 18,
                  color: cs.onErrorContainer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Нет сети — показано сохранённое расписание",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (hint != null && hint.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          hint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onErrorContainer.withAlpha(200),
                          ),
                        ),
                      ),
                    if (last != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          "Обновлено: $last",
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onErrorContainer.withAlpha(170),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: "Закрыть",
                onPressed: onClose,
                visualDensity: VisualDensity.compact,
                splashRadius: 18,
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: cs.onErrorContainer.withAlpha(210),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 48, top: 2, bottom: 2),
      child: Text(text,
          style: theme.textTheme.bodySmall?.copyWith(
            fontStyle: FontStyle.italic,
            fontSize: 11,
            color: theme.colorScheme.onSurface.withAlpha(80),
          )),
    );
  }
}
