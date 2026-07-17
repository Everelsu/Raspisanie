import 'dart:io';

import 'package:flutter/services.dart';

/// Switches the launcher icon between the per-theme activity-aliases
/// declared in AndroidManifest.xml.
class AppIconService {
  static const _channel = MethodChannel('com.example.raspiflutter/app_icon');

  static const themedIcons = [
    'dark',
    'light',
    'green',
    'pink',
    'blue',
    'gray',
    'purple',
    'orange',
    'red',
    'teal',
  ];

  /// Enables the alias for [themeKey], disables the rest.
  /// No-op on non-Android platforms and unknown keys.
  static Future<void> setIcon(String themeKey) async {
    if (!Platform.isAndroid) return;
    if (!themedIcons.contains(themeKey)) return;
    try {
      await _channel.invokeMethod('setIcon', themeKey);
    } on PlatformException {
      // Переключение иконки некритично — молча оставляем текущую.
    }
  }
}
