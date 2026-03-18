import "dart:io";

import "package:flutter/foundation.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:workmanager/workmanager.dart";

import "../../features/schedule/data/preferences_manager.dart";
import "../update/github_update_service.dart";
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
    final release = await getLatestGitHubRelease();
    if (release == null) return true;
    final info = await PackageInfo.fromPlatform();
    if (compareVersions(info.version, release.version) >= 0) return true;
    await sp.setString("pending_app_update_ver", release.version);
    await sp.setString("pending_app_update_apk", release.apkUrl);
    await sp.setString("pending_app_update_notes", release.releaseNotes);
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint("Background app update check: $e");
      debugPrintStack(stackTrace: st);
    }
  }
  return true;
}
