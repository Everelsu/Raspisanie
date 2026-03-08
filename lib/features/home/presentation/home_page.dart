import "dart:io";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:package_info_plus/package_info_plus.dart";

import "../../../core/notifications/notification_service.dart";
import "../../../core/services/font_service.dart";
import "../../../core/update/app_update_service.dart";
import "../../../core/update/update_dialog.dart";
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

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  bool _sheetOpen = false;

  static const _titles = ["Расписание", "Итоги", "Заметки", "Настройки"];

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    NotificationService.openScheduleOnTap.addListener(_onOpenScheduleRequested);
    _pages = [
      SchedulePage(controller: widget.controller),
      StatisticsPage(controller: widget.controller),
      const NotesPage(),
      SettingsPage(
        controller: widget.controller,
        onThemeChanged: widget.onThemeChanged,
        fontService: widget.fontService,
      ),
    ];
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(seconds: 2), () async {
          if (!mounted) return;
          final release = await checkForUpdate();
          if (!mounted || release == null) return;
          final info = await PackageInfo.fromPlatform();
          final theme = Theme.of(context);
          showDialog(
            context: context,
            builder: (ctx) => UpdateDialog(
              release: release,
              currentVersion: info.version,
              theme: theme,
            ),
          );
        });
      });
    }
  }

  @override
  void dispose() {
    NotificationService.openScheduleOnTap.removeListener(_onOpenScheduleRequested);
    super.dispose();
  }

  void _onOpenScheduleRequested() {
    if (!NotificationService.openScheduleOnTap.value || !mounted) return;
    NotificationService.openScheduleOnTap.value = false;
    setState(() {
      _currentIndex = 0;
      _sheetOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: _currentIndex == 2
          ? null
          : AppBar(
              title: ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) {
                  final groupName = widget.controller.selectedGroup?.name;
                  final title = _titles[_currentIndex];

                  if (groupName != null && _currentIndex != 3) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title),
                        Text(
                          groupName,
                          style: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
                        ),
                      ],
                    );
                  }
                  return Text(title);
                },
              ),
              actions: [
                if (_currentIndex == 3)
                  IconButton(
                    onPressed: () => _showNotificationSheet(context),
                    icon: Icon(
                      Icons.notifications_outlined,
                      color: theme.colorScheme.onSurface,
                    ),
                    tooltip: "Уведомления",
                  ),
              ],
            ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: const Interval(0.0, 1.0),
            ),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.02),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              )),
              child: child,
            ),
          );
        },
        child: KeyedSubtree(
          key: ValueKey(_currentIndex),
          child: _pages[_currentIndex],
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

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.cardTheme.color ?? theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ListenableBuilder(
        listenable: ctrl,
        builder: (ctx, _) => StatefulBuilder(
          builder: (ctx, setSheetState) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withAlpha(60),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text("Уведомления", style: theme.textTheme.titleLarge),
                  const SizedBox(height: 16),
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
                      if (mounted) setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "За сколько минут до пары",
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [5, 10, 15].map((m) {
                      final selected = prefs.notificationOffset == m;
                      return ChoiceChip(
                        label: Text("$m мин"),
                        selected: selected,
                        selectedColor: theme.colorScheme.primary.withAlpha(40),
                        onSelected: (_) async {
                          setSheetState(() => prefs.notificationOffset = m);
                          await ctrl.syncNotificationsNow();
                          if (mounted) setState(() {});
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
                      if (mounted) setState(() {});
                    },
                  ),

                ],
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
