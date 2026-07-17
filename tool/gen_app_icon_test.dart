// Generates assets/icon/app_icon.png (1024x1024) from the Union logo path.
// Run: flutter test tool/gen_app_icon_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generate app_icon.png', () async {
    const size = 1024.0;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    // Background — dark, matches the launcher/adaptive icon background.
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, size, size),
      ui.Paint()..color = const ui.Color(0xFF171717),
    );

    // Union mark: source viewBox 615x431. Fit into the safe area
    // (flutter_launcher_icons uses this PNG as the adaptive foreground too,
    // so keep the mark within ~52% of the canvas).
    const srcW = 615.0;
    const srcH = 431.0;
    const targetW = size * 0.62;
    const scale = targetW / srcW;
    const targetH = srcH * scale;

    canvas.save();
    canvas.translate((size - targetW) / 2, (size - targetH) / 2);
    canvas.scale(scale, scale);
    canvas.drawPath(_logoPath(), ui.Paint()..color = const ui.Color(0xFFF2F2F2));
    canvas.restore();

    final image =
        await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    final file = File('assets/icon/app_icon.png');
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
    expect(file.existsSync(), isTrue);
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
