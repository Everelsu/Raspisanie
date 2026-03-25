// ignore_for_file: avoid_print
/// Generates Android monochrome adaptive icon layer:
/// assets/icon/app_icon_monochrome.png (1024x1024, transparent background).
library;

import 'dart:io';

import 'package:image/image.dart' as img;

img.ColorUint8 _rgba(int r, int g, int b, int a) => img.ColorUint8.rgba(r, g, b, a);

void main() {
  const size = 1024;
  const white = 0xFFFFFFFF;

  final image = img.Image(width: size, height: size, numChannels: 4);

  // Fully transparent background.
  img.fill(image, color: _rgba(0, 0, 0, 0));

  final cx = size ~/ 2;
  final cy = size ~/ 2;

  // Draw only calendar glyph (white), no circular background.
  final calW = size * 0.5;
  final calH = size * 0.42;
  final left = (cx - calW / 2).round();
  final top = (cy - calH / 2).round();
  final w = calW.round();
  final h = calH.round();
  final barH = (calH * 0.22).round();
  final whiteColor = _rgba(
    (white >> 16) & 0xFF,
    (white >> 8) & 0xFF,
    white & 0xFF,
    255,
  );

  // Top bar.
  img.fillRect(image, x1: left, y1: top, x2: left + w, y2: top + barH, color: whiteColor);

  // Body.
  img.fillRect(
    image,
    x1: left,
    y1: top + barH,
    x2: left + w,
    y2: top + h,
    color: whiteColor,
  );

  // Punch transparent holes in 4x3 grid to keep calendar feel.
  final dotR = (size * 0.022).round().clamp(2, 20);
  final padX = calW * 0.18;
  final padY = (calH - barH) * 0.18;
  final bodyW = calW;
  final bodyH = calH - barH;
  final bodyTop = top + barH;

  for (int row = 0; row < 3; row++) {
    for (int col = 0; col < 4; col++) {
      final px = left + padX + (col + 0.5) * (bodyW - 2 * padX) / 4;
      final py = bodyTop + padY + (row + 0.5) * (bodyH - 2 * padY) / 3;
      img.fillCircle(
        image,
        x: px.round(),
        y: py.round(),
        radius: dotR,
        color: _rgba(0, 0, 0, 0),
      );
    }
  }

  final path = 'assets/icon/app_icon_monochrome.png';
  File(path).parent.createSync(recursive: true);
  File(path).writeAsBytesSync(img.encodePng(image));
  print('Saved $path (${size}x$size)');
}
