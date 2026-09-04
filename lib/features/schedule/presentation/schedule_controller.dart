import "dart:async";

import "package:flutter/foundation.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../../../core/notifications/notification_service.dart"
    show Lesson, NotificationService;
import "../../../core/widgets/home_widget_service.dart";
import "../data/express_schedule_repository.dart";
import "../data/groups_cache.dart";
import "../data/lesson_times.dart";
import "../data/preferences_manager.dart";
import "../data/lesson_times_sync.dart";
import "../data/schedule_cache.dart";
import "../data/statistics_cache.dart";
import "../data/sub_schedule_cache.dart";
import "../domain/models.dart";
import "../domain/schedule_hash.dart";

class ScheduleController extends ChangeNotifier {
  ScheduleController({required SharedPreferences prefs})
      : _prefsManager = PreferencesManager(prefs) {
    final sCache = ScheduleCache(prefs);
    final gCache = GroupsCache(prefs);
    final stCache = StatisticsCache(prefs);
    final subCache = SubScheduleCache(prefs);
    _repository = ExpressScheduleRepository(
      scheduleCache: sCache,
      groupsCache: gCache,
      statisticsCache: stCache,
      subScheduleCache: subCache,
    );
    _lessonTimesSync = LessonTimesSync(_prefsManager);
    _applyCustomBaseUrls();
    _applyCustomLessonTimes();
  }

  Timer? _autoRefreshTimer;
  Timer? _remoteLessonTimesTimer;
  DateTime? _lastScheduleRefreshAt;
  bool _silentRefreshInFlight = false;
  static const Duration _staleThreshold = Duration(minutes: 25);

  final PreferencesManager _prefsManager;
  late final ExpressScheduleRepository _repository;
  late final LessonTimesSync _lessonTimesSync;

  PreferencesManager get prefs => _prefsManager;
  ExpressScheduleRepository get repository => _repository;

  bool isLoading = false;
  String? error;

  List<Group> groups = const [];
  Group? selectedGroup;
  List<DaySchedule> schedule = const [];

  bool isLoadingStats = false;
  GroupStatistics? statistics;

  String get college => _prefsManager.college;

  Future<void> init() async {
    // Не ждём сеть на старте: цепочка фолбэков может занять секунды, а
    // расписание рисуется из кэша сразу. Изменится время — экран
    // перерисуется сам, когда запрос вернётся.
    unawaited(_syncRemoteLessonTimesIfNeeded(silent: true));
    _startRemoteLessonTimesAutoSync();
    if (_prefsManager.isGroupSelected) {
      selectedGroup = Group(
        id: -1,
        name: _prefsManager.selectedGroupName,
        fileName: _prefsManager.selectedGroupFile,
        pageUrl: "",
      );
      try {
        final firstDay = _repository.scheduleCache
            ?.loadFirstDay(selectedGroup!.fileName, college);
        if (firstDay != null) {
          schedule = [firstDay];
          notifyListeners();
        }
      } catch (_) {}
      // Load cached schedule immediately for faster first paint,
      // then refresh group/teacher list in background.
      await loadSchedule(useCache: true);
      await loadGroups(silent: true);
      final syncedFile = selectedGroup?.fileName ?? "";
      if (syncedFile.isNotEmpty &&
          syncedFile != _prefsManager.selectedGroupFile) {
        _prefsManager.selectedGroupFile = syncedFile;
        await loadSchedule(useCache: true);
      }
    }
    startAutoRefresh();
  }

  Future<void> loadGroups({bool silent = false, bool force = false}) async {
    if (!silent) {
      isLoading = true;
      error = null;
      notifyListeners();
    }

    try {
      if (_prefsManager.isTeacherMode) {
        groups = await _repository.fetchTeachers(
          college: college,
          forceRefresh: force,
        );
      } else {
        groups = await _repository.fetchGroups(
          college: college,
          forceRefresh: force,
        );
      }

      if (selectedGroup != null) {
        final byFile =
            groups.where((g) => g.fileName == selectedGroup!.fileName);
        if (byFile.isNotEmpty) {
          selectedGroup = byFile.first;
        } else {
          final byName = groups.where((g) => g.name == selectedGroup!.name);
          if (byName.isNotEmpty) {
            selectedGroup = byName.first;
          }
        }
      }
    } catch (e) {
      if (!silent) error = _humanReadableError(e);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadSchedule({bool useCache = true}) async {
    final group = selectedGroup;
    if (group == null) return;

    isLoading = true;
    error = null;
    notifyListeners();

    try {
      schedule = await _repository.fetchSchedule(
        groupFile: group.fileName,
        college: college,
        useCache: useCache,
      );
      _lastScheduleRefreshAt = DateTime.now();
      _prefsManager.lastScheduleNetworkOkMs =
          DateTime.now().millisecondsSinceEpoch;
      if (schedule.isEmpty) {
        error = "Расписание не найдено.";
      }
      if (_repository.scheduleChanged) _repository.clearChangedFlag();
      _checkScheduleHashAndNotify();
      await _syncLessonNotifications();
      _updateHomeWidget();
    } catch (e) {
      error = _humanReadableError(e);
      if (schedule.isEmpty) {
        final cached = _repository.scheduleCache
            ?.loadAllowingExpired(group.fileName, college);
        if (cached != null && cached.isNotEmpty) {
          schedule = cached;
          error = "Показаны сохранённые данные. $error";
          _updateHomeWidget();
          await _syncLessonNotifications();
        }
      } else {
        error = "Не удалось обновить. $error";
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshSchedule() => loadSchedule(useCache: false);

  /// Вызывать при возврате в приложение: тихо обновляет расписание, если кэш устарел.
  Future<void> onAppResumed() async {
    // Время пар проверяем всегда: оно меняется независимо от расписания,
    // а гейт по интервалу и паузе после ошибок внутри LessonTimesSync.
    unawaited(_syncRemoteLessonTimesIfNeeded(silent: true));
    if (!_prefsManager.autoRefreshEnabled || selectedGroup == null) return;
    final now = DateTime.now();
    if (_lastScheduleRefreshAt != null &&
        now.difference(_lastScheduleRefreshAt!) < _staleThreshold) {
      return;
    }
    await _refreshScheduleSilent();
  }

  /// Фоновое обновление без индикатора загрузки (для resume и таймера).
  Future<void> _refreshScheduleSilent() async {
    final group = selectedGroup;
    if (group == null) return;
    if (_silentRefreshInFlight) return;
    _silentRefreshInFlight = true;
    try {
      final result = await _repository.fetchSchedule(
        groupFile: group.fileName,
        college: college,
        useCache: false,
      );
      if (result.isEmpty) return;
      // Отбрасываем результат если группа сменилась пока шёл запрос.
      if (selectedGroup?.fileName != group.fileName) return;
      schedule = result;
      _lastScheduleRefreshAt = DateTime.now();
      _prefsManager.lastScheduleNetworkOkMs =
          DateTime.now().millisecondsSinceEpoch;
      if (_repository.scheduleChanged) _repository.clearChangedFlag();
      _checkScheduleHashAndNotify();
      await _syncLessonNotifications();
      _updateHomeWidget();
      notifyListeners();
    } catch (_) {
    } finally {
      _silentRefreshInFlight = false;
    }
  }

  void _checkScheduleHashAndNotify() {
    final newHash = computeScheduleHash(schedule);
    final old = _prefsManager.lastScheduleHash;
    if (old.isNotEmpty &&
        old != newHash &&
        _prefsManager.notifyScheduleChanges) {
      try {
        NotificationService.instance.showScheduleChanged(
          groupName: selectedGroup?.name ?? _prefsManager.selectedGroupName,
        );
      } catch (_) {}
    }
    _prefsManager.lastScheduleHash = newHash;
  }

  /// Перепланировать напоминания на сегодня. Возвращает сообщение для пользователя.
  Future<String> syncNotificationsNow() async {
    try {
      return await _syncLessonNotifications();
    } catch (e) {
      return "Ошибка: $e";
    }
  }

  Future<String> _syncLessonNotifications() async {
    final today = DateTime.now();
    final todayKey =
        "${today.day.toString().padLeft(2, "0")}.${today.month.toString().padLeft(2, "0")}.${today.year}";
    final todayKeyAlt =
        "${today.year}-${today.month.toString().padLeft(2, "0")}-${today.day.toString().padLeft(2, "0")}";
    final todaySchedule = schedule
        .where((d) => d.date == todayKey || d.date == todayKeyAlt)
        .toList();
    final enabled = _prefsManager.notificationsEnabled;

    if (!enabled) {
      await NotificationService.instance.scheduleToday(
        lessons: const [],
        offsetMinutes: _prefsManager.notificationOffset,
        enabled: false,
      );
      return "Напоминания выключены";
    }
    if (todaySchedule.isEmpty || todaySchedule.first.items.isEmpty) {
      await NotificationService.instance.scheduleToday(
        lessons: const [],
        offsetMinutes: _prefsManager.notificationOffset,
        enabled: true,
      );
      return "Нет пар на сегодня";
    }

    final isTeacher = _prefsManager.isTeacherMode;
    final lessonList = todaySchedule.first.items
        .map(
          (e) => Lesson(
            number: e.lessonNumber,
            subject: e.subject ?? "Пара ${e.lessonNumber}",
            startTime: LessonTimes.getTime(e.lessonNumber, college: college)
                    ?.startTime ??
                "08:00",
            classroom: e.classroom,
            subgroup: e.subgroup,
            teacher: isTeacher ? null : e.teacher,
            groupName: isTeacher ? selectedGroup?.name : null,
          ),
        )
        .toList()
      ..sort((a, b) => a.number.compareTo(b.number));

    await NotificationService.instance.scheduleToday(
      lessons: lessonList,
      offsetMinutes: _prefsManager.notificationOffset,
      enabled: true,
    );
    return "Запланировано ${lessonList.length} напоминаний на сегодня";
  }

  void startAutoRefresh() {
    stopAutoRefresh();
    if (!_prefsManager.autoRefreshEnabled) return;
    final minutes = _prefsManager.autoRefreshInterval;
    final interval = Duration(minutes: minutes);
    _autoRefreshTimer = Timer.periodic(interval, (_) {
      if (selectedGroup != null) {
        unawaited(_refreshScheduleSilent());
      }
    });
  }

  void stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  void _startRemoteLessonTimesAutoSync() {
    _remoteLessonTimesTimer?.cancel();
    final h = _prefsManager.lessonTimesMinIntervalHours.clamp(1, 168);
    _remoteLessonTimesTimer = Timer.periodic(
      Duration(hours: h),
      (_) => _syncRemoteLessonTimesIfNeeded(silent: true),
    );
  }

  Future<void> loadStatistics() async {
    final group = selectedGroup;
    if (group == null) return;

    isLoadingStats = true;
    notifyListeners();

    try {
      statistics = await _repository.fetchStatistics(
        groupFile: group.fileName,
        college: college,
      );
    } catch (_) {
      statistics = null;
    } finally {
      isLoadingStats = false;
      notifyListeners();
    }
  }

  Future<void> refreshStatistics() async {
    await loadStatistics();
  }

  void selectGroup(Group? group) {
    selectedGroup = group;
    _lastScheduleRefreshAt =
        null; // сбрасываем, чтобы onAppResumed обновил новую группу
    if (group != null) {
      _prefsManager.selectedGroupFile = group.fileName;
      _prefsManager.selectedGroupName = group.name;
    } else {
      _prefsManager.selectedGroupFile = "";
      _prefsManager.selectedGroupName = "";
    }
    schedule = const [];
    statistics = null;
    notifyListeners();
  }

  void setCollege(String value) {
    _prefsManager.college = value;
    groups = const [];
    selectedGroup = null;
    schedule = const [];
    statistics = null;
    _prefsManager.selectedGroupFile = "";
    _prefsManager.selectedGroupName = "";
    notifyListeners();
  }

  void refreshCollegeSources() {
    _applyCustomBaseUrls();
    notifyListeners();
  }

  void setUserMode(String mode) {
    if (_prefsManager.userMode == mode) return;
    _prefsManager.userMode = mode;
    groups = const [];
    selectedGroup = null;
    schedule = const [];
    statistics = null;
    _prefsManager.selectedGroupFile = "";
    _prefsManager.selectedGroupName = "";
    notifyListeners();
  }

  // Полоска-акцент в виджете красится всегда: свой цвет темы, если
  // пользователь не задал кастомный акцент — иначе виджет рисует её
  // белой (Kotlin-сторона фолбэчится на themeTitleColor, который для
  // тёмной темы = белый, и полоска не смотрится).
  int _widgetAccentColor(String widgetTheme) =>
      widgetAccentColorFor(_prefsManager, widgetTheme);

  void _updateHomeWidget() {
    final widgetTheme = _prefsManager.effectiveWidgetTheme;
    HomeWidgetService.updateWidget(
      schedule: schedule,
      groupName: selectedGroup?.name ?? _prefsManager.selectedGroupName,
      themeKey: widgetTheme,
      fontScale: _prefsManager.widgetFontScale,
      college: college,
      accentColorValue: _widgetAccentColor(widgetTheme),
    );
  }

  void refreshHomeWidget() {
    _updateHomeWidget();
  }

  void refreshHomeWidgetTheme() {
    final widgetTheme = _prefsManager.effectiveWidgetTheme;
    HomeWidgetService.updateWidgetTheme(
      themeKey: widgetTheme,
      fontScale: _prefsManager.widgetFontScale,
      accentColorValue: _widgetAccentColor(widgetTheme),
    );
  }

  String _humanReadableError(Object e) {
    final msg = e.toString();
    if (msg.contains("SocketException") || msg.contains("подключени")) {
      return "Нет подключения к интернету";
    }
    if (msg.contains("Timeout") || msg.contains("время ожидания")) {
      return "Сервер не отвечает. Попробуйте позже";
    }
    if (msg.contains("HTTP 5")) {
      return "Ошибка сервера. Попробуйте позже";
    }
    if (msg.contains("HTTP 4")) {
      return "Страница не найдена";
    }
    if (msg.contains("FormatException")) {
      return "Некорректный формат файла времени пар";
    }
    if (msg.contains("StateError")) {
      return msg.replaceAll("StateError: ", "").replaceAll("Bad state: ", "");
    }
    return "Ошибка загрузки данных";
  }

  void _applyCustomLessonTimes() {
    _prefsManager.applyStoredLessonTimes();
  }

  void _applyCustomBaseUrls() {
    _repository.setCustomBaseUrls(_prefsManager.effectiveCollegeBaseUrls);
  }

  Future<bool> refreshLessonTimesFromRemote({bool silent = false}) async {
    return _syncRemoteLessonTimesIfNeeded(force: true, silent: silent);
  }

  Future<bool> _syncRemoteLessonTimesIfNeeded({
    bool force = false,
    bool silent = false,
  }) async {
    try {
      final result = await _lessonTimesSync.run(force: force);
      _startRemoteLessonTimesAutoSync();
      if (result.changed) {
        if (selectedGroup != null) {
          await loadSchedule(useCache: true);
        } else {
          notifyListeners();
        }
      }
      return result.ok;
    } catch (e) {
      if (!silent) {
        error = _humanReadableError(e);
        notifyListeners();
      }
      return false;
    }
  }

  @override
  void dispose() {
    stopAutoRefresh();
    _remoteLessonTimesTimer?.cancel();
    _remoteLessonTimesTimer = null;
    _repository.dispose();
    super.dispose();
  }
}
