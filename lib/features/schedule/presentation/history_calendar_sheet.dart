import "package:flutter/material.dart";
import "package:table_calendar/table_calendar.dart";

import "../../../core/database/schedule_database.dart";
import "../domain/models.dart";
import "schedule_controller.dart";

class HistoryCalendarSheet extends StatefulWidget {
  const HistoryCalendarSheet({super.key, required this.controller});
  final ScheduleController controller;

  @override
  State<HistoryCalendarSheet> createState() => _HistoryCalendarSheetState();
}

class _HistoryCalendarSheetState extends State<HistoryCalendarSheet> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Set<DateTime> _markedDays = {};
  DaySchedule? _selectedSchedule;
  bool _loading = true;
  String _lastScopeKey = "";

  @override
  void initState() {
    super.initState();
    _lastScopeKey = _scopeKey();
    widget.controller.addListener(_onControllerChanged);
    _loadMarkedDays();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final nextKey = _scopeKey();
    if (nextKey == _lastScopeKey) return;
    _lastScopeKey = nextKey;
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _selectedDay = null;
        _selectedSchedule = null;
        _markedDays = {};
        _loading = true;
        _focusedDay = DateTime.now();
      });
      _loadMarkedDays();
    });
  }

  String _scopeKey() =>
      "${widget.controller.prefs.selectedGroupFile}|${widget.controller.college}";

  Future<void> _loadMarkedDays() async {
    final groupFile = widget.controller.prefs.selectedGroupFile;
    final college = widget.controller.college;
    if (groupFile.isEmpty) {
      setState(() => _loading = false);
      return;
    }

    try {
      final days = await ScheduleDatabase.instance
          .getMarkedDays(groupFile, college);
      if (mounted) {
        setState(() {
          _markedDays = days.toSet();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onDaySelected(DateTime day, DateTime focused) async {
    setState(() {
      _focusedDay = focused;
      _selectedDay = day;
    });

    final groupFile = widget.controller.prefs.selectedGroupFile;
    final college = widget.controller.college;

    final selected = await ScheduleDatabase.instance
        .getDayScheduleForDate(groupFile, college, day);
    if (!mounted) return;
    if (selected != null) {
      setState(() {
        _selectedSchedule = selected;
      });
    }
  }

  void _backToCalendar() {
    setState(() {
      _selectedSchedule = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator.adaptive(),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.history_rounded, color: primary, size: 18),
              ),
              const SizedBox(width: 10),
              Text("История расписания",
                  style: theme.textTheme.titleMedium),
              const Spacer(),
              FutureBuilder<int>(
                future: ScheduleDatabase.instance.getSnapshotCount(),
                builder: (_, snap) {
                  if (!snap.hasData) return const SizedBox.shrink();
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withAlpha(12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text("${snap.data} зап.",
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontSize: 10)),
                  );
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final slide = Tween<Offset>(
                begin: const Offset(0, 0.1),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: slide, child: child),
              );
            },
            child: _selectedSchedule == null
                ? _CalendarView(
                    key: const ValueKey("calendar"),
                    markedDays: _markedDays,
                    focusedDay: _focusedDay,
                    selectedDay: _selectedDay,
                    onDaySelected: _onDaySelected,
                    onPageChanged: (day) => setState(() => _focusedDay = day),
                  )
                : _DayOnlyView(
                    key: const ValueKey("day"),
                    day: _selectedSchedule!,
                    onBack: _backToCalendar,
                    selectedDay: _selectedDay ?? DateTime.now(),
                  ),
          ),
        ),
      ],
    );
  }
}

class _CalendarView extends StatelessWidget {
  const _CalendarView({
    super.key,
    required this.markedDays,
    required this.focusedDay,
    required this.selectedDay,
    required this.onDaySelected,
    required this.onPageChanged,
  });

  final Set<DateTime> markedDays;
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final void Function(DateTime day, DateTime focusedDay) onDaySelected;
  final ValueChanged<DateTime> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    if (markedDays.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 36, color: theme.colorScheme.onSurface.withAlpha(40)),
            const SizedBox(height: 10),
            Text("Нет сохранённых данных", style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              "Данные появятся после загрузки расписания",
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: TableCalendar(
            firstDay: DateTime(2020),
            lastDay: DateTime.now().add(const Duration(days: 365)),
            focusedDay: focusedDay,
            selectedDayPredicate: (d) => selectedDay != null && isSameDay(d, selectedDay),
            onDaySelected: onDaySelected,
            onPageChanged: onPageChanged,
            startingDayOfWeek: StartingDayOfWeek.monday,
            locale: "ru_RU",
            calendarFormat: CalendarFormat.month,
            availableCalendarFormats: const {CalendarFormat.month: ""},
            rowHeight: 40,
            daysOfWeekHeight: 30,
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: theme.textTheme.titleSmall!
                  .copyWith(fontSize: 14, color: theme.colorScheme.onSurface),
              leftChevronIcon: Icon(Icons.chevron_left, color: primary, size: 22),
              rightChevronIcon: Icon(Icons.chevron_right, color: primary, size: 22),
              headerPadding: const EdgeInsets.symmetric(vertical: 6),
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: theme.textTheme.bodySmall!
                  .copyWith(fontWeight: FontWeight.w600, fontSize: 11),
              weekendStyle: theme.textTheme.bodySmall!.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 11,
                color: theme.colorScheme.error.withAlpha(180),
              ),
            ),
            calendarStyle: CalendarStyle(
              cellMargin: const EdgeInsets.all(2),
              todayDecoration: BoxDecoration(
                color: primary.withAlpha(30),
                shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-0.7, -0.7),
                  end: Alignment(0.9, 0.9),
                  stops: const [0.0, 0.45, 1.0],
                  colors: [
                    primary,
                    primary.withAlpha(230),
                    primary.withAlpha(195),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              markerDecoration: BoxDecoration(color: primary, shape: BoxShape.circle),
              markerSize: 5,
              markersMaxCount: 1,
            ),
            eventLoader: (day) {
              final d = DateTime(day.year, day.month, day.day);
              return markedDays.contains(d) ? [true] : [];
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            "Нажмите на дату с точкой, чтобы посмотреть расписание",
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _DayOnlyView extends StatelessWidget {
  const _DayOnlyView({
    super.key,
    required this.day,
    required this.onBack,
    required this.selectedDay,
  });

  final DaySchedule day;
  final VoidCallback onBack;
  final DateTime selectedDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 700) {
          onBack();
        }
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: onBack,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  tooltip: "Назад к календарю",
                ),
                Text(
                  _formatFullDate(selectedDay),
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                _HistoryDayCard(day: day, theme: theme, primary: theme.colorScheme.primary),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatFullDate(DateTime d) {
    const months = [
      "", "января", "февраля", "марта", "апреля", "мая",
      "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"
    ];
    return "${d.day} ${months[d.month]} ${d.year}";
  }
}

class _HistoryDayCard extends StatelessWidget {
  const _HistoryDayCard({
    required this.day,
    required this.theme,
    required this.primary,
  });

  final DaySchedule day;
  final ThemeData theme;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    final items = day.items.toList()
      ..sort((a, b) => a.lessonNumber.compareTo(b.lessonNumber));
    final cardColor = theme.cardTheme.color ?? theme.cardColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: const [0.0, 0.35, 0.7, 1.0],
              colors: [
                Color.alphaBlend(primary.withAlpha(14), cardColor),
                Color.alphaBlend(primary.withAlpha(8), cardColor),
                Color.alphaBlend(primary.withAlpha(4), cardColor),
                cardColor,
              ],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _capitalize(day.day),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    day.date,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              if (items.isEmpty) ...[
                const SizedBox(height: 12),
                Text("Нет занятий",
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontStyle: FontStyle.italic)),
              ] else ...[
                const SizedBox(height: 10),
                ...items.map((item) => _LessonRow(item: item, theme: theme)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({required this.item, required this.theme});
  final ScheduleItem item;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final primary = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.onSurface.withAlpha(15),
            ),
            alignment: Alignment.center,
            child: Text(
              "${item.lessonNumber}",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.subject ?? "—",
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (_hasDetails) ...[
                  const SizedBox(height: 1),
                  Text(
                    [
                      if (item.classroom?.isNotEmpty == true) item.classroom,
                      if (item.teacher?.isNotEmpty == true) item.teacher,
                    ].join(" · "),
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          if (item.subgroup != null) ...[
            const SizedBox(width: 8),
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: primary.withAlpha(25),
              ),
              child: Text(
                "${item.subgroup} п/г",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool get _hasDetails =>
      (item.classroom?.isNotEmpty == true) ||
      (item.teacher?.isNotEmpty == true);
}
