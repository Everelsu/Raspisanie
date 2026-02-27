import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../../../core/notifications/notification_service.dart";
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
  });
  final ScheduleController controller;
  final VoidCallback onThemeChanged;

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
    _pages = [
      SchedulePage(controller: widget.controller),
      StatisticsPage(controller: widget.controller),
      NotesPage(controller: widget.controller),
      SettingsPage(
        controller: widget.controller,
        onThemeChanged: widget.onThemeChanged,
      ),
    ];
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
                    onPressed: () => _showNotificationSettings(context),
                    icon: Icon(Icons.notifications_outlined,
                        color: theme.colorScheme.onSurface),
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

  void _showNotificationSettings(BuildContext context) {
    final theme = Theme.of(context);
    final prefs = widget.controller.prefs;
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withAlpha(40),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text("Уведомления", style: theme.textTheme.titleLarge),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Напоминания о парах",
                              style: theme.textTheme.bodyLarge),
                          Text("Уведомление перед началом пары",
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    Switch(
                      value: prefs.notificationsEnabled,
                      onChanged: (v) {
                        setSheetState(() => prefs.notificationsEnabled = v);
                        if (!v) {
                          NotificationService().cancelAll();
                        }
                        setState(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Изменения расписания",
                              style: theme.textTheme.bodyLarge),
                          Text("Уведомлять при обновлении данных",
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    Switch(
                      value: prefs.notifyScheduleChanges,
                      onChanged: (v) {
                        setSheetState(() => prefs.notifyScheduleChanges = v);
                        setState(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Нет пар сегодня",
                              style: theme.textTheme.bodyLarge),
                          Text("Напоминать, если занятий на сегодня нет",
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    Switch(
                      value: prefs.notifyNoLessons,
                      onChanged: (v) {
                        setSheetState(() => prefs.notifyNoLessons = v);
                        setState(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text("За сколько минут", style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                Row(
                  children: [5, 10, 15, 30].map((m) {
                    final selected = prefs.notificationOffset == m;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text("$m мин"),
                        selected: selected,
                        selectedColor: theme.colorScheme.primary.withAlpha(40),
                        onSelected: (_) {
                          setSheetState(() => prefs.notificationOffset = m);
                          setState(() {});
                        },
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () => NotificationService().showTestNotification(),
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text("Тест уведомления"),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

}
