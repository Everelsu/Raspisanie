import "dart:io";

import "package:flutter_local_notifications/flutter_local_notifications.dart";

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings("@mipmap/ic_launcher");
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(android: android, iOS: ios);
    await _plugin.initialize(settings: settings);
    _initialized = true;

    if (Platform.isAndroid) {
      final androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    }
  }

  Future<void> scheduleLessonReminder({
    required int id,
    required String subject,
    required String time,
    required DateTime scheduledDate,
    required int offsetMinutes,
  }) async {
    if (!_initialized) await init();

    final notifyAt = scheduledDate.subtract(Duration(minutes: offsetMinutes));
    if (notifyAt.isBefore(DateTime.now())) return;

    final delay = notifyAt.difference(DateTime.now());

    Future.delayed(delay, () async {
      const android = AndroidNotificationDetails(
        "lesson_reminders",
        "Напоминания о парах",
        channelDescription: "Уведомления перед началом пар",
        importance: Importance.high,
        priority: Priority.high,
        icon: "@mipmap/ic_launcher",
      );
      const ios = DarwinNotificationDetails();
      const details = NotificationDetails(android: android, iOS: ios);

      await _plugin.show(
        id: id,
        title: "Через $offsetMinutes мин — $subject",
        body: "Начало в $time",
        notificationDetails: details,
      );
    });
  }

  Future<void> cancelAll() async {
    if (!_initialized) await init();
    await _plugin.cancelAll();
  }

  Future<void> showTestNotification() async {
    if (!_initialized) await init();

    const android = AndroidNotificationDetails(
      "lesson_reminders",
      "Напоминания о парах",
      channelDescription: "Уведомления перед началом пар",
      importance: Importance.high,
      priority: Priority.high,
      icon: "@mipmap/ic_launcher",
    );
    const ios = DarwinNotificationDetails();
    const details = NotificationDetails(android: android, iOS: ios);

    await _plugin.show(
      id: 9999,
      title: "Тестовое уведомление",
      body: "Уведомления работают!",
      notificationDetails: details,
    );
  }

  Future<void> showScheduleChanged({required String groupName}) async {
    if (!_initialized) await init();

    const android = AndroidNotificationDetails(
      "schedule_changes",
      "Изменения расписания",
      channelDescription: "Уведомления об изменениях в расписании",
      importance: Importance.high,
      priority: Priority.high,
      icon: "@mipmap/ic_launcher",
    );
    const ios = DarwinNotificationDetails();
    const details = NotificationDetails(android: android, iOS: ios);

    await _plugin.show(
      id: 8888,
      title: "Расписание изменилось",
      body: groupName.isNotEmpty
          ? "Обновлено расписание для $groupName"
          : "Расписание было обновлено",
      notificationDetails: details,
    );
  }

  Future<void> showNoLessonsToday({required String groupName}) async {
    if (!_initialized) await init();
    const android = AndroidNotificationDetails(
      "lesson_reminders",
      "Напоминания о парах",
      channelDescription: "Уведомления перед началом пар",
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: "@mipmap/ic_launcher",
    );
    const ios = DarwinNotificationDetails();
    const details = NotificationDetails(android: android, iOS: ios);
    await _plugin.show(
      id: 7777,
      title: "Сегодня нет пар",
      body: groupName.isNotEmpty
          ? "Для $groupName сегодня занятий нет"
          : "Сегодня занятий нет",
      notificationDetails: details,
    );
  }

  Future<void> scheduleForDay({
    required List<({int number, String subject, String startTime})> lessons,
    required DateTime date,
    required int offsetMinutes,
  }) async {
    await cancelAll();
    for (final lesson in lessons) {
      final timeParts = lesson.startTime.split(":");
      if (timeParts.length != 2) continue;
      final hour = int.tryParse(timeParts[0]) ?? 0;
      final minute = int.tryParse(timeParts[1]) ?? 0;
      final scheduledDate =
          DateTime(date.year, date.month, date.day, hour, minute);

      await scheduleLessonReminder(
        id: lesson.number,
        subject: lesson.subject,
        time: lesson.startTime,
        scheduledDate: scheduledDate,
        offsetMinutes: offsetMinutes,
      );
    }
  }
}
