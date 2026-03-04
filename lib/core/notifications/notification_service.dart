import "dart:io";

import "package:flutter_local_notifications/flutter_local_notifications.dart";
import "package:timezone/timezone.dart" as tz;
import "package:timezone/data/latest_all.dart" as tz_data;

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channelLessons = "lesson_reminders";
  static const _channelChanges = "schedule_changes";
  static const _groupLessons = "lesson_reminders_group";

  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation("Europe/Moscow"));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

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
      await androidPlugin?.requestExactAlarmsPermission();
    }
  }

  /// Формат в стиле Telegram: короткий заголовок, тело "предмет · время" (одна строка).
  static String _formatReminderTitle(int offsetMinutes) =>
      "Пара через $offsetMinutes мин";
  static String _formatReminderBody(String subject, String time) {
    const maxSubject = 48;
    final s = subject.length > maxSubject
        ? "${subject.substring(0, maxSubject)}…"
        : subject;
    return "$s · $time";
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

    final tzDate = tz.TZDateTime.from(notifyAt, tz.local);
    final android = AndroidNotificationDetails(
      _channelLessons,
      "Пары",
      channelDescription: "Напоминания перед началом пары",
      importance: Importance.high,
      priority: Priority.high,
      icon: "@mipmap/ic_launcher",
      groupKey: _groupLessons,
    );
    const ios = DarwinNotificationDetails();
    final details = NotificationDetails(android: android, iOS: ios);

    await _plugin.zonedSchedule(
      id: id,
      title: _formatReminderTitle(offsetMinutes),
      body: _formatReminderBody(subject, time),
      scheduledDate: tzDate,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> cancelAll() async {
    if (!_initialized) await init();
    await _plugin.cancelAll();
  }

  Future<void> showTestNotification() async {
    if (!_initialized) await init();

    const android = AndroidNotificationDetails(
      _channelLessons,
      "Пары",
      channelDescription: "Напоминания перед началом пары",
      importance: Importance.high,
      priority: Priority.high,
      icon: "@mipmap/ic_launcher",
    );
    const ios = DarwinNotificationDetails();
    const details = NotificationDetails(android: android, iOS: ios);

    await _plugin.show(
      id: 9999,
      title: "Уведомления включены",
      body: "Напоминания о парах будут приходить в фоне",
      notificationDetails: details,
    );
  }

  /// Как в Telegram: короткий заголовок, тело с сутью (группа/контекст).
  Future<void> showScheduleChanged({required String groupName}) async {
    if (!_initialized) await init();

    const android = AndroidNotificationDetails(
      _channelChanges,
      "Расписание",
      channelDescription: "Уведомления об изменении расписания",
      importance: Importance.high,
      priority: Priority.high,
      icon: "@mipmap/ic_launcher",
    );
    const ios = DarwinNotificationDetails();
    const details = NotificationDetails(android: android, iOS: ios);

    await _plugin.show(
      id: 8888,
      title: "Расписание обновлено",
      body: groupName.isNotEmpty ? groupName : "Данные изменены",
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
