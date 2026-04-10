import "dart:io";
import "dart:ui" as ui;

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:path_provider/path_provider.dart";
import "package:share_plus/share_plus.dart";

import "../../../core/services/font_service.dart";
import "../data/lesson_times.dart";
import "../domain/models.dart";

Future<void> showDayShareSheet(
  BuildContext context, {
  required DaySchedule day,
  required String college,
  required String shareText,
  String title = "Расписание",
  String? subtitle,
}) async {
  final theme = Theme.of(context);
  HapticFeedback.mediumImpact();
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          const SizedBox(height: 12),
          ListTile(
            leading:
                Icon(Icons.share_outlined, color: theme.colorScheme.primary),
            title: const Text("Поделиться"),
            onTap: () async {
              Navigator.pop(ctx);
              await SharePlus.instance.share(ShareParams(text: shareText));
            },
          ),
          ListTile(
            leading:
                Icon(Icons.copy_outlined, color: theme.colorScheme.primary),
            title: const Text("Скопировать"),
            onTap: () async {
              Navigator.pop(ctx);
              await Clipboard.setData(ClipboardData(text: shareText));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Скопировано"),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
          ListTile(
            leading:
                Icon(Icons.image_outlined, color: theme.colorScheme.primary),
            title: const Text("Поделиться изображением"),
            onTap: () async {
              Navigator.pop(ctx);
              await _shareDayAsImage(
                context,
                day: day,
                college: college,
                title: title,
                subtitle: subtitle,
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<void> _shareDayAsImage(
  BuildContext context, {
  required DaySchedule day,
  required String college,
  required String title,
  String? subtitle,
}) async {
  ui.Image? image;
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final fontService = FontService();
    await fontService.load();
    if (!context.mounted) return;
    image = await _renderDayImage(
      context,
      day: day,
      college: college,
      fontService: fontService,
      title: title,
      subtitle: subtitle,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    image = null;
    if (bytes == null) return;

    final appDir = await getApplicationDocumentsDirectory();
    final shareDir = Directory("${appDir.path}/share_images");
    if (!shareDir.existsSync()) shareDir.createSync(recursive: true);
    final fileName = "raspisanie_${day.date.replaceAll(".", "-")}.png";
    final shareFile = File("${shareDir.path}/$fileName");
    await shareFile.writeAsBytes(bytes.buffer.asUint8List(), flush: true);

    await Future.delayed(const Duration(milliseconds: 300));
    if (!context.mounted) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(shareFile.path, mimeType: "image/png", name: fileName)],
      ),
    );
  } catch (_) {
    if (!context.mounted || messenger == null) return;
    messenger.showSnackBar(
      const SnackBar(content: Text("Не удалось сформировать изображение")),
    );
  } finally {
    image?.dispose();
  }
}

Future<ui.Image> _renderDayImage(
  BuildContext context, {
  required DaySchedule day,
  required String college,
  required FontService fontService,
  required String title,
  String? subtitle,
}) async {
  final tf = fontService.textForCanvas;
  const width = 800.0;
  const horizontalPadding = 28.0;
  const topPadding = 24.0;
  const headerGap = 12.0;
  const tileGap = 8.0;
  const badgeSize = 32.0;
  const footerHeight = 24.0;
  const linePadding = 8.0;
  const subgroupChipPaddingH = 6.0;
  const subgroupChipPaddingV = 4.0;

  final theme = Theme.of(context);
  final sortedItems = day.items.toList()
    ..sort((a, b) {
      final byLesson = a.lessonNumber.compareTo(b.lessonNumber);
      if (byLesson != 0) return byLesson;
      return (a.subgroup ?? 0).compareTo(b.subgroup ?? 0);
    });

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

  final headerStyle =
      tf(fgPrimary, fontSize: 28, fontWeight: FontWeight.w700, height: 1.1);
  final subStyle =
      tf(fgSecondary, fontSize: 16, fontWeight: FontWeight.w500, height: 1.2);
  final titleStyle =
      tf(fgPrimary, fontSize: 17, fontWeight: FontWeight.w700, height: 1.15);
  final detailsStyle =
      tf(fgMuted, fontSize: 13, fontWeight: FontWeight.w500, height: 1.2);
  final subgroupChipStyle = tf(
    theme.colorScheme.primary,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  TextPainter tp(
    String text,
    TextStyle style,
    double maxWidth, {
    int? maxLines,
  }) {
    return TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : "...",
    )..layout(maxWidth: maxWidth, minWidth: 0);
  }

  final dateLabel = "${_capitalize(day.day)}, ${day.date}";
  final titlePainter = tp(title, headerStyle, width - horizontalPadding * 2);
  final datePainter = tp(dateLabel, subStyle, width - horizontalPadding * 2);
  final subtitlePainter = tp(
    (subtitle == null || subtitle.trim().isEmpty) ? " " : subtitle.trim(),
    subStyle.copyWith(fontSize: 14, color: fgMuted),
    width - horizontalPadding * 2,
    maxLines: 1,
  );

  final contentWidth = width - horizontalPadding * 2;
  final textAreaWidth = contentWidth - badgeSize - 16;
  final grouped = <int, List<ScheduleItem>>{};
  for (final item in sortedItems) {
    grouped.putIfAbsent(item.lessonNumber, () => []).add(item);
  }
  final lessonNumbers = grouped.keys.toList()..sort();

  double contentHeight = 0;
  final tileHeights = <double>[];
  for (final lessonNum in lessonNumbers) {
    final lessonItems = grouped[lessonNum]!;
    double tileH = linePadding;
    for (final item in lessonItems) {
      final time = LessonTimes.formatTime(item.lessonNumber, college: college);
      final itemTitle =
          item.subject?.trim().isNotEmpty == true ? item.subject!.trim() : "—";
      final detailsParts = <String>[
        if (time.isNotEmpty) time,
        if (item.classroom?.isNotEmpty == true) "Ауд. ${item.classroom}",
        if (item.teacher?.isNotEmpty == true) item.teacher!,
      ];
      final details = detailsParts.join("  ·  ");
      final titleLayout =
          tp(itemTitle, titleStyle, textAreaWidth - 50, maxLines: 2);
      final detailsP = details.isEmpty
          ? null
          : tp(details, detailsStyle, textAreaWidth - 50, maxLines: 1);
      final sg = item.subgroup;
      final chipP =
          sg == null ? null : tp("$sg п/г", subgroupChipStyle, 40, maxLines: 1);
      final lineContentH = titleLayout.height +
          (detailsP?.height ?? 0) +
          (detailsP != null ? 3 : 0);
      final chipH =
          chipP != null ? (chipP.height + subgroupChipPaddingV * 2) : 0.0;
      tileH += (lineContentH > chipH ? lineContentH : chipH) + linePadding;
    }
    final minTileH = badgeSize + 16;
    final safeTileH = tileH < minTileH ? minTileH : tileH;
    tileHeights.add(safeTileH);
    contentHeight += safeTileH + tileGap;
  }
  if (contentHeight > 0) contentHeight -= tileGap;
  if (lessonNumbers.isEmpty) contentHeight = 48.0;

  final headerHeight =
      titlePainter.height + 4 + datePainter.height + 2 + subtitlePainter.height;
  final height =
      topPadding + headerHeight + headerGap + contentHeight + footerHeight + 16;

  final dpr = MediaQuery.devicePixelRatioOf(context);
  final exportScale = (dpr * 1.35).clamp(2.5, 3.75);
  final outW = (width * exportScale).round();
  final outH = (height * exportScale).round();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
  );
  canvas.scale(exportScale);
  final primary = theme.colorScheme.primary;

  canvas.drawRect(
    Rect.fromLTWH(0, 0, width, height),
    Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(width, height),
        [blendDeep, baseA, blendSoft, baseB],
        const [0.0, 0.28, 0.68, 1.0],
      ),
  );
  canvas.drawCircle(
    Offset(width - 80, -30),
    180,
    Paint()..color = accent.withAlpha(30),
  );

  titlePainter.paint(canvas, Offset(horizontalPadding, topPadding));
  datePainter.paint(
    canvas,
    Offset(horizontalPadding, topPadding + titlePainter.height + 4),
  );
  subtitlePainter.paint(
    canvas,
    Offset(
      horizontalPadding,
      topPadding + titlePainter.height + datePainter.height + 6,
    ),
  );

  final totalLessons = lessonNumbers.length;
  final countChip = tp(
    "$totalLessons ${_lessonsWord(totalLessons)}",
    subStyle.copyWith(fontSize: 12, color: fgPrimary),
    140,
    maxLines: 1,
  );
  final chipW = countChip.width + 16;
  const chipH = 26.0;
  final chipX = width - horizontalPadding - chipW;
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(chipX, topPadding + 2, chipW, chipH),
      const Radius.circular(10),
    ),
    Paint()..color = (isDark ? Colors.white : Colors.black).withAlpha(22),
  );
  countChip.paint(
    canvas,
    Offset(chipX + 8, topPadding + 2 + (chipH - countChip.height) / 2),
  );

  var y = topPadding + headerHeight + headerGap;
  final rowBgPaint = Paint()
    ..color =
        (isDark ? Colors.white : Colors.black).withAlpha(isDark ? 24 : 12);
  final badgePaint = Paint()..color = primary.withAlpha(220);
  final badgeTextStyle = tf(
    theme.colorScheme.onPrimary,
    fontSize: 14,
    fontWeight: FontWeight.w700,
  );

  if (lessonNumbers.isEmpty) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(horizontalPadding, y, contentWidth, 48),
      const Radius.circular(14),
    );
    canvas.drawRRect(rect, rowBgPaint);
    final emptyP =
        tp("Нет занятий", titleStyle, contentWidth - 20, maxLines: 1);
    emptyP.paint(
      canvas,
      Offset(horizontalPadding + 12, y + (48 - emptyP.height) / 2),
    );
  } else {
    for (var ti = 0; ti < lessonNumbers.length; ti++) {
      final lessonNum = lessonNumbers[ti];
      final lessonItems = grouped[lessonNum]!;
      final tileH = tileHeights[ti];

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(horizontalPadding, y, contentWidth, tileH),
        const Radius.circular(14),
      );
      canvas.drawRRect(rect, rowBgPaint);

      const badgeX = horizontalPadding + 8;
      final badgeY = y + (tileH - badgeSize) / 2;
      canvas.drawCircle(
        Offset(badgeX + badgeSize / 2, badgeY + badgeSize / 2),
        badgeSize / 2,
        badgePaint,
      );
      final badgeText = tp("$lessonNum", badgeTextStyle, badgeSize);
      badgeText.paint(
        canvas,
        Offset(
          badgeX + (badgeSize - badgeText.width) / 2,
          badgeY + (badgeSize - badgeText.height) / 2,
        ),
      );

      final textX = badgeX + badgeSize + 8;
      var lineY = y + linePadding;
      for (final item in lessonItems) {
        final time =
            LessonTimes.formatTime(item.lessonNumber, college: college);
        final itemTitle = item.subject?.trim().isNotEmpty == true
            ? item.subject!.trim()
            : "—";
        final detailsParts = <String>[
          if (time.isNotEmpty) time,
          if (item.classroom?.isNotEmpty == true) "Ауд. ${item.classroom}",
          if (item.teacher?.isNotEmpty == true) item.teacher!,
        ];
        final details = detailsParts.join("  ·  ");
        final sg = item.subgroup;
        final chipP = sg == null
            ? null
            : tp("$sg п/г", subgroupChipStyle, 40, maxLines: 1);
        final chipW =
            chipP != null ? (chipP.width + subgroupChipPaddingH * 2) : 0.0;
        final chipH =
            chipP != null ? (chipP.height + subgroupChipPaddingV * 2) : 0.0;
        final titleAreaW = textAreaWidth - chipW - 4;
        final titleP = tp(itemTitle, titleStyle, titleAreaW, maxLines: 2);
        final detailsP = details.isEmpty
            ? null
            : tp(details, detailsStyle, titleAreaW, maxLines: 1);
        final lineContentH =
            titleP.height + (detailsP != null ? 3 + detailsP.height : 0);
        titleP.paint(canvas, Offset(textX, lineY));
        if (detailsP != null) {
          detailsP.paint(canvas, Offset(textX, lineY + titleP.height + 3));
        }
        if (chipP != null) {
          final cx = horizontalPadding + contentWidth - 8 - chipW;
          final cy = lineY + (lineContentH - chipH) / 2;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(cx, cy, chipW, chipH),
              const Radius.circular(6),
            ),
            Paint()..color = theme.colorScheme.primary.withAlpha(25),
          );
          chipP.paint(
            canvas,
            Offset(
              cx + (chipW - chipP.width) / 2,
              cy + (chipH - chipP.height) / 2,
            ),
          );
        }
        lineY += (lineContentH > chipH ? lineContentH : chipH) + linePadding;
      }
      y += tileH + tileGap;
    }
  }

  final footerPainter = tp(
    "Raspisanie",
    tf(fgMuted.withAlpha(190), fontSize: 12, fontWeight: FontWeight.w500),
    width - horizontalPadding * 2,
  );
  footerPainter.paint(
      canvas, Offset(horizontalPadding, height - footerHeight - 8));

  return recorder.endRecording().toImage(outW, outH);
}

String _capitalize(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

String _lessonsWord(int n) {
  if (n % 10 == 1 && n % 100 != 11) return "пара";
  if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) {
    return "пары";
  }
  return "пар";
}
