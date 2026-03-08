import "package:firebase_core/firebase_core.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/material.dart";
import "package:intl/date_symbol_data_local.dart";
import "package:shared_preferences/shared_preferences.dart";

import "app/app.dart";
import "core/notifications/notification_service.dart";
import "core/messaging/firebase_messaging_service.dart";
import "core/services/font_service.dart";
import "core/storage/storage_cleanup.dart";
import "core/widgets/home_widget_service.dart";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  await initializeDateFormatting("ru_RU", null);
  final prefs = await SharedPreferences.getInstance();
  final fontService = FontService();
  await fontService.load();

  await NotificationService.instance.init();
  await NotificationService.instance.restoreIfNeeded();

  try {
    await initFirebaseMessaging();
  } catch (_) {}

  runApp(RaspiFlutterApp(prefs: prefs, fontService: fontService));

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await HomeWidgetService.init();
    StorageCleanup.runPeriodicCleanup(prefs);
  });
}
