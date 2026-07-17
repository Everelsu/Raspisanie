import "dart:async";
import "dart:io";

import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:package_info_plus/package_info_plus.dart";

import "../../../core/notifications/notification_service.dart";
import "../../../core/services/analytics_service.dart";
import "../../../core/services/font_service.dart";
import "../../../core/update/app_update_controller.dart";
import "../../../core/update/changelog_page.dart";
import "../../../core/update/update_dialog.dart";
import "../../../core/update/version_utils.dart";
import "../../../core/widgets/animated_app_bar.dart";
import "../../../core/widgets/bottom_bar_sheet.dart";
import "../../games/games_menu.dart";
import "../../network/presentation/browser_bar.dart";
import "../../network/presentation/network_page.dart";
import "../../schedule/domain/models.dart";
import "../../schedule/presentation/history_calendar_sheet.dart";
import "../../schedule/presentation/schedule_controller.dart";
import "../../schedule/presentation/schedule_page.dart";
import "../../settings/presentation/settings_page.dart";
import "../../statistics/presentation/statistics_page.dart";

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.onThemeChanged,
    required this.fontService,
  });
  final ScheduleController controller;
  final VoidCallback onThemeChanged;
  final FontService fontService;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  /// Варианты «за сколько минут до пары» в настройках уведомлений.
  static const List<int> _kNotificationOffsets = [5, 10, 15];

  int _currentIndex = 0;
  bool _sheetOpen = false;
  bool _appUpdateDialogOpen = false;
  bool _isProgrammaticNavigation = false;
  PageController? _pageController;

  /// Контроллеры прокрутки вкладок — для «скролла наверх» по долгому
  /// нажатию на AppBar (расписание и итоги).
  final _scheduleScrollCtrl = ScrollController();
  final _statsScrollCtrl = ScrollController();

  /// Состояние браузерного тулбара. Сам тулбар рисуется здесь — в едином
  /// AppBar (переключается с заголовком по вкладке), а WebView-логика
  /// живёт в NetworkPage.
  final _browserBarCtrl = BrowserBarController();

  /// Fullscreen WebView on the network tab — hides bottom bar + in-browser toolbar.
  bool _networkImmersive = false;
  late final ValueNotifier<bool> _networkImmersiveNotifier;

  static const _titles = [
    "Расписание",
    "Итоги",
    "Сеть",
    "Настройки",
  ];
  static const _screenIds = ["schedule", "stats", "network", "settings"];

  PageController get _safePageController =>
      _pageController ??= PageController(initialPage: _currentIndex);

  @override
  void initState() {
    super.initState();
    _networkImmersiveNotifier = ValueNotifier<bool>(false);
    _pageController = PageController(initialPage: _currentIndex);
    WidgetsBinding.instance.addObserver(this);
    NotificationService.openScheduleOnTap.addListener(_onOpenScheduleRequested);
    AnalyticsService.instance.logScreen(_screenIds[_currentIndex]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowWhatsNewSnackbar();
    });
    if (Platform.isAndroid && widget.controller.prefs.autoCheckAppUpdate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tryShowPendingBackgroundUpdate();
        Future.delayed(const Duration(seconds: 2), () {
          _checkForegroundAppUpdate();
        });
      });
    }
  }

  /// После установки обновления показываем ненавязчивый снекбар со ссылкой
  /// на журнал изменений. Для свежих установок просто запоминаем версию.
  Future<void> _maybeShowWhatsNewSnackbar() async {
    final prefs = widget.controller.prefs;
    final info = await PackageInfo.fromPlatform();
    final seen = prefs.lastSeenAppVersion;
    if (seen == info.version) return;
    prefs.lastSeenAppVersion = info.version;
    if (seen == null || seen.isEmpty) return;
    if (compareVersions(seen, info.version) >= 0) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Приложение обновлено до ${info.version}"),
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: "Что нового",
          onPressed: () {
            if (!mounted) return;
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ChangelogPage(),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scheduleScrollCtrl.dispose();
    _statsScrollCtrl.dispose();
    _browserBarCtrl.dispose();
    _networkImmersiveNotifier.dispose();
    _pageController?.dispose();
    _pageController = null;
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.openScheduleOnTap
        .removeListener(_onOpenScheduleRequested);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) return;
    if (!Platform.isAndroid || !widget.controller.prefs.autoCheckAppUpdate) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryShowPendingBackgroundUpdate();
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = widget.controller.prefs.lastResumeAppUpdateCheckMs ?? 0;
      if (now - last < const Duration(hours: 6).inMilliseconds) return;
      widget.controller.prefs.lastResumeAppUpdateCheckMs = now;
      _checkForegroundAppUpdate();
    });
  }

  /// Кэш вкладок: одинаковые инстансы виджетов между build'ами — Flutter
  /// пропускает их пересборку (identical-check), и setState на переключении
  /// вкладки не перестраивает все четыре страницы разом (это был главный
  /// источник просадки кадров при переключении).
  ///
  /// Кэш сбрасывается при смене controller/fontService (didUpdateWidget) и
  /// при hot reload (reassemble) — это сохраняет старый фикс «битых» слотов
  /// после hot reload. NetworkPage пересоздаётся только когда меняется его
  /// isActive-флаг.
  List<Widget>? _tabPagesCache;
  bool? _tabPagesNetworkActive;

  List<Widget> _buildTabPages() {
    final networkActive = _currentIndex == 2;
    if (_tabPagesCache != null && _tabPagesNetworkActive == networkActive) {
      return _tabPagesCache!;
    }
    final networkPage = RepaintBoundary(
      child: NetworkPage(
        key: const ValueKey<Object>("network_browser_v2"),
        scheduleController: widget.controller,
        isActive: networkActive,
        barController: _browserBarCtrl,
        parentImmersiveNotifier: _networkImmersiveNotifier,
        onImmersiveChanged: (v) {
          setState(() {
            _networkImmersive = v;
            _networkImmersiveNotifier.value = v;
          });
        },
      ),
    );
    if (_tabPagesCache != null) {
      // ВАЖНО: новый список, а не мутация старого. Старый PageView держит
      // ссылку на прежний список; мутация на месте делала old.children[2]
      // == new.children[2], диффер считал ребёнка неизменным и NetworkPage
      // не получал isActive=true при свайпе на вкладку.
      _tabPagesCache = List.of(_tabPagesCache!)..[2] = networkPage;
    } else {
      _tabPagesCache = [
        RepaintBoundary(
          child: SchedulePage(
            key: const ValueKey<Object>("home_tab_schedule"),
            controller: widget.controller,
            fontService: widget.fontService,
            scrollController: _scheduleScrollCtrl,
          ),
        ),
        RepaintBoundary(
          child: StatisticsPage(
            key: const ValueKey<Object>("home_tab_stats"),
            controller: widget.controller,
            scrollController: _statsScrollCtrl,
          ),
        ),
        networkPage,
        RepaintBoundary(
          child: SettingsPage(
            key: const ValueKey<Object>("home_tab_settings"),
            controller: widget.controller,
            onThemeChanged: widget.onThemeChanged,
            fontService: widget.fontService,
          ),
        ),
      ];
    }
    _tabPagesNetworkActive = networkActive;
    return _tabPagesCache!;
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.fontService != widget.fontService) {
      _tabPagesCache = null;
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    _tabPagesCache = null;
  }

  /// Фоновый воркер нашёл обновление — сразу запускаем полную проверку
  /// (без троттлинга): контроллер заново получит манифест и подготовит APK.
  Future<void> _tryShowPendingBackgroundUpdate() async {
    final p = widget.controller.prefs;
    final ver = p.pendingAppUpdateVersion;
    if (ver == null || ver.isEmpty) return;
    p.clearPendingAppUpdate();
    if (!mounted || _appUpdateDialogOpen) return;
    final info = await PackageInfo.fromPlatform();
    if (!mounted || compareVersions(info.version, ver) >= 0) return;
    await _checkForegroundAppUpdate();
  }

  Future<void> _checkForegroundAppUpdate() async {
    if (!mounted || _appUpdateDialogOpen) return;
    final controller = AppUpdateController.instance;
    final update = await controller.check();
    if (!mounted || update == null) return;
    // Если APK уже качается — дождёмся: диалог сразу предложит «Установить».
    if (controller.downloading) {
      await controller.download();
      if (!mounted || controller.available == null) return;
    }
    if (!await controller.shouldPrompt()) return;
    if (!mounted) return;
    await _showUpdateDialog();
  }

  Future<void> _showUpdateDialog() async {
    if (!mounted || _appUpdateDialogOpen) return;
    _appUpdateDialogOpen = true;
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      await showAppUpdateDialog(context, currentVersion: info.version);
    } finally {
      _appUpdateDialogOpen = false;
    }
  }

  void _onOpenScheduleRequested() {
    if (!NotificationService.openScheduleOnTap.value || !mounted) return;
    NotificationService.openScheduleOnTap.value = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _sheetOpen = false;
      });
      _goToPage(0);
    });
  }

  Future<void> _goToPage(int index) async {
    if (!mounted || index == _currentIndex) return;
    _applyTabChange(index);
    final controller = _pageController;
    if (controller == null) return;
    if (controller.hasClients) {
      _isProgrammaticNavigation = true;
      try {
        await controller.animateToPage(
          index,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      } finally {
        _isProgrammaticNavigation = false;
      }
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = _pageController;
      if (c == null || !c.hasClients) return;
      c.jumpToPage(index);
    });
  }

  void _applyTabChange(int index) {
    if (!mounted || index == _currentIndex) return;
    if (_currentIndex == 2 && index != 2) {
      _networkImmersiveNotifier.value = false;
    }
    setState(() {
      _currentIndex = index;
      if (index != 2) _networkImmersive = false;
      _sheetOpen = false;
    });
    AnalyticsService.instance.logScreen(_screenIds[index]);
  }

  Future<void> _handleNetworkBottomZoneSwipe(DragEndDetails details) async {
    if (!mounted || _currentIndex != 2 || _networkImmersive || _sheetOpen) {
      return;
    }
    final velocity = details.primaryVelocity ?? 0.0;
    const threshold = 320.0;
    if (velocity.abs() < threshold) return;
    if (velocity < 0) {
      await _goToPage(3);
      return;
    }
    await _goToPage(1);
  }

  /// Долгое нажатие на AppBar — плавный скролл наверх (расписание и итоги).
  void _handleAppBarLongPress() {
    final target = switch (_currentIndex) {
      0 => _scheduleScrollCtrl,
      1 => _statsScrollCtrl,
      _ => null,
    };
    if (target == null || !target.hasClients) return;
    if (target.offset <= 0) return;
    HapticFeedback.mediumImpact();
    target.animateTo(
      0,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  /// Свайп по AppBar на «Расписании»/«Итогах» — переключение между
  /// избранными группами (или преподавателями — тот же список).
  ///
  /// Реализовано через сырые указатели [Listener], а не
  /// [GestureDetector.onHorizontalDragEnd]: AppBar лежит поверх [PageView]
  /// в [Stack], и обычный распознаватель горизонтального жеста конкурирует
  /// с внутренним drag-распознавателем PageView за ту же арену — PageView
  /// почти всегда побеждает первым, и свайп по AppBar просто листает вкладки
  /// вместо переключения группы. [Listener] не участвует в арене жестов и
  /// получает события в любом случае.
  Offset? _appBarPointerDownPos;

  void _handleAppBarPointerDown(PointerDownEvent event) {
    _appBarPointerDownPos = event.position;
  }

  void _handleAppBarPointerCancel(PointerCancelEvent event) {
    _appBarPointerDownPos = null;
  }

  void _handleAppBarPointerUp(PointerUpEvent event) {
    final start = _appBarPointerDownPos;
    _appBarPointerDownPos = null;
    if (start == null) return;
    if (_currentIndex != 0 && _currentIndex != 1) return;
    final delta = event.position - start;
    if (delta.dx.abs() < 48) return;
    if (delta.dx.abs() < delta.dy.abs() * 1.2) return;
    _switchFavoriteGroup(delta.dx < 0 ? 1 : -1);
  }

  void _showAppBarToast(IconData icon, String text) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
        duration: const Duration(milliseconds: 1800),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 90),
      ),
    );
  }

  /// Переключение между избранными группами/преподавателями по кругу.
  /// Молча не выходим: каждая причина «не сработало» даёт подсказку —
  /// иначе фича выглядит сломанной.
  void _switchFavoriteGroup(int dir) {
    final ctrl = widget.controller;
    final isTeacher = ctrl.prefs.isTeacherMode;
    if (ctrl.groups.isEmpty) {
      unawaited(ctrl.loadGroups());
      _showAppBarToast(
        Icons.hourglass_top_rounded,
        "Список ещё загружается — попробуй через секунду",
      );
      return;
    }
    // Только избранные, существующие в текущем списке: у преподавателей
    // отфильтруются группы, добавленные в режиме студента, и наоборот.
    final names = ctrl.groups.map((g) => g.name).toSet();
    final favs = ctrl.prefs.favoriteGroups.where(names.contains).toList()
      ..sort();
    if (favs.length < 2) {
      _showAppBarToast(
        Icons.star_border_rounded,
        isTeacher
            ? "Добавь 2+ преподавателей в избранное — и переключай их свайпом по шапке"
            : "Добавь 2+ группы в избранное — и переключай их свайпом по шапке",
      );
      return;
    }
    final currentName =
        ctrl.selectedGroup?.name ?? ctrl.prefs.selectedGroupName;
    var idx = favs.indexOf(currentName);
    idx = idx == -1
        ? (dir > 0 ? 0 : favs.length - 1)
        : (idx + dir + favs.length) % favs.length;
    Group? next;
    for (final g in ctrl.groups) {
      if (g.name == favs[idx]) {
        next = g;
        break;
      }
    }
    if (next == null || next.name == currentName) return;
    HapticFeedback.mediumImpact();
    ctrl.selectGroup(next);
    unawaited(ctrl.loadSchedule());
    if (_currentIndex == 1) {
      unawaited(ctrl.loadStatistics());
    }
    _showAppBarToast(Icons.star_rounded, next.name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: null,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView(
            controller: _safePageController,
            physics: (_networkImmersive || _currentIndex == 2)
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            onPageChanged: (index) {
              if (!_isProgrammaticNavigation) {
                _applyTabChange(index);
              }
            },
            children: _buildTabPages(),
          ),
          // Растворение контента у нижнего края (кроме «Сети» — там WebView).
          // Дешёвая вуаль цветом фона вместо ShaderMask: без saveLayer на
          // весь экран, стоимость — один маленький градиент.
          if (widget.controller.prefs.contentEdgeFade && _currentIndex != 2)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 110,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Theme.of(context).scaffoldBackgroundColor,
                        Theme.of(context)
                            .scaffoldBackgroundColor
                            .withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // Единый AppBar на все вкладки: на «Сети» вместо заголовка —
          // браузерный тулбар (BrowserToolbar). Прячется только в
          // полноэкранном режиме WebView.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Builder(
              builder: (context) {
                final hidden = _currentIndex == 2 && _networkImmersive;
                return IgnorePointer(
                  ignoring: hidden,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    offset: hidden ? const Offset(0, -1.1) : Offset.zero,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 240),
                      opacity: hidden ? 0 : 1,
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: _handleAppBarPointerDown,
                        onPointerUp: _handleAppBarPointerUp,
                        onPointerCancel: _handleAppBarPointerCancel,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onLongPress: _currentIndex == 2
                              ? null
                              : _handleAppBarLongPress,
                          child: _HomeAnimatedAppBar(
                            controller: widget.controller,
                            title: _titles[_currentIndex],
                            tabIndex: _currentIndex,
                            showNotificationsAction: _currentIndex == 3,
                            onNotificationsTap: () =>
                                _showNotificationSheet(context),
                            browserToolbar: _currentIndex == 2
                                ? BrowserToolbar(controller: _browserBarCtrl)
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: AnimatedSize(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.hardEdge,
        child: (_currentIndex == 2 && _networkImmersive)
            ? const SizedBox(width: double.infinity, height: 0)
            : GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragEnd: _currentIndex == 2
                    ? (d) => _handleNetworkBottomZoneSwipe(d)
                    : null,
                child: BottomBarWithSheet(
                  selectedIndex: _currentIndex,
                  onIndexChanged: (index) async {
                    FocusScope.of(context).unfocus();
                    HapticFeedback.selectionClick();
                    await _goToPage(index);
                  },
                  sheetOpen: _sheetOpen,
                  onSheetToggle: () {
                    HapticFeedback.lightImpact();
                    FocusScope.of(context).unfocus();
                    setState(() => _sheetOpen = !_sheetOpen);
                  },
                  onSheetClosedByDrag: () {
                    setState(() => _sheetOpen = false);
                  },
                  onNavItemLongPress: (i) {
                    if (i == 2) showGamesMenu(context);
                  },
                  sheetChild:
                      HistoryCalendarSheet(controller: widget.controller),
                ),
              ),
      ),
    );
  }

  void _showNotificationSheet(BuildContext context) {
    final theme = Theme.of(context);
    final ctrl = widget.controller;
    final prefs = ctrl.prefs;
    final surface = theme.colorScheme.surface;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.72,
        ),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListenableBuilder(
          listenable: ctrl,
          builder: (ctx, _) => StatefulBuilder(
            builder: (ctx, setSheetState) => SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface.withAlpha(60),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withAlpha(25),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.notifications_rounded,
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Уведомления",
                                style: theme.textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "Напоминания о парах и изменениях",
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      margin: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _notificationSwitchTile(
                            theme,
                            setSheetState,
                            Icons.alarm_rounded,
                            "Напоминания о парах",
                            "Пуш за выбранное время до начала пары (на текущий день)",
                            prefs.notificationsEnabled,
                            (v) async {
                              setSheetState(
                                  () => prefs.notificationsEnabled = v);
                              if (!v) {
                                await NotificationService.instance.cancelAll();
                              } else {
                                await ctrl.syncNotificationsNow();
                              }
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) setState(() {});
                              });
                            },
                          ),
                          _notificationDivider(theme),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "За сколько минут до пары",
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  "Когда придёт напоминание о следующей паре",
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _notificationOffsetChooser(
                                  theme,
                                  ctrl,
                                  setSheetState,
                                ),
                                if (!prefs.notificationsEnabled)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      "Включите напоминания, чтобы выбрать интервал",
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          _notificationDivider(theme),
                          _notificationSwitchTile(
                            theme,
                            setSheetState,
                            Icons.published_with_changes_rounded,
                            "Изменение расписания",
                            "Пуш, когда данные расписания обновились",
                            prefs.notifyScheduleChanges,
                            (v) {
                              setSheetState(
                                  () => prefs.notifyScheduleChanges = v);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) setState(() {});
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    _NotificationPermissionCard(
                      onPermissionsChanged: () {
                        setSheetState(() {});
                      },
                    ),
                    if (!kReleaseMode) ...[
                      const SizedBox(height: 16),
                      Text(
                        "Отладка",
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Card(
                        clipBehavior: Clip.antiAlias,
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Тест уведомлений",
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Каналы и exact alarm. В release не показывается.",
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton(
                                    onPressed: () async {
                                      await NotificationService.instance
                                          .showTestNow();
                                    },
                                    child: const Text("Сейчас"),
                                  ),
                                  OutlinedButton(
                                    onPressed: () async {
                                      final ok = await NotificationService
                                          .instance
                                          .scheduleTestIn1Min();
                                      if (!ctx.mounted) return;
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            ok
                                                ? "Тест через 1 мин запланирован"
                                                : "Не удалось (нет разрешения)",
                                          ),
                                        ),
                                      );
                                    },
                                    child: const Text("Через 1 мин"),
                                  ),
                                  OutlinedButton(
                                    onPressed: () async {
                                      final name =
                                          prefs.selectedGroupName.trim();
                                      await NotificationService.instance
                                          .showScheduleChanged(
                                        groupName: name.isEmpty ? "Тест" : name,
                                        fromBackgroundWorker: true,
                                      );
                                    },
                                    child: const Text("«Изменилось»"),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _notificationOffsetChooser(
    ThemeData theme,
    ScheduleController ctrl,
    StateSetter setSheetState,
  ) {
    final prefs = ctrl.prefs;
    final remindersOn = prefs.notificationsEnabled;
    return Opacity(
      opacity: remindersOn ? 1 : 0.45,
      child: IgnorePointer(
        ignoring: !remindersOn,
        child: Row(
          children: [
            for (var i = 0; i < _kNotificationOffsets.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: _notificationOffsetButton(
                  theme,
                  minutes: _kNotificationOffsets[i],
                  selected:
                      prefs.notificationOffset == _kNotificationOffsets[i],
                  onTap: () async {
                    final m = _kNotificationOffsets[i];
                    setSheetState(() => prefs.notificationOffset = m);
                    await ctrl.syncNotificationsNow();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() {});
                    });
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _notificationDivider(ThemeData theme) {
    return Divider(
      height: 1,
      indent: 16,
      endIndent: 16,
      color: theme.dividerTheme.color,
    );
  }

  Widget _notificationOffsetButton(
    ThemeData theme, {
    required int minutes,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final cs = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: selected
                ? cs.primary.withAlpha(25)
                : theme.scaffoldBackgroundColor,
            border: Border.all(
              color: selected ? cs.primary : cs.onSurface.withAlpha(30),
              width: selected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              "$minutes мин",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? cs.primary : cs.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _notificationSwitchTile(
    ThemeData theme,
    StateSetter
        sheetState, // ignore: unused_parameter — нужен для единой сигнатуры с вызовом из листа
    IconData icon,
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primary.withAlpha(value ? 28 : 14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 17,
              color: value ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Карточка разрешений для уведомлений
// ─────────────────────────────────────────────────────────────────────────────

class _NotificationPermissionCard extends StatefulWidget {
  const _NotificationPermissionCard({required this.onPermissionsChanged});
  final VoidCallback onPermissionsChanged;

  @override
  State<_NotificationPermissionCard> createState() =>
      _NotificationPermissionCardState();
}

class _NotificationPermissionCardState
    extends State<_NotificationPermissionCard> with WidgetsBindingObserver {
  bool? _notifEnabled;
  bool? _exactEnabled;
  // true после того как пользователь нажал «Разрешить» и диалог не показался
  // (Android: повторный запрос после отказа молча возвращает false).
  bool _notifPermanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final results = await Future.wait([
      NotificationService.instance.areNotificationsEnabled(),
      NotificationService.instance.canScheduleExactAlarms(),
    ]);
    if (!mounted) return;
    setState(() {
      _notifEnabled = results[0];
      _exactEnabled = results[1];
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) return const SizedBox.shrink();

    final notifOk = _notifEnabled ?? true;
    final exactOk = _exactEnabled ?? true;
    if (notifOk && exactOk) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text("Разрешения", style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!notifOk) ...[
                _PermissionRow(
                  theme: theme,
                  icon: Icons.notifications_off_outlined,
                  title: "Уведомления отключены",
                  subtitle: _notifPermanentlyDenied
                      ? "Выдайте разрешение в настройках приложения"
                      : "Приложению нужно ваше разрешение",
                  buttonLabel: _notifPermanentlyDenied ? "Настройки" : "Разрешить",
                  onTap: () async {
                    if (_notifPermanentlyDenied) {
                      await NotificationService.instance
                          .openNotificationSettings();
                      return;
                    }
                    final granted = await NotificationService.instance
                        .requestNotificationPermission();
                    if (!granted && mounted) {
                      setState(() => _notifPermanentlyDenied = true);
                    }
                    await _refresh();
                    widget.onPermissionsChanged();
                  },
                ),
              ],
              if (!notifOk && !exactOk)
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: theme.dividerTheme.color,
                ),
              if (!exactOk) ...[
                _PermissionRow(
                  theme: theme,
                  icon: Icons.alarm_off_outlined,
                  title: "Точные будильники недоступны",
                  subtitle: "Уведомления могут приходить с задержкой",
                  buttonLabel: "Настройки",
                  onTap: () async {
                    await NotificationService.instance
                        .requestExactAlarmPermission();
                    await _refresh();
                    widget.onPermissionsChanged();
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.theme,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onTap,
  });

  final ThemeData theme;
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.error),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(buttonLabel, style: theme.textTheme.labelMedium),
          ),
        ],
      ),
    );
  }
}

class _HomeAnimatedAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _HomeAnimatedAppBar({
    required this.controller,
    required this.title,
    required this.tabIndex,
    required this.showNotificationsAction,
    required this.onNotificationsTap,
    this.browserToolbar,
  });

  final ScheduleController controller;
  final String title;
  final int tabIndex;
  final bool showNotificationsAction;
  final VoidCallback onNotificationsTap;

  /// Браузерный тулбар для вкладки «Сеть» — подменяет заголовок,
  /// оставаясь внутри того же самого AppBar.
  final Widget? browserToolbar;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final groupName = controller.selectedGroup?.name;
        return AnimatedAppBar(
          title: title,
          subtitle: (groupName != null && tabIndex != 3) ? groupName : null,
          tabIndex: tabIndex,
          titleWidget: browserToolbar,
          actions: [
            if (showNotificationsAction)
              GlassActionButton(
                icon: Icons.notifications_outlined,
                tooltip: "Уведомления",
                onTap: onNotificationsTap,
              ),
          ],
        );
      },
    );
  }
}
