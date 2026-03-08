import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Рисует иконку приложения (как в bottom_bar_sheet: круг + календарь с точками).
/// Используется для экспорта PNG высокого разрешения.
class AppIconPainter extends CustomPainter {
  AppIconPainter({
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final Color backgroundColor;
  final Color foregroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;

    // Круг фона (светло-голубой)
    canvas.drawCircle(center, radius, Paint()..color = backgroundColor);

    // Календарь по центру (масштаб под размер)
    final calW = size.width * 0.5;
    final calH = size.height * 0.42;
    final left = center.dx - calW / 2;
    final top = center.dy - calH / 2;

    // Верхняя плашка (полоска месяца)
    final barH = calH * 0.22;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, calW, barH),
        const Radius.circular(4),
      ),
      Paint()..color = foregroundColor,
    );

    // Тело календаря (светлое)
    final bodyTop = top + barH;
    final bodyH = calH - barH;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, bodyTop, calW, bodyH),
        const Radius.circular(4),
      ),
      Paint()..color = Colors.white,
    );

    // 12 точек сетка 4x3
    final dotR = size.width * 0.022;
    final padX = calW * 0.18;
    final padY = bodyH * 0.18;
    final cellW = (calW - 2 * padX) / 3;
    final cellH = (bodyH - 2 * padY) / 2;
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 4; col++) {
        final cx = left + padX + (col + 0.5) * (calW - 2 * padX) / 4;
        final cy = bodyTop + padY + (row + 0.5) * (bodyH - 2 * padY) / 3;
        canvas.drawCircle(
          Offset(cx, cy),
          dotR,
          Paint()..color = foregroundColor,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Виджет иконки для экспорта (круг обрезается через decoration).
class AppIconWidget extends StatelessWidget {
  const AppIconWidget({
    super.key,
    this.size = 256,
    this.backgroundColor = const Color(0xFF7EB5D8),
    this.foregroundColor = const Color(0xFF1C1C1E),
  });

  final double size;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: CustomPaint(
          size: Size(size, size),
          painter: AppIconPainter(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
          ),
        ),
      ),
    );
  }
}

/// Точка входа: запустить приложение, отрендерить иконку и сохранить в assets/icon/app_icon.png.
/// Запуск: flutter run -t lib/app_icon_painter.dart
void main() {
  runApp(const _IconExporterApp());
}

class _IconExporterApp extends StatefulWidget {
  const _IconExporterApp();

  @override
  State<_IconExporterApp> createState() => _IconExporterAppState();
}

class _IconExporterAppState extends State<_IconExporterApp> {
  final GlobalKey _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _captureAndSave());
  }

  Future<void> _captureAndSave() async {
    final boundary = _key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    // 1024 = 256 * 4
    final image = await boundary.toImage(pixelRatio: 4);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    final pngBytes = byteData.buffer.asUint8List();
    final path = 'assets/icon/app_icon.png';
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(pngBytes);
    debugPrint('Saved $path (${pngBytes.length} bytes, 1024x1024)');
    if (mounted) {
      setState(() => _saved = true);
    }
  }

  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.grey[200],
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RepaintBoundary(
                key: _key,
                child: const AppIconWidget(size: 256),
              ),
              const SizedBox(height: 24),
              Text(
                _saved ? 'Иконка сохранена в assets/icon/app_icon.png' : 'Рендер...',
                style: TextStyle(color: Colors.grey[800], fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
