import "dart:io";

import "package:firebase_core/firebase_core.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter_local_notifications/flutter_local_notifications.dart";

/// Обработчик FCM в фоне (терминальное состояние). Должен быть top-level.
@pragma("vm:entry-point")
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

const AndroidNotificationChannel _fcmChannel = AndroidNotificationChannel(
  "fcm_messages",
  "Push-уведомления",
  description: "Входящие push-уведомления",
  importance: Importance.high,
  playSound: true,
  enableVibration: true,
);

/// Инициализация Firebase Messaging: права, канал, обработчики и токен.
Future<void> initFirebaseMessaging() async {
  final messaging = FirebaseMessaging.instance;
  if (Platform.isIOS) {
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }
  if (Platform.isAndroid) {
    final plugin = FlutterLocalNotificationsPlugin();
    final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.createNotificationChannel(_fcmChannel);
    }
  }
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );
  await messaging.getToken();
}
