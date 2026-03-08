// ignore_for_file: avoid_print
/// Генерирует assets/icon/app_icon.png (1024x1024) из кода.
/// Запуск из корня проекта: dart run tool/draw_app_icon.dart
library;


import 'dart:io';

import 'package:image/image.dart' as img;

img.ColorUint8 _color(int hex) => img.ColorUint8.rgba(
      (hex >> 16) & 0xFF,
      (hex >> 8) & 0xFF,
      hex & 0xFF,
      255,
    );

void main() {
  const size = 1024;
  const bgColor = 0xFF7EB5D8; // светлый голубой
  const fgColor = 0xFF1C1C1E; // тёмный (календарь)
  const white = 0xFFFFFFFF;

  final image = img.Image(width: size, height: size);

  final cx = size ~/ 2;
  final cy = size ~/ 2;
  final radius = size ~/ 2;

  // Круг фона
  img.fillCircle(image, x: cx, y: cy, radius: radius, color: _color(bgColor));

  // Календарь по центру
  final calW = size * 0.5;
  final calH = size * 0.42;
  final left = (cx - calW / 2).round();
  final top = (cy - calH / 2).round();
  final w = calW.round();
  final h = calH.round();
  final barH = (calH * 0.22).round();

  // Верхняя плашка
  img.fillRect(image, x1: left, y1: top, x2: left + w, y2: top + barH, color: _color(fgColor));

  // Тело календаря
  img.fillRect(
    image,
    x1: left,
    y1: top + barH,
    x2: left + w,
    y2: top + h,
    color: _color(white),
  );

  // 12 точек 4x3
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
      img.fillCircle(image, x: px.round(), y: py.round(), radius: dotR, color: _color(fgColor));
    }
  }

  final path = 'assets/icon/app_icon.png';
  File(path).parent.createSync(recursive: true);
  File(path).writeAsBytesSync(img.encodePng(image));
  print('Saved $path (${size}x$size)');
}
