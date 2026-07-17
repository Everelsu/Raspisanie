// Generates per-theme legacy launcher PNGs (API <26) and the splash mark.
// Run: flutter test tool/gen_theme_icons_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const _themes = <String, (int bg, int fg)>{
  'dark': (0xFF171717, 0xFFF2F2F2),
  'light': (0xFFF2F2F7, 0xFF111111),
  'green': (0xFF0C1A0C, 0xFF34C759),
  'pink': (0xFF140A10, 0xFFFF6B9D),
  'blue': (0xFF0A1620, 0xFF5AC8FA),
  'gray': (0xFF18181A, 0xFFA0A0A8),
  'purple': (0xFF120D1F, 0xFFB388FF),
  'orange': (0xFF211307, 0xFFFF9F1C),
  'red': (0xFF1A0A0A, 0xFFFF453A),
  'teal': (0xFF1A1807, 0xFFE8E37A),
};

Future<void> _writePng({
  required String path,
  required double size,
  int? bg,
  required int fg,
  required double markFraction,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  if (bg != null) {
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, size, size),
      ui.Paint()..color = ui.Color(bg),
    );
  }
  const srcW = 615.0;
  const srcH = 431.0;
  final targetW = size * markFraction;
  final scale = targetW / srcW;
  final targetH = srcH * scale;
  canvas.save();
  canvas.translate((size - targetW) / 2, (size - targetH) / 2);
  canvas.scale(scale, scale);
  canvas.drawPath(_logoPath(), ui.Paint()..color = ui.Color(fg));
  canvas.restore();

  final image =
      await recorder.endRecording().toImage(size.toInt(), size.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  test('generate theme icons and splash mark', () async {
    const res = 'android/app/src/main/res';
    for (final entry in _themes.entries) {
      await _writePng(
        path: '$res/mipmap-xxhdpi/ic_launcher_${entry.key}.png',
        size: 432,
        bg: entry.value.$1,
        fg: entry.value.$2,
        markFraction: 0.62,
      );
    }
    // Splash mark: logo only, transparent bg. Android 12 shows it inside a
    // 2/3-diameter circle, so keep the mark well within the center.
    await _writePng(
      path: 'assets/icon/splash_mark.png',
      size: 1152,
      fg: 0xFFF2F2F2,
      markFraction: 0.42,
    );
    // Тонированные знаки для per-theme сплэша (values-v31/splash_themes.xml):
    // системный сплэш игнорирует android:tint в bitmap-xml, нужны готовые PNG.
    // 864px = 288dp @xxhdpi — рекомендованный размер иконки сплэша A12+.
    for (final entry in _themes.entries) {
      await _writePng(
        path: '$res/drawable-xxhdpi/splash_mark_${entry.key}.png',
        size: 864,
        fg: entry.value.$2,
        markFraction: 0.42,
      );
    }
    expect(File('assets/icon/splash_mark.png').existsSync(), isTrue);
  });
}

ui.Path _logoPath() => ui.Path()
  ..moveTo(55, 0.300781)
  ..cubicTo(55.0429, 0.240718, 55.0858, 0.180066, 55.1289, 0.120117)
  ..lineTo(307.613, 181.841)
  ..lineTo(560, 0.191406)
  ..lineTo(560, 0)
  ..lineTo(615, 0)
  ..lineTo(615, 431)
  ..lineTo(560.331, 431)
  ..cubicTo(560.254, 431.109, 560.177, 431.218, 560.099, 431.326)
  ..lineTo(307.613, 249.605)
  ..lineTo(55.1289, 431.326)
  ..cubicTo(55.0509, 431.218, 54.9736, 431.109, 54.8965, 431)
  ..lineTo(0, 431)
  ..lineTo(0, 0)
  ..lineTo(55, 0)
  ..close()
  ..moveTo(55, 367.223)
  ..cubicTo(58.4014, 362.461, 62.6267, 358.166, 67.6396, 354.558)
  ..lineTo(260.537, 215.723)
  ..lineTo(67.6396, 76.8896)
  ..cubicTo(62.6264, 73.2815, 58.4015, 68.9853, 55, 64.2236)
  ..close()
  ..moveTo(560, 64.5381)
  ..cubicTo(556.638, 69.1742, 552.49, 73.3612, 547.588, 76.8896)
  ..lineTo(354.689, 215.723)
  ..lineTo(547.588, 354.558)
  ..cubicTo(552.49, 358.086, 556.638, 362.272, 560, 366.908)
  ..close();
