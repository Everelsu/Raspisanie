import "dart:io";

import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:package_info_plus/package_info_plus.dart";

import "../../../core/notifications/notification_service.dart";
import "../../../core/services/analytics_service.dart";
import "../../../core/services/font_service.dart";
import "../../../core/update/app_update_service.dart";
import "../../../core/update/github_update_service.dart";
import "../../../core/update/update_dialog.dart";
import "../../../core/update/version_utils.dart";
import "../../../core/widgets/animated_app_bar.dart";
import "../../../core/widgets/bottom_bar_sheet.dart";
import "../../games/games_menu.dart";
import "../../network/presentation/network_page.dart";
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
    if (Platform.isAndroid && widget.controller.prefs.autoCheckAppUpdate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tryShowPendingBackgroundUpdate();
        Future.delayed(const Duration(seconds: 2), () {
          _checkForegroundAppUpdate();
        });
      });
    }
  }

  @override
  void dispose() {
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

  /// Собираем вкладки при каждом [build], чтобы после hot reload и обновления
  /// [HomePage] всегда передавался актуальный [ScheduleController] (кэш в
  /// [initState] давал «битые» слоты полей и null у [NetworkPage.controller]).
  List<Widget> _buildTabPages() {
    return [
      SchedulePage(
        key: const ValueKey<Object>("home_tab_schedule"),
        controller: widget.controller,
        fontService: widget.fontService,
      ),
      StatisticsPage(
        key: const ValueKey<Object>("home_tab_stats"),
        controller: widget.controller,
      ),
      NetworkPage(
        key: const ValueKey<Object>("network_browser_v2"),
        scheduleController: widget.controller,
        isActive: _currentIndex == 2,
        parentImmersiveNotifier: _networkImmersiveNotifier,
        onImmersiveChanged: (v) {
          setState(() {
            _networkImmersive = v;
            _networkImmersiveNotifier.value = v;
          });
        },
      ),
      SettingsPage(
        key: const ValueKey<Object>("home_tab_settings"),
        controller: widget.controller,
        onThemeChanged: widget.onThemeChanged,
        fontService: widget.fontService,
      ),
    ];
  }

  Future<void> _tryShowPendingBackgroundUpdate() async {
    final p = widget.controller.prefs;
    final ver = p.pendingAppUpdateVersion;
    final apk = p.pendingAppUpdateApkUrl;
    if (ver == null || apk == null || ver.isEmpty || apk.isEmpty) return;
    if (!mounted || _appUpdateDialogOpen) return;
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    if (compareVersions(info.version, ver) >= 0) {
      p.clearPendingAppUpdate();
      return;
    }
    final notes = p.pendingAppUpdateNotes;
    p.clearPendingAppUpdate();
    await _showUpdateDialog(GitHubReleaseInfo(
      version: ver,
      apkUrl: apk,
      releaseNotes: notes,
    ));
  }

  Future<void> _checkForegroundAppUpdate() async {
    if (!mounted || _appUpdateDialogOpen) return;
    final release = await checkForUpdate();
    if (!mounted || release == null) return;
    await _showUpdateDialog(release);
  }

  Future<void> _showUpdateDialog(GitHubReleaseInfo release) async {
    if (!mounted || _appUpdateDialogOpen) return;
    _appUpdateDialogOpen = true;
    try {
      final theme = Theme.of(context);
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => UpdateDialog(
          release: release,
          currentVersion: info.version,
          theme: theme,
        ),
      );
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

  double _homeBarVisibility() {
    final controller = _pageController;
    if (controller == null || !controller.hasClients) {
      return _currentIndex == 2 ? 0 : 1;
    }
    final page = controller.page ?? _currentIndex.toDouble();
    final distanceToNetwork = (page - 2).abs();
    if (distanceToNetwork >= 0.55) return 1;
    return Curves.easeOut.transform(
      (distanceToNetwork / 0.55).clamp(0.0, 1.0),
    );
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
            children: _buildTabPages()
                .map((page) => RepaintBoundary(child: page))
                .toList(),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _safePageController,
              builder: (context, _) {
                final visibility = _homeBarVisibility();
                if (visibility <= 0.001) {
                  return const SizedBox.shrink();
                }
                final offsetY = (1 - visibility) * -18;
                final scale = 0.96 + visibility * 0.04;
                return Transform.translate(
                  offset: Offset(0, offsetY),
                  child: Transform.scale(
                    scale: scale,
                    alignment: Alignment.topCenter,
                    child: Opacity(
                      opacity: visibility,
                      child: _HomeAnimatedAppBar(
                        controller: widget.controller,
                        title: _titles[_currentIndex],
                        tabIndex: _currentIndex,
                        showNotificationsAction: _currentIndex == 3,
                        onNotificationsTap: () =>
                            _showNotificationSheet(context),
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
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
                    const SizedBox(height: 12),
                    Text(
                      "Уведомления",
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      margin: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _notificationSwitchTile(
                            theme,
                            setSheetState,
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
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
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
  });

  final ScheduleController controller;
  final String title;
  final int tabIndex;
  final bool showNotificationsAction;
  final VoidCallback onNotificationsTap;

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
