// ignore_for_file: avoid_print

import "dart:convert";
import "dart:io";

import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
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

  /// Уникальный id в пределах дня. cancelAll() вызывается перед каждым
  /// планированием, поэтому дата в ID не нужна — достаточно number + subgroup.
  int notificationId() => number * 10 + (subgroup ?? 0);

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

  /// Защита от параллельных вызовов init(). Если инициализация уже идёт,
  /// повторные вызовы ждут её завершения — не запускают _doInit() заново.
  Future<void>? _initFuture;

  /// Поставить true при нажатии на уведомление — HomePage переключится на
  /// вкладку «Расписание».
  static final ValueNotifier<bool> openScheduleOnTap = ValueNotifier(false);

  /// true когда приложение на переднем плане. Уведомление «расписание
  /// изменилось» не показывается если пользователь уже в приложении.
  static bool appInForeground = true;

  static const _channel = "lesson_reminders";
  static const _channelChanges = "schedule_changes";

  /// Монохромная иконка для статус-бара. Должна быть в drawable, НЕ mipmap.
  static const _androidIcon = "@drawable/ic_stat_notify";

  static const _kEnabled = "ns_enabled";
  static const _kOffset = "ns_offset";
  static const _kLessons = "ns_lessons";

  // ─────────────────────────────────────────────────────────────────────────────
  // INIT
  // ─────────────────────────────────────────────────────────────────────────────

  /// Инициализировать сервис.
  ///
  /// Безопасно вызывать несколько раз подряд — повторные вызовы ждут
  /// первый и ничего не делают. Параллельные вызовы сливаются в один
  /// _doInit() и не дублируют инициализацию плагина.
  Future<void> init() async {
    if (_initialized) return;
    _initFuture ??= _doInit();
    try {
      await _initFuture;
    } catch (_) {
      _initFuture = null; // следующий вызов может повторить попытку
      rethrow;
    }
  }

  Future<void> _doInit() async {
    _initTimezone();

    // В release-сборке resource shrinker может удалить @drawable/ic_stat_notify
    // если на него нет XML-ссылки (keep.xml и manifest meta-data это фиксят).
    // Fallback на @mipmap/ic_launcher гарантирует, что инициализация не упадёт
    // даже если иконка всё-таки пропала — уведомления будут работать.
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [],
    );

    bool pluginInited = false;
    for (final icon in [_androidIcon, "@mipmap/ic_launcher"]) {
      try {
        await _plugin.initialize(
          settings: InitializationSettings(
            android: AndroidInitializationSettings(icon),
            iOS: iosSettings,
          ),
          onDidReceiveNotificationResponse: _onNotificationTapped,
        );
        if (icon != _androidIcon) {
          debugPrint(
            "NotificationService: $icon used as fallback — "
            "ic_stat_notify not found (resource stripped?)",
          );
        }
        pluginInited = true;
        break;
      } on PlatformException catch (e) {
        if (e.code == "invalid_icon") {
          debugPrint("NotificationService: icon '$icon' missing: $e");
          continue;
        }
        rethrow;
      }
    }
    if (!pluginInited) {
      throw StateError(
        "NotificationService: no valid icon found, notifications disabled",
      );
    }

    if (Platform.isAndroid) {
      final ap = _androidPlugin;
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
    debugPrint("NotificationService: initialized");
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // ПЛАНИРОВАНИЕ
  // ─────────────────────────────────────────────────────────────────────────────

  /// Запланировать уведомления на сегодня.
  ///
  /// Старые уведомления отменяются первым делом — повторный вызов безопасен.
  /// Если [enabled] == false, только отменяет всё и сохраняет состояние.
  Future<void> scheduleToday({
    required List<Lesson> lessons,
    required int offsetMinutes,
    required bool enabled,
  }) async {
    await _ensureInit();

    // Сначала сохраняем — чтобы restoreIfNeeded() знал актуальное состояние.
    await _saveToPrefs(
      lessons: lessons,
      offsetMinutes: offsetMinutes,
      enabled: enabled,
    );

    await _plugin.cancelAll();

    if (!enabled) {
      debugPrint("NotificationService: notifications disabled, cancelled all");
      return;
    }

    // Android 13+: проверяем POST_NOTIFICATIONS перед планированием.
    if (Platform.isAndroid) {
      final granted = await _androidPlugin?.areNotificationsEnabled() ?? false;
      if (!granted) {
        debugPrint(
          "NotificationService: POST_NOTIFICATIONS not granted — skipping schedule",
        );
        return;
      }
    }

    // Exact alarms: Android 12+ (API 31). Падаем на inexact если нет разрешения.
    final bool canExact;
    if (Platform.isAndroid) {
      canExact =
          await _androidPlugin?.canScheduleExactNotifications() ?? false;
    } else {
      canExact = true;
    }

    debugPrint(
      "NotificationService: scheduling ${lessons.length} lessons "
      "(canExact=$canExact, offset=${offsetMinutes}m)",
    );

    int scheduled = 0;
    for (final lesson in lessons) {
      final notifyAt =
          lesson.todayStartsAt.subtract(Duration(minutes: offsetMinutes));

      // Пропускаем пары, до которых меньше 30 секунд.
      if (!notifyAt.isAfter(DateTime.now().add(const Duration(seconds: 30)))) {
        continue;
      }

      final scheduledDate = tz.TZDateTime.from(notifyAt, tz.local);
      final details = _lessonDetails(lesson, offsetMinutes);
      final id = lesson.notificationId();
      final title = _title(lesson.number, offsetMinutes);
      final body = _bodyShort(lesson);

      final ok = await _scheduleOne(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        details: details,
        canExact: canExact,
      );
      if (ok) scheduled++;
    }

    debugPrint(
      "NotificationService: scheduled $scheduled/${lessons.length}",
    );
  }

  /// Восстановить уведомления из кеша.
  ///
  /// Вызывать при каждом запуске — уведомления могут быть сброшены системой
  /// (перезагрузка, обновление приложения).
  Future<void> restoreIfNeeded() async {
    await _ensureInit();

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kEnabled) ?? false;
    if (!enabled) return;

    final raw = prefs.getString(_kLessons);
    if (raw == null) return;

    final offset = prefs.getInt(_kOffset) ?? 10;

    final List<Lesson> lessons;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      lessons = list
          .map((e) => Lesson.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint("NotificationService: restoreIfNeeded parse error: $e");
      return;
    }

    await scheduleToday(
      lessons: lessons,
      offsetMinutes: offset,
      enabled: true,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // РАЗРЕШЕНИЯ
  // ─────────────────────────────────────────────────────────────────────────────

  /// Запросить разрешения при первом запуске.
  ///
  /// Вызывать **после** `runApp()` через `addPostFrameCallback` — Activity
  /// должна быть готова к показу системного диалога.
  ///
  /// Возвращает `true` если разрешение было только что выдано (ранее не было).
  /// В этом случае вызывающий код должен перепланировать уведомления.
  Future<bool> requestPermissionsOnStartup() async {
    await _ensureInit();

    if (Platform.isAndroid) {
      final alreadyGranted =
          await _androidPlugin?.areNotificationsEnabled() ?? false;
      if (alreadyGranted) return false;

      final granted =
          await _androidPlugin?.requestNotificationsPermission() ?? false;
      debugPrint(
        "NotificationService: requestPermissionsOnStartup Android → granted=$granted",
      );
      return granted;
    }

    if (Platform.isIOS) {
      final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted = await iosPlugin?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
      debugPrint(
        "NotificationService: requestPermissionsOnStartup iOS → granted=$granted",
      );
      return granted;
    }

    return false;
  }

  /// Разрешены ли уведомления системой (Android 13+, API 33+).
  Future<bool> areNotificationsEnabled() async {
    await _ensureInit();
    if (Platform.isAndroid) {
      return await _androidPlugin?.areNotificationsEnabled() ?? false;
    }
    return true;
  }

  /// Доступны ли точные будильники (Android 12+, API 31+).
  Future<bool> canScheduleExactAlarms() async {
    await _ensureInit();
    if (Platform.isAndroid) {
      return await _androidPlugin?.canScheduleExactNotifications() ?? false;
    }
    return true;
  }

  /// Запросить разрешение `POST_NOTIFICATIONS`. Возвращает true если выдано.
  Future<bool> requestNotificationPermission() async {
    await _ensureInit();
    if (Platform.isAndroid) {
      return await _androidPlugin?.requestNotificationsPermission() ?? false;
    }
    return true;
  }

  /// Открыть системный экран разрешения точных будильников (Android 12+).
  Future<void> requestExactAlarmPermission() async {
    await _ensureInit();
    if (Platform.isAndroid) {
      await _androidPlugin?.requestExactAlarmsPermission();
    }
  }

  /// Открыть системные настройки уведомлений для этого приложения.
  ///
  /// Используется когда пользователь отказал в разрешении и повторный
  /// вызов [requestNotificationPermission] не показывает диалог.
  Future<void> openNotificationSettings() async {
    if (Platform.isAndroid) {
      try {
        await const MethodChannel("com.example.raspiflutter/system_settings")
            .invokeMethod<void>("openNotificationSettings");
      } catch (e) {
        debugPrint("NotificationService: openNotificationSettings error: $e");
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // ПРОЧИЕ ПУБЛИЧНЫЕ МЕТОДЫ
  // ─────────────────────────────────────────────────────────────────────────────

  /// Отменить все уведомления и пометить как выключенные.
  Future<void> cancelAll() async {
    await _ensureInit();
    await _plugin.cancelAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, false);
    debugPrint("NotificationService: all notifications cancelled");
  }

  /// Уведомление «расписание изменилось».
  ///
  /// Из фонового изолята (Workmanager) передавай [fromBackgroundWorker]: true —
  /// в нём [appInForeground] всегда true из-за отдельного изолята.
  Future<void> showScheduleChanged({
    required String groupName,
    bool fromBackgroundWorker = false,
  }) async {
    if (!fromBackgroundWorker && appInForeground) return;
    await _ensureInit();

    if (Platform.isAndroid) {
      final granted = await _androidPlugin?.areNotificationsEnabled() ?? false;
      if (!granted) return;
    }

    final body = groupName.trim().isEmpty
        ? "Данные обновлены. Откройте приложение."
        : "Группа «$groupName» — проверьте расписание.";

    await _plugin.show(
      id: 99989,
      title: "Расписание изменилось",
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

  /// Запланировать тестовое уведомление через 1 минуту.
  /// Возвращает true если запланировано (exact или inexact).
  Future<bool> scheduleTestIn1Min() async {
    await _ensureInit();
    final at = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 1));
    final details = _details(_channel);

    // Сначала пробуем exact.
    try {
      await _plugin.zonedSchedule(
        id: 99991,
        title: "Тест: таймер ✓",
        body: "Пришло через 1 мин — exact alarm работает",
        scheduledDate: at,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      return true;
    } catch (e) {
      debugPrint("NotificationService: exact test failed, trying inexact: $e");
    }

    // Fallback: inexact.
    try {
      await _plugin.zonedSchedule(
        id: 99991,
        title: "Тест: таймер (неточный) ✓",
        body: "Пришло через ~1 мин — inexact alarm",
        scheduledDate: at,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      return true;
    } catch (e) {
      debugPrint("NotificationService: inexact test also failed: $e");
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // PRIVATE
  // ─────────────────────────────────────────────────────────────────────────────

  Future<bool> _scheduleOne({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails details,
    required bool canExact,
  }) async {
    if (canExact) {
      try {
        await _plugin.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: scheduledDate,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
        return true;
      } catch (e) {
        debugPrint(
          "NotificationService: exact failed for id=$id, trying inexact: $e",
        );
      }
    }

    // Inexact fallback (или основной путь если нет exact permission).
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      return true;
    } catch (e) {
      debugPrint("NotificationService: inexact also failed for id=$id: $e");
      return false;
    }
  }

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
          channelId == _channelChanges
              ? "Изменения расписания"
              : "Напоминания о парах",
          channelDescription: "Уведомления расписания",
          icon: _androidIcon,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

  NotificationDetails _lessonDetails(Lesson lesson, int offsetMinutes) {
    final title = _title(lesson.number, offsetMinutes);
    final bigText = _bodyBig(lesson);

    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channel,
        "Напоминания о парах",
        channelDescription: "За N минут до начала пары",
        icon: _androidIcon,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        visibility: NotificationVisibility.public,
        styleInformation: BigTextStyleInformation(
          bigText,
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

  /// Одна строка: название · кабинет (подгруппа) · препод/группа.
  static String _bodyShort(Lesson lesson) {
    const maxSubjectLen = 36;
    final subject = lesson.subject.length > maxSubjectLen
        ? "${lesson.subject.substring(0, maxSubjectLen)}…"
        : lesson.subject;
    final parts = <String>[subject];
    if (lesson.classroom?.trim().isNotEmpty == true) {
      parts.add(lesson.classroom!.trim());
    }
    if (lesson.subgroup != null) parts.add("п/г ${lesson.subgroup}");
    final last = lesson.teacher ?? lesson.groupName;
    if (last?.trim().isNotEmpty == true) parts.add(last!.trim());
    return parts.join(" · ");
  }

  /// Развёрнутый текст (BigText): название, кабинет, подгруппа, препод/группа, время.
  static String _bodyBig(Lesson lesson) {
    final lines = <String>[lesson.subject];
    if (lesson.classroom?.trim().isNotEmpty == true) {
      lines.add("Кабинет: ${lesson.classroom!.trim()}");
    }
    if (lesson.subgroup != null) lines.add("Подгруппа ${lesson.subgroup}");
    if (lesson.teacher?.trim().isNotEmpty == true) {
      lines.add("Преподаватель: ${lesson.teacher!.trim()}");
    }
    if (lesson.groupName?.trim().isNotEmpty == true) {
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

  /// Обработчик тапа по уведомлению.
  ///
  /// `@pragma("vm:entry-point")` обязателен: в release R8 не видит вызова
  /// из нативного кода и может удалить функцию при tree-shaking.
  @pragma("vm:entry-point")
  static void _onNotificationTapped(NotificationResponse response) {
    openScheduleOnTap.value = true;
  }

  /// Установить локальный timezone.
  ///
  /// Сначала пробуем найти по имени (`Europe/Moscow`, `Asia/Yakutsk` и т.д.),
  /// потом по смещению часов (Etc/GMT±N).
  static void _initTimezone() {
    tz_data.initializeTimeZones();

    // Попытка 1: имя зоны системы (на Android обычно корректный IANA-идентификатор).
    final tzName = DateTime.now().timeZoneName;
    if (tzName.isNotEmpty) {
      try {
        tz.setLocalLocation(tz.getLocation(tzName));
        debugPrint("NotificationService: timezone set by name → $tzName");
        return;
      } catch (_) {
        // Имя не найдено в базе (например аббревиатура "YAKT") — идём дальше.
      }
    }

    // Попытка 2: Etc/GMT±N по смещению часов.
    final offset = DateTime.now().timeZoneOffset;
    final h = offset.inHours.clamp(-12, 14);
    // POSIX: Etc/GMT-8 = UTC+8, Etc/GMT+5 = UTC-5 (инвертированный знак).
    final sign = h <= 0 ? "+" : "-";
    try {
      tz.setLocalLocation(tz.getLocation("Etc/GMT$sign${h.abs()}"));
      debugPrint(
        "NotificationService: timezone set by offset → Etc/GMT$sign${h.abs()}",
      );
      return;
    } catch (_) {}

    // Последний резерв.
    tz.setLocalLocation(tz.UTC);
    debugPrint("NotificationService: timezone fallback → UTC");
  }
}
