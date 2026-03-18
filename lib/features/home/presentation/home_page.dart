import "dart:io";

import "package:animations/animations.dart";
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
import "../../notes/presentation/notes_page.dart";
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
  int _currentIndex = 0;
  bool _sheetOpen = false;
  bool _appUpdateDialogOpen = false;

  static const _titles = ["Расписание", "Итоги", "Заметки", "Настройки"];
  static const _screenIds = ["schedule", "stats", "notes", "settings"];

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.openScheduleOnTap.addListener(_onOpenScheduleRequested);
    _pages = [
      SchedulePage(
        controller: widget.controller,
        fontService: widget.fontService,
      ),
      StatisticsPage(controller: widget.controller),
      const NotesPage(),
      SettingsPage(
        controller: widget.controller,
        onThemeChanged: widget.onThemeChanged,
        fontService: widget.fontService,
      ),
    ];
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
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.openScheduleOnTap.removeListener(_onOpenScheduleRequested);
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
        _currentIndex = 0;
        _sheetOpen = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: _currentIndex == 2
          ? null
          : _HomeAnimatedAppBar(
              controller: widget.controller,
              title: _titles[_currentIndex],
              tabIndex: _currentIndex,
              showNotificationsAction: _currentIndex == 3,
              onNotificationsTap: () => _showNotificationSheet(context),
            ),
      body: PageTransitionSwitcher(
        duration: const Duration(milliseconds: 380),
        transitionBuilder: (child, animation, secondaryAnimation) {
          return SharedAxisTransition(
            animation: animation,
            secondaryAnimation: secondaryAnimation,
            transitionType: SharedAxisTransitionType.horizontal,
            child: child,
          );
        },
        child: KeyedSubtree(
          key: ValueKey(_currentIndex),
          child: RepaintBoundary(child: _pages[_currentIndex]),
        ),
      ),
      bottomNavigationBar: BottomBarWithSheet(
        selectedIndex: _currentIndex,
        onIndexChanged: (index) {
          FocusScope.of(context).unfocus();
          HapticFeedback.selectionClick();
          setState(() {
            _sheetOpen = false;
            _currentIndex = index;
          });
          AnalyticsService.instance.logScreen(_screenIds[index]);
          if (index == 1) {
            widget.controller.loadStatistics();
          }
        },
        sheetOpen: _sheetOpen,
        onSheetToggle: () {
          HapticFeedback.lightImpact();
          FocusScope.of(context).unfocus();
          setState(() => _sheetOpen = !_sheetOpen);
        },
        sheetChild: HistoryCalendarSheet(controller: widget.controller),
      ),
    );
  }

  void _showNotificationSheet(BuildContext context) {
    final theme = Theme.of(context);
    final ctrl = widget.controller;
    final prefs = ctrl.prefs;
    final bg = theme.cardTheme.color ?? theme.cardColor;
    final primary = theme.colorScheme.primary;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.6,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(40),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: ListenableBuilder(
          listenable: ctrl,
          builder: (ctx, _) => StatefulBuilder(
            builder: (ctx, setSheetState) => SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface.withAlpha(80),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: primary.withAlpha(24),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.notifications_outlined,
                            size: 22,
                            color: primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          "Уведомления",
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  _notificationSwitchTile(
                    theme,
                    setSheetState,
                    "Напоминания о парах",
                    "Приходят при открытии и обновлении расписания",
                    prefs.notificationsEnabled,
                    (v) async {
                      setSheetState(() => prefs.notificationsEnabled = v);
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
                  const SizedBox(height: 16),
                  Text(
                    "За сколько минут до пары",
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [5, 10, 15].map((m) {
                      final selected = prefs.notificationOffset == m;
                      return ChoiceChip(
                        label: Text("$m мин"),
                        selected: selected,
                        selectedColor: primary.withAlpha(48),
                        onSelected: (_) async {
                          setSheetState(() => prefs.notificationOffset = m);
                          await ctrl.syncNotificationsNow();
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) setState(() {});
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  _notificationSwitchTile(
                    theme,
                    setSheetState,
                    "Обновление расписания",
                    "Уведомлять при изменении данных",
                    prefs.notifyScheduleChanges,
                    (v) {
                      setSheetState(() => prefs.notifyScheduleChanges = v);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() {});
                      });
                    },
                  ),

                  ],
                ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _notificationSwitchTile(
    ThemeData theme,
    StateSetter setSheetState,
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyLarge),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
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

class _HomeAnimatedAppBar extends StatelessWidget implements PreferredSizeWidget {
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
