import "package:firebase_core/firebase_core.dart";
import "package:firebase_crashlytics/firebase_crashlytics.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/material.dart";
import "package:flutter/foundation.dart";
import "package:flutter_native_splash/flutter_native_splash.dart";
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
import "core/background/widget_refresh_task.dart";
import "package:home_widget/home_widget.dart" show HomeWidget;
import "package:workmanager/workmanager.dart";
import "firebase_options.dart";

void main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // Держим нативный сплэш, пока SplashIntro не отрисует свой первый кадр —
  // иначе система анимированно убирает свою иконку и знак «выплывает» заново.
  FlutterNativeSplash.preserve(widgetsBinding: binding);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  if (ScheduleBackgroundWorker.supported) {
    await Workmanager().initialize(
      callbackDispatcher,
    );
  }
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    if (kReleaseMode) {
      FlutterError.onError = (details) {
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      };
      WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    } else {
      // Debug: даём SDK создать session-директорию (setCustomKey ставится в очередь
      // Crashlytics-executor ПОСЛЕ openSession, поэтому await гарантирует что
      // директория уже существует к моменту когда Firebase Analytics вызовет log()).
      // Без этого Analytics вызывает log() в гонке с созданием директории → ENOENT.
      await FirebaseCrashlytics.instance.setCustomKey('build_type', 'debug');
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
      FlutterError.onError = FlutterError.presentError;
    }
  } catch (_) {}
  await initializeDateFormatting("ru_RU", null);
  final prefs = await SharedPreferences.getInstance();
  final fontService = FontService();
  await fontService.load();

  try {
    await NotificationService.instance
        .init()
        .timeout(const Duration(seconds: 5));
    await NotificationService.instance
        .restoreIfNeeded()
        .timeout(const Duration(seconds: 3));
  } catch (e) {
    debugPrint("NotificationService startup error: $e");
  }

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
  // app_open логируется Firebase автоматически — ручной вызов не нужен.

  await ScheduleBackgroundWorker.ensureRegisteredIfNeeded(prefs: pm);
  await AppUpdateBackgroundWorker.ensureRegistered(prefs: pm);

  try {
    await initFirebaseMessaging();
  } catch (_) {}

  runApp(RaspiFlutterApp(prefs: prefs, fontService: fontService));

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    // Запрашиваем разрешение после runApp — Activity гарантированно готова.
    // Если разрешение только что выдано — перепланируем уведомления,
    // потому что restoreIfNeeded() выше пропустил их (permission был denied).
    // try-catch: исключения из async postFrameCallback уходят в
    // platformDispatcher.onError → Crashlytics как fatal, что вводит в заблуждение.
    try {
      final newlyGranted =
          await NotificationService.instance.requestPermissionsOnStartup();
      if (newlyGranted) {
        await NotificationService.instance.restoreIfNeeded();
      }
    } catch (e) {
      debugPrint("Notification startup (postFrame) error: $e");
    }
    await HomeWidgetService.init();
    // Кнопка «Обновить» на домашнем виджете поднимает фоновый изолят и
    // вызывает этот колбэк — без регистрации тап просто ничего не делает.
    try {
      await HomeWidget.registerInteractivityCallback(
        homeWidgetInteractivityCallback,
      );
    } catch (e) {
      debugPrint("Widget interactivity callback registration failed: $e");
    }
    StorageCleanup.runPeriodicCleanup(prefs);
  });
}
