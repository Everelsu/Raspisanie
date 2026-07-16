import "dart:io";

import "package:flutter/foundation.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:workmanager/workmanager.dart";

import "../../features/schedule/data/preferences_manager.dart";
import "../update/update_manifest.dart";
import "../update/version_utils.dart";

class AppUpdateBackgroundWorker {
  static const String taskName = "app_update_check";
  static const String uniqueName = "app_update_check_unique";

  static bool get supported => !kIsWeb && Platform.isAndroid;

  static Future<void> ensureRegistered({
    required PreferencesManager prefs,
  }) async {
    if (!supported) return;
    if (!prefs.autoCheckAppUpdate) {
      await Workmanager().cancelByUniqueName(uniqueName);
      return;
    }
    await Workmanager().registerPeriodicTask(
      uniqueName,
      taskName,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(networkType: NetworkType.connected),
      frequency: const Duration(hours: 24),
    );
  }
}

/// Вызывается из [callbackDispatcher] в isolate.
Future<bool> runAppUpdateBackgroundTask() async {
  final sp = await SharedPreferences.getInstance();
  final pm = PreferencesManager(sp);
  if (!pm.autoCheckAppUpdate) return true;
  try {
    final manifest = await fetchUpdateManifest();
    if (manifest == null) return true;
    final info = await PackageInfo.fromPlatform();
    if (compareVersions(info.version, manifest.version) >= 0) return true;
    // Полное состояние обновления пересоберёт AppUpdateController при
    // следующем открытии приложения — здесь только помечаем находку.
    await sp.setString("pending_app_update_ver", manifest.version);
    await sp.setString("pending_app_update_apk", manifest.apkUrl);
    await sp.setString("pending_app_update_notes", manifest.notes);
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint("Background app update check: $e");
      debugPrintStack(stackTrace: st);
    }
  }
  return true;
}
