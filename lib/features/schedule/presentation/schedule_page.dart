import "dart:ui" as ui;
import "dart:io";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_staggered_animations/flutter_staggered_animations.dart";
import "package:share_plus/share_plus.dart";
import "package:path_provider/path_provider.dart";

import "../../../core/widgets/custom_refresh.dart";
import "../data/lesson_times.dart";
import "../data/preferences_manager.dart";
import "../domain/models.dart";
import "schedule_controller.dart";
import "sub_schedule_sheet.dart";

class SchedulePage extends StatelessWidget {
  const SchedulePage({super.key, required this.controller});
  final ScheduleController controller;

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
        if (schedule.isEmpty && !isLoading && error == null) {
          body = Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primary.withAlpha(15),
                    ),
                    child: Icon(Icons.event_note_outlined,
                        size: 36,
                        color: theme.colorScheme.primary.withAlpha(120)),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    prefs.isGroupSelected
                        ? "Потяните вниз для загрузки"
                        : "Выберите группу в настройках",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  if (!prefs.isGroupSelected) ...[
                    const SizedBox(height: 6),
                    Text(
                      "Перейдите на вкладку Настройки",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          );
        } else if (error != null && schedule.isEmpty) {
          body = Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.error.withAlpha(15),
                    ),
                    child: Icon(Icons.cloud_off_outlined,
                        size: 36, color: theme.colorScheme.error),
                  ),
                  const SizedBox(height: 16),
                  Text(error,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error)),
                  const SizedBox(height: 8),
                  Text("Потяните вниз для обновления",
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          );
        } else {
          final useAnimations = schedule.length <= 14;
          final listView = ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
            itemCount: schedule.length,
            itemBuilder: (context, index) {
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
            },
          );
          body = useAnimations ? AnimationLimiter(child: listView) : listView;
        }

        return CustomRefreshWrapper(
          onRefresh: controller.refreshSchedule,
          color: theme.colorScheme.primary,
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
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(primary.withAlpha(28), cardColor),
                Color.alphaBlend(primary.withAlpha(12), cardColor),
                cardColor,
              ],
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
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
                            "${items.length} ${_lessonsWord(items.length)}",
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
    HapticFeedback.mediumImpact();
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withAlpha(40),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(Icons.share_outlined, color: theme.colorScheme.primary),
              title: const Text("Поделиться"),
              onTap: () {
                Navigator.pop(ctx);
                SharePlus.instance.share(
                  ShareParams(text: _formatDayAsText(items)),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.copy_outlined, color: theme.colorScheme.primary),
              title: const Text("Скопировать"),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: _formatDayAsText(items)));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Скопировано"), duration: Duration(seconds: 1)),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.image_outlined, color: theme.colorScheme.primary),
              title: const Text("Поделиться изображением"),
              onTap: () async {
                Navigator.pop(ctx);
                await _shareDayAsImage(context, items);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _shareDayAsImage(
    BuildContext context,
    List<ScheduleItem> items,
  ) async {
    ui.Image? image;
    try {
      image = await _renderDayImage(context, items);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final pngBytes = bytes.buffer.asUint8List();
      final safeDate = day.date.replaceAll(".", "-");
      final fileName =
          "schedule_${safeDate}_${DateTime.now().millisecondsSinceEpoch}.png";
      final text = "${_capitalizeDay(day.day)}, ${_formatDate(day.date)}";
      final dir = await getTemporaryDirectory();
      final file = File("${dir.path}/$fileName");
      await file.writeAsBytes(pngBytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: "image/png", name: fileName)],
          text: text,
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Не удалось сформировать изображение")),
        );
      }
    } finally {
      image?.dispose();
    }
  }

  Future<ui.Image> _renderDayImage(
    BuildContext context,
    List<ScheduleItem> items,
  ) async {
    final theme = Theme.of(context);
    const width = 1200.0;
    const horizontalPadding = 44.0;
    const topPadding = 36.0;
    const headerGap = 16.0;
    const rowGap = 10.0;
    const rowMinHeight = 88.0;
    const badgeSize = 44.0;
    const footerHeight = 34.0;

    final sortedItems = items.toList()
      ..sort((a, b) => a.lessonNumber.compareTo(b.lessonNumber));

    final isDark = theme.brightness == Brightness.dark;
    final baseA = isDark ? const Color(0xFF0E172A) : const Color(0xFFEFF4FF);
    final baseB = isDark ? const Color(0xFF111827) : const Color(0xFFE7EEFF);
    final accent = HSLColor.fromColor(theme.colorScheme.primary)
        .withSaturation(
          (HSLColor.fromColor(theme.colorScheme.primary).saturation + 0.12)
              .clamp(0.0, 1.0),
        )
        .withLightness(
          (HSLColor.fromColor(theme.colorScheme.primary).lightness + 0.02)
              .clamp(0.0, 1.0),
        )
        .toColor();
    final blendSoft = Color.alphaBlend(accent.withAlpha(78), baseB);
    final blendDeep = Color.alphaBlend(accent.withAlpha(44), baseA);

    final fgPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final fgSecondary =
        isDark ? Colors.white.withAlpha(210) : const Color(0xFF334155);
    final fgMuted =
        isDark ? Colors.white.withAlpha(180) : const Color(0xFF475569);

    final headerStyle = TextStyle(
      color: fgPrimary,
      fontSize: 44,
      fontWeight: FontWeight.w700,
      height: 1.08,
    );
    final subStyle = TextStyle(
      color: fgSecondary,
      fontSize: 24,
      fontWeight: FontWeight.w500,
      height: 1.16,
    );
    final titleStyle = TextStyle(
      color: fgPrimary,
      fontSize: 26,
      fontWeight: FontWeight.w700,
      height: 1.14,
    );
    final detailsStyle = TextStyle(
      color: fgMuted,
      fontSize: 20,
      fontWeight: FontWeight.w500,
      height: 1.2,
    );

    TextPainter tp(
      String text,
      TextStyle style,
      double maxWidth, {
      int? maxLines,
    }) {
      final p = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        maxLines: maxLines,
        ellipsis: maxLines == null ? null : "...",
      )..layout(maxWidth: maxWidth, minWidth: 0);
      return p;
    }

    final dateLabel = "${_capitalizeDay(day.day)}, ${_formatDate(day.date)}";
    final titlePainter =
        tp("Расписание", headerStyle, width - horizontalPadding * 2);
    final datePainter = tp(dateLabel, subStyle, width - horizontalPadding * 2);
    final groupPainter = tp(
      prefs.selectedGroupName.isEmpty ? "Группа не выбрана" : prefs.selectedGroupName,
      subStyle.copyWith(fontSize: 20, color: fgMuted),
      width - horizontalPadding * 2,
      maxLines: 1,
    );

    final rows = sortedItems
        .map((item) {
          final time = LessonTimes.formatTime(item.lessonNumber, college: college);
          final baseTitle = item.subject?.trim().isNotEmpty == true
              ? item.subject!.trim()
              : "—";
          final subgroupLabel = item.subgroup == null ? null : "П/Г ${item.subgroup}";
          final detailsParts = <String>[
            if (time.isNotEmpty) time,
            if (item.classroom?.isNotEmpty == true) "Ауд. ${item.classroom}",
            if (item.teacher?.isNotEmpty == true) item.teacher!,
          ];
          final details = detailsParts.join("  ·  ");
          return (
            num: item.lessonNumber,
            title: baseTitle,
            subgroup: subgroupLabel,
            details: details,
          );
        })
        .toList();

    const contentWidth = width - horizontalPadding * 2;
    const textAreaWidth = contentWidth - badgeSize - 22;

    var rowsHeight = 0.0;
    if (rows.isEmpty) {
      final emptyPainter = tp("Нет занятий", titleStyle, contentWidth - 28, maxLines: 1);
      rowsHeight = (emptyPainter.height + 24) > rowMinHeight
          ? (emptyPainter.height + 24)
          : rowMinHeight;
    } else {
      for (final row in rows) {
        final rowTitle = tp(row.title, titleStyle, textAreaWidth, maxLines: 2);
        final subgroupPainter = row.subgroup == null
            ? null
            : tp(
                row.subgroup!,
                detailsStyle.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: fgSecondary,
                ),
                textAreaWidth * 0.6,
                maxLines: 1,
              );
        final rowDetails =
            row.details.isEmpty ? null : tp(row.details, detailsStyle, textAreaWidth, maxLines: 2);
        final textHeight = rowTitle.height +
            (subgroupPainter?.height ?? 0) +
            (rowDetails?.height ?? 0) +
            (subgroupPainter != null ? 6 : 0) +
            (rowDetails != null ? 8 : 0);
        final rowHeight = (textHeight + 20) > rowMinHeight
            ? (textHeight + 20)
            : rowMinHeight;
        rowsHeight += rowHeight + rowGap;
      }
      if (rowsHeight > 0) rowsHeight -= rowGap;
    }

    final headerHeight = titlePainter.height + 6 + datePainter.height + 4 + groupPainter.height;
    final height =
        topPadding + headerHeight + headerGap + rowsHeight + footerHeight + 20;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
    final primary = theme.colorScheme.primary;
    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(width, height),
        [
          blendDeep,
          baseA,
          blendSoft,
          baseB,
        ],
        const [0.0, 0.28, 0.68, 1.0],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), bgPaint);

    // Soft glows make gradient transitions smoother.
    canvas.drawCircle(
      const Offset(width - 120, -40),
      260,
      Paint()..color = accent.withAlpha(30),
    );
    canvas.drawCircle(
      Offset(-70, height + 30),
      280,
      Paint()..color = accent.withAlpha(20),
    );

    titlePainter.paint(canvas, const Offset(horizontalPadding, topPadding));
    datePainter.paint(
      canvas,
      Offset(horizontalPadding, topPadding + titlePainter.height + 6),
    );
    groupPainter.paint(
      canvas,
      Offset(horizontalPadding, topPadding + titlePainter.height + datePainter.height + 10),
    );

    final countChip = tp(
      "${rows.length} ${_lessonsWord(rows.length)}",
      subStyle.copyWith(fontSize: 18, color: fgPrimary),
      220,
      maxLines: 1,
    );
    final chipW = countChip.width + 24;
    const chipH = 34.0;
    final chipX = width - horizontalPadding - chipW;
    const chipY = topPadding + 6;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(chipX, chipY, chipW, chipH),
        const Radius.circular(12),
      ),
      Paint()..color = (isDark ? Colors.white : Colors.black).withAlpha(22),
    );
    countChip.paint(
      canvas,
      Offset(chipX + 12, chipY + (chipH - countChip.height) / 2),
    );

    var y = topPadding + headerHeight + headerGap;
    final rowBgPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withAlpha(isDark ? 24 : 12);
    final badgePaint = Paint()..color = primary.withAlpha(220);
    final badgeTextStyle = TextStyle(
      color: theme.colorScheme.onPrimary,
      fontSize: 20,
      fontWeight: FontWeight.w700,
    );

    if (rows.isEmpty) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(horizontalPadding, y, contentWidth, rowMinHeight),
        const Radius.circular(18),
      );
      canvas.drawRRect(rect, rowBgPaint);
      final emptyPainter = tp("Нет занятий", titleStyle, contentWidth - 24, maxLines: 1);
      emptyPainter.paint(
        canvas,
        Offset(
          horizontalPadding + 12,
          y + (rowMinHeight - emptyPainter.height) / 2,
        ),
      );
      y += rowMinHeight;
    } else {
      for (final row in rows) {
        final rowTitle = tp(row.title, titleStyle, textAreaWidth, maxLines: 2);
        final subgroupPainter = row.subgroup == null
            ? null
            : tp(
                row.subgroup!,
                detailsStyle.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: fgSecondary,
                ),
                textAreaWidth * 0.6,
                maxLines: 1,
              );
        final rowDetails =
            row.details.isEmpty ? null : tp(row.details, detailsStyle, textAreaWidth, maxLines: 2);
        final textHeight = rowTitle.height +
            (subgroupPainter?.height ?? 0) +
            (rowDetails?.height ?? 0) +
            (subgroupPainter != null ? 6 : 0) +
            (rowDetails != null ? 8 : 0);
        final rowHeight = (textHeight + 20) > rowMinHeight
            ? (textHeight + 20)
            : rowMinHeight;

        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(horizontalPadding, y, contentWidth, rowHeight),
          const Radius.circular(18),
        );
        canvas.drawRRect(rect, rowBgPaint);

        const badgeX = horizontalPadding + 10;
        final badgeY = y + (rowHeight - badgeSize) / 2;
        canvas.drawCircle(
          Offset(badgeX + badgeSize / 2, badgeY + badgeSize / 2),
          badgeSize / 2,
          badgePaint,
        );
        final badgeText = tp("${row.num}", badgeTextStyle, badgeSize);
        badgeText.paint(
          canvas,
          Offset(
            badgeX + (badgeSize - badgeText.width) / 2,
            badgeY + (badgeSize - badgeText.height) / 2,
          ),
        );

        const textX = badgeX + badgeSize + 12;
        final titleY = y + 10;
        final titleForPaint = tp(row.title, titleStyle, textAreaWidth, maxLines: 2);
        titleForPaint.paint(canvas, Offset(textX, titleY));

        var textCursorY = titleY + titleForPaint.height;
        if (subgroupPainter != null) {
          textCursorY += 6;
          final chipW = subgroupPainter.width + 18;
          final chipH = subgroupPainter.height + 6;
          const chipX = textX;
          final chipY = textCursorY;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(chipX, chipY, chipW, chipH),
              const Radius.circular(8),
            ),
            Paint()
              ..color = (isDark ? Colors.white : Colors.black)
                  .withAlpha(isDark ? 18 : 10),
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(chipX, chipY, chipW, chipH),
              const Radius.circular(8),
            ),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = fgSecondary.withAlpha(isDark ? 85 : 70),
          );
          subgroupPainter.paint(
            canvas,
            Offset(
              chipX + (chipW - subgroupPainter.width) / 2,
              chipY + (chipH - subgroupPainter.height) / 2,
            ),
          );
          textCursorY += chipH;
        }
        if (rowDetails != null) {
          textCursorY += 6;
          rowDetails.paint(canvas, Offset(textX, textCursorY));
        }
        y += rowHeight + rowGap;
      }
    }

    final footerPainter = tp(
      "Raspisanie • $dateLabel",
      TextStyle(
        color: fgMuted.withAlpha(190),
        fontSize: 18,
        fontWeight: FontWeight.w500,
      ),
      width - horizontalPadding * 2,
    );
    footerPainter.paint(canvas, Offset(horizontalPadding, height - footerHeight));

    return recorder.endRecording().toImage(width.toInt(), height.toInt());
  }

  String _formatDayAsText(List<ScheduleItem> items) {
    final buf = StringBuffer();
    buf.writeln("${_capitalizeDay(day.day)}, ${_formatDate(day.date)}");
    buf.writeln();
    for (final item in items) {
      buf.write("${item.lessonNumber}. ${item.subject ?? '—'}");
      if (item.subgroup != null) buf.write(" (${item.subgroup} п/г)");
      if (item.classroom != null && item.classroom!.isNotEmpty) buf.write(" — ${item.classroom}");
      if (item.teacher != null && item.teacher!.isNotEmpty) buf.write(" — ${item.teacher}");
      buf.writeln();
    }
    return buf.toString().trimRight();
  }

  List<Widget> _buildLessonList(BuildContext context, List<ScheduleItem> items) {
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
            final bt = LessonTimes.getBreakText(prevNum, lessonNum, college: college);
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

  String _capitalizeDay(String d) => d.isEmpty ? d : d[0].toUpperCase() + d.substring(1);

  String _formatDate(String date) {
    try {
      final parts = date.split(".");
      if (parts.length != 3) return date;
      final d = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      const months = ["", "января", "февраля", "марта", "апреля", "мая",
        "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"];
      if (m < 1 || m > 12) return date;
      return "$d ${months[m]}";
    } catch (_) { return date; }
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
            colors: [
              theme.colorScheme.primary.withAlpha(16),
              theme.colorScheme.primary.withAlpha(6),
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

  Widget _singleLesson(BuildContext context, ThemeData theme, ScheduleItem item) {
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
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: theme.colorScheme.primary.withAlpha(25),
                  ),
                  child: Text(
                    "$sg п/г",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
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
    if (item.classroom != null && item.classroom!.isNotEmpty) {
      lines.add(_detailLine(
        context: context,
        theme: theme,
        icon: Icons.meeting_room_outlined,
        text: item.classroom!,
        href: item.classroomHref,
      ));
    }
    if (controller.prefs.isTeacherMode) {
      if (item.subject != null && item.subject!.isNotEmpty) {
        lines.add(_detailLine(
          context: context,
          theme: theme,
          icon: Icons.groups_2_outlined,
          text: item.subject!,
          href: item.subjectHref,
        ));
      }
    } else if (item.teacher != null && item.teacher!.isNotEmpty) {
      lines.add(_detailLine(
        context: context,
        theme: theme,
        icon: Icons.person_outline_rounded,
        text: item.teacher!,
        href: item.teacherHref,
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

  Widget _lessonTitle(BuildContext context, ThemeData theme, ScheduleItem item) {
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
        ? "${startTime.startTime} – ${endTime.endTime}" : "";

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.colorScheme.onSurface.withAlpha(25),
                width: 1.5,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.free_breakfast_outlined, size: 16,
                color: theme.colorScheme.onSurface.withAlpha(50)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurface.withAlpha(100))),
                if (timeLabel.isNotEmpty)
                  Text(timeLabel, style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11, color: theme.colorScheme.onSurface.withAlpha(60))),
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 48, top: 2, bottom: 2),
      child: Text(text, style: theme.textTheme.bodySmall?.copyWith(
        fontStyle: FontStyle.italic, fontSize: 11,
        color: theme.colorScheme.onSurface.withAlpha(80),
      )),
    );
  }
}
