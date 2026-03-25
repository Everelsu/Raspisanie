// ignore_for_file: avoid_print

import "dart:convert";
import "dart:io";

import "package:flutter/foundation.dart";
import "package:flutter_local_notifications/flutter_local_notifications.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:timezone/data/latest_all.dart" as tz_data;
import "package:timezone/timezone.dart" as tz;

// ═══════════════════════════════════════════════════════════════════════════════
// MODEL
// ═══════════════════════════════════════════════════════════════════════════════

class Lesson {
  final int number;
  final String subject;
  final String startTime;
  /// Кабинет/аудитория.
  final String? classroom;
  /// Подгруппа (1, 2 и т.д.), если пара по подгруппам.
  final int? subgroup;
  /// Преподаватель — для режима «Студент».
  final String? teacher;
  /// Название группы — для режима «Преподаватель» (у кого пара).
  final String? groupName;

  const Lesson({
    required this.number,
    required this.subject,
    required this.startTime,
    this.classroom,
    this.subgroup,
    this.teacher,
    this.groupName,
  });

  /// Момент начала пары сегодня.
  DateTime get todayStartsAt {
    final now = DateTime.now();
    final parts = startTime.split(":");
    final h = int.tryParse(parts[0].trim()) ?? 0;
    final m = parts.length > 1 ? (int.tryParse(parts[1].trim()) ?? 0) : 0;
    return DateTime(now.year, now.month, now.day, h, m);
  }

  /// Уникальный id: (YYYYMMDD * 100) + number. Нет коллизий.
  int notificationId() {
    final d = DateTime.now();
    return (d.year * 10000 + d.month * 100 + d.day) * 100 + number;
  }

  Map<String, dynamic> toJson() => {
        "n": number,
        "s": subject,
        "t": startTime,
        if (classroom != null && classroom!.isNotEmpty) "c": classroom,
        if (subgroup != null) "g": subgroup,
        if (teacher != null && teacher!.isNotEmpty) "p": teacher,
        if (groupName != null && groupName!.isNotEmpty) "gr": groupName,
      };

  factory Lesson.fromJson(Map<String, dynamic> j) => Lesson(
        number: j["n"] as int,
        subject: j["s"] as String,
        startTime: j["t"] as String,
        classroom: j["c"] as String?,
        subgroup: j["g"] as int?,
        teacher: j["p"] as String?,
        groupName: j["gr"] as String?,
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Поставить true при нажатии на уведомление — HomePage переключится на вкладку «Расписание».
  static final ValueNotifier<bool> openScheduleOnTap = ValueNotifier(false);

  /// true, когда приложение на переднем плане. Не показываем «расписание изменилось», если пользователь уже в приложении.
  static bool appInForeground = true;

  static const _channel = "lesson_reminders";
  static const _channelChanges = "schedule_changes";

  /// Android: только `@drawable/…` с белым силуэтом на прозрачном фоне (не mipmap launcher).
  static const _androidSmallIcon = "@drawable/ic_stat_notify";

  static const _kEnabled = "ns_enabled";
  static const _kOffset = "ns_offset";
  static const _kLessons = "ns_lessons";

  // ─────────────────────────────────────────────────────────────────────────────
  // INIT
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;

    _initTimezone();

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings("@mipmap/ic_launcher"),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
          notificationCategories: [],
        ),
      ),
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    if (Platform.isAndroid) {
      final ap = _androidPlugin;
      await ap?.requestNotificationsPermission();
      await ap?.requestExactAlarmsPermission();
      await ap?.createNotificationChannel(const AndroidNotificationChannel(
        _channel,
        "Напоминания о парах",
        description: "За N минут до начала пары — предмет, время, аудитория",
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ));
      await ap?.createNotificationChannel(const AndroidNotificationChannel(
        _channelChanges,
        "Изменения расписания",
        description: "Когда данные расписания обновились",
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ));
    }

    _initialized = true;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ─────────────────────────────────────────────────────────────────────────────

  /// Запланировать уведомления на сегодня.
  ///
  /// Старые уведомления отменяются автоматически — можно вызывать
  /// повторно при любом изменении расписания.
  ///
  /// [lessons]       — список пар на сегодня.
  /// [offsetMinutes] — за сколько минут до начала пары уведомлять.
  /// [enabled]       — false: отменяет всё и ничего не планирует.
  Future<void> scheduleToday({
    required List<Lesson> lessons,
    required int offsetMinutes,
    required bool enabled,
  }) async {
    await _ensureInit();

    await _plugin.cancelAll();

    await _saveToPrefs(
      lessons: lessons,
      offsetMinutes: offsetMinutes,
      enabled: enabled,
    );

    if (!enabled) return;

    for (final lesson in lessons) {
      final notifyAt = lesson.todayStartsAt
          .subtract(Duration(minutes: offsetMinutes));
      final now = DateTime.now();

      if (!notifyAt.isAfter(now.add(const Duration(seconds: 30)))) continue;

      try {
        await _plugin.zonedSchedule(
          id: lesson.notificationId(),
          title: _title(lesson.number, offsetMinutes),
          body: _bodyShort(lesson),
          scheduledDate: tz.TZDateTime.from(notifyAt, tz.local),
          notificationDetails: _lessonDetails(lesson, offsetMinutes),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      } catch (_) {}
    }
  }

  /// Восстановить уведомления из кеша.
  ///
  /// Вызывать при каждом запуске приложения — на случай если
  /// уведомления были сброшены системой.
  Future<void> restoreIfNeeded() async {
    await _ensureInit();

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kEnabled) ?? false;
    if (!enabled) return;

    final raw = prefs.getString(_kLessons);
    if (raw == null) return;

    final offset = prefs.getInt(_kOffset) ?? 10;

    List<Lesson> lessons;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      lessons = list
          .map((e) => Lesson.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return;
    }

    await scheduleToday(
      lessons: lessons,
      offsetMinutes: offset,
      enabled: true,
    );
  }

  /// Отменить все уведомления.
  Future<void> cancelAll() async {
    await _ensureInit();
    await _plugin.cancelAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, false);
  }

  /// Уведомление о смене расписания.
  ///
  /// В **основном изоляте** не показывается, если [appInForeground] — пользователь
  /// уже в приложении. Фоновый Workmanager выполняется в **другом изоляте**, где
  /// [appInForeground] по умолчанию true, поэтому оттуда передавайте
  /// [fromBackgroundWorker]: true.
  Future<void> showScheduleChanged({
    required String groupName,
    bool fromBackgroundWorker = false,
  }) async {
    if (!fromBackgroundWorker && appInForeground) return;
    await _ensureInit();
    final title = "Расписание изменилось";
    final body = groupName.trim().isEmpty
        ? "Данные обновлены. Откройте приложение."
        : "Группа «$groupName» — проверьте расписание.";
    await _plugin.show(
      id: 99989,
      title: title,
      body: body,
      notificationDetails: _details(_channelChanges),
    );
  }

  // ─── Тесты ──────────────────────────────────────────────────────────────────

  Future<void> showTestNow() async {
    await _ensureInit();
    await _plugin.show(
      id: 99990,
      title: "Уведомления работают ✓",
      body: "Напоминания о парах будут приходить вовремя",
      notificationDetails: _details(_channel),
    );
  }

  Future<bool> scheduleTestIn1Min() async {
    await _ensureInit();
    final at = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 1));
    try {
      await _plugin.zonedSchedule(
        id: 99991,
        title: "Тест: таймер ✓",
        body: "Пришло через 1 мин — exact alarm работает",
        scheduledDate: at,
        notificationDetails: _details(_channel),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // PRIVATE
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> _saveToPrefs({
    required List<Lesson> lessons,
    required int offsetMinutes,
    required bool enabled,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, enabled);
    await prefs.setInt(_kOffset, offsetMinutes);
    await prefs.setString(
      _kLessons,
      jsonEncode(lessons.map((l) => l.toJson()).toList()),
    );
  }

  NotificationDetails _details(String channelId) => NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelId == _channelChanges ? "Изменения расписания" : "Напоминания о парах",
          channelDescription: "Уведомления",
          importance: Importance.max,
          priority: Priority.max,
          icon: _androidSmallIcon,
          playSound: true,
          enableVibration: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

  /// Оформление уведомления о паре: заголовок, краткий текст и развёрнутый (BigText).
  /// Структура: название · кабинет (погруппа) · препод / группа.
  NotificationDetails _lessonDetails(Lesson lesson, int offsetMinutes) {
    final title = _title(lesson.number, offsetMinutes);
    final big = _bodyBig(lesson);

    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channel,
        "Напоминания о парах",
        channelDescription: "За N минут до начала пары",
        importance: Importance.max,
        priority: Priority.high,
        icon: _androidSmallIcon,
        playSound: true,
        enableVibration: true,
        visibility: NotificationVisibility.public,
        styleInformation: BigTextStyleInformation(
          big,
          contentTitle: title,
          summaryText: "Начало в ${lesson.startTime}",
        ),
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        subtitle: "Начало в ${lesson.startTime}",
      ),
    );
  }

  static String _title(int lessonNumber, int offsetMinutes) =>
      "Пара $lessonNumber через $offsetMinutes мин";

  /// Одна строка: название · кабинет (погруппа) · препод/группа.
  static String _bodyShort(Lesson lesson) {
    const maxSubjectLen = 36;
    final subject = lesson.subject.length > maxSubjectLen
        ? "${lesson.subject.substring(0, maxSubjectLen)}…"
        : lesson.subject;
    final parts = <String>[subject];
    if (lesson.classroom != null && lesson.classroom!.trim().isNotEmpty) {
      parts.add(lesson.classroom!.trim());
    }
    if (lesson.subgroup != null) {
      parts.add("п/г ${lesson.subgroup}");
    }
    final last = lesson.teacher ?? lesson.groupName;
    if (last != null && last.trim().isNotEmpty) {
      parts.add(last.trim());
    }
    return parts.join(" · ");
  }

  /// Развёрнутый текст (BigText): название, кабинет, погруппа, препод/группа, время.
  static String _bodyBig(Lesson lesson) {
    final lines = <String>[lesson.subject];
    if (lesson.classroom != null && lesson.classroom!.trim().isNotEmpty) {
      lines.add("Кабинет: ${lesson.classroom!.trim()}");
    }
    if (lesson.subgroup != null) {
      lines.add("Подгруппа ${lesson.subgroup}");
    }
    if (lesson.teacher != null && lesson.teacher!.trim().isNotEmpty) {
      lines.add("Преподаватель: ${lesson.teacher!.trim()}");
    }
    if (lesson.groupName != null && lesson.groupName!.trim().isNotEmpty) {
      lines.add("Группа: ${lesson.groupName!.trim()}");
    }
    lines.add("Начало в ${lesson.startTime}");
    return lines.join("\n");
  }

  AndroidFlutterLocalNotificationsPlugin? get _androidPlugin =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  Future<void> _ensureInit() async {
    if (!_initialized) await init();
  }

  static void _onNotificationTapped(NotificationResponse response) {
    openScheduleOnTap.value = true;
  }

  static void _initTimezone() {
    tz_data.initializeTimeZones();
    final offset = DateTime.now().timeZoneOffset;
    final h = offset.inHours.clamp(-12, 14);
    try {
      tz.setLocalLocation(
          tz.getLocation("Etc/GMT${h <= 0 ? '+' : '-'}${h.abs()}"));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
  }
}
