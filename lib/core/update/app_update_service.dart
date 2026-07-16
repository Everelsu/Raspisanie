import "dart:io";

import "package:flutter/foundation.dart";
import "package:flutter/services.dart";

const MethodChannel _channel = MethodChannel("com.example.raspiflutter/install_apk");

/// Запускает установку APK по пути. Только Android.
/// Файл не удаляем сразу — установщик читает его асинхронно; кэш почистится при необходимости.
Future<bool> installApk(String filePath) async {
  if (!Platform.isAndroid) return false;
  try {
    await _channel.invokeMethod<void>("install", {"path": filePath});
    return true;
  } on PlatformException catch (e) {
    if (kDebugMode) debugPrint("Install APK error: ${e.message}");
    return false;
  }
}
