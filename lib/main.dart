import "package:firebase_core/firebase_core.dart";
import "package:firebase_crashlytics/firebase_crashlytics.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/material.dart";
import "package:flutter/foundation.dart";
import "package:intl/date_symbol_data_local.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:shared_preferences/shared_preferences.dart";

import "app/app.dart";
import "core/messaging/firebase_messaging_service.dart";
import "core/notifications/notification_service.dart";
import "core/services/analytics_service.dart";
import "core/services/font_service.dart";
import "core/storage/storage_cleanup.dart";
import "core/widgets/home_widget_service.dart";
import "features/schedule/data/preferences_manager.dart";
import "core/background/app_update_background_worker.dart";
import "core/background/schedule_background_worker.dart";
import "package:workmanager/workmanager.dart";
import "firebase_options.dart";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  if (ScheduleBackgroundWorker.supported) {
    await Workmanager().initialize(
      callbackDispatcher,
    );
  }
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(kReleaseMode);
    FlutterError.onError = (details) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };
    WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (_) {}
  await initializeDateFormatting("ru_RU", null);
  final prefs = await SharedPreferences.getInstance();
  final fontService = FontService();
  await fontService.load();

  await NotificationService.instance.init();
  await NotificationService.instance.restoreIfNeeded();

  await AnalyticsService.instance.init();
  final pm = PreferencesManager(prefs);
  await AnalyticsService.instance.setEnabled(pm.analyticsEnabled);
  try {
    final info = await PackageInfo.fromPlatform();
    await AnalyticsService.instance.logAppStart(
      appVersion: info.version,
      platform: defaultTargetPlatform.name,
    );
  } catch (_) {}
  await AnalyticsService.instance.logAppOpen();

  await ScheduleBackgroundWorker.ensureRegisteredIfNeeded(prefs: pm);
  await AppUpdateBackgroundWorker.ensureRegistered(prefs: pm);

  try {
    await initFirebaseMessaging();
  } catch (_) {}

  runApp(RaspiFlutterApp(prefs: prefs, fontService: fontService));

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    // Запрашиваем разрешение после runApp — Activity гарантированно готова.
    await NotificationService.instance.requestPermissionsOnStartup();
    await HomeWidgetService.init();
    StorageCleanup.runPeriodicCleanup(prefs);
  });
}
