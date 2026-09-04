import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/database/schedule_database.dart';
import '../data/holidays.dart';
import '../domain/models.dart';
import 'day_share_sheet.dart';
import 'holiday_card.dart';
import 'schedule_controller.dart';

class HistoryCalendarSheet extends StatefulWidget {
  const HistoryCalendarSheet({super.key, required this.controller});
  final ScheduleController controller;

  @override
  State<HistoryCalendarSheet> createState() => _HistoryCalendarSheetState();
}

class _HistoryCalendarSheetState extends State<HistoryCalendarSheet>
    with SingleTickerProviderStateMixin {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Set<DateTime> _markedDays = {};
  DaySchedule? _selectedSchedule;
  bool _loading = true;
  bool _loadingDay = false;
  String _lastScopeKey = '';

  // true = переходим «вперёд» (calendar→day), false = «назад» (day→calendar)
  bool _slideForward = true;

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
        _loadingDay = false;
        _focusedDay = DateTime.now();
        _slideForward = true;
      });
      _loadMarkedDays();
    });
  }

  String _scopeKey() =>
      '${widget.controller.prefs.selectedGroupFile}|${widget.controller.college}';

  Future<void> _loadMarkedDays() async {
    final groupFile = widget.controller.prefs.selectedGroupFile;
    final college = widget.controller.college;
    if (groupFile.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final days =
          await ScheduleDatabase.instance.getMarkedDays(groupFile, college);
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
    // Если день не помечен — нечего показывать
    final normalized = DateTime(day.year, day.month, day.day);
    final hasData = _markedDays.contains(normalized);

    HapticFeedback.selectionClick();
    setState(() {
      _focusedDay = focused;
      _selectedDay = day;
      _slideForward = true;
      if (hasData) {
        _loadingDay = true;
        _selectedSchedule = null;
      }
    });

    if (!hasData) return;

    final groupFile = widget.controller.prefs.selectedGroupFile;
    final college = widget.controller.college;
    final selected = await ScheduleDatabase.instance
        .getDayScheduleForDate(groupFile, college, day);
    if (!mounted) return;
    setState(() {
      _selectedSchedule = selected;
      _loadingDay = false;
    });
  }

  void _backToCalendar() {
    HapticFeedback.lightImpact();
    setState(() {
      _slideForward = false;
      _selectedSchedule = null;
      _loadingDay = false;
    });
  }

  // Перейти к следующему помеченному дню
  void _nextMarkedDay() {
    if (_selectedDay == null || _markedDays.isEmpty) return;
    final sorted = _markedDays.toList()..sort();
    final next = sorted.where((d) => d.isAfter(_selectedDay!)).firstOrNull;
    if (next == null) return;
    _onDaySelected(next, next);
  }

  // Перейти к предыдущему помеченному дню
  void _prevMarkedDay() {
    if (_selectedDay == null || _markedDays.isEmpty) return;
    final sorted = _markedDays.toList()..sort();
    final prev = sorted.where((d) => d.isBefore(_selectedDay!)).lastOrNull;
    if (prev == null) return;
    setState(() => _slideForward = false);
    _onDaySelected(prev, prev);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight;
        // Свёрнутый лист даёт ~20–40 px — тяжёлый Column даёт RenderFlex overflow
        if (h.isFinite && h < 36) {
          return const SizedBox.shrink();
        }

        if (_loading) {
          if (h.isFinite && h < 72) {
            return Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: primary,
                ),
              ),
            );
          }
          return Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(h.isFinite && h < 140 ? 12 : 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: primary,
                      ),
                    ),
                    SizedBox(height: h.isFinite && h < 100 ? 8 : 12),
                    Text(
                      'Загрузка истории…',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(120),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Column(
          children: [
            _Header(
              primary: primary,
              isDark: isDark,
              theme: theme,
              showBack: _selectedSchedule != null || _loadingDay,
              selectedDay: _selectedDay,
              onBack: _backToCalendar,
              onPrev: _selectedDay != null ? _prevMarkedDay : null,
              onNext: _selectedDay != null ? _nextMarkedDay : null,
              markedCount: _markedDays.length,
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (currentChild, previousChildren) {
                  return ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ...previousChildren,
                        if (currentChild != null) currentChild,
                      ],
                    ),
                  );
                },
                transitionBuilder: (child, anim) {
                  final offset = _slideForward
                      ? const Offset(0.08, 0)
                      : const Offset(-0.08, 0);
                  return FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: offset, end: Offset.zero)
                          .animate(anim),
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        scale: 0.985 + (anim.value * 0.015),
                        child: child,
                      ),
                    ),
                  );
                },
                child: _loadingDay
                    ? _DayLoadingSkeleton(
                        key: const ValueKey('skeleton'),
                        theme: theme,
                        primary: primary,
                      )
                    : _selectedSchedule != null
                        ? _DayView(
                            key: ValueKey('day_$_selectedDay'),
                            day: _selectedSchedule!,
                            college: widget.controller.college,
                            holiday: widget.controller.prefs.showHolidays
                                ? Holidays.forRawDate(_selectedSchedule!.date)
                                : null,
                            selectedDay: _selectedDay ?? DateTime.now(),
                            onBack: _backToCalendar,
                            primary: primary,
                            theme: theme,
                            isDark: isDark,
                            onPrev: _prevMarkedDay,
                            onNext: _nextMarkedDay,
                            hasMarkedDays: _markedDays.length > 1,
                          )
                        : _CalendarView(
                            key: const ValueKey('calendar'),
                            markedDays: _markedDays,
                            focusedDay: _focusedDay,
                            selectedDay: _selectedDay,
                            onDaySelected: _onDaySelected,
                            onPageChanged: (d) =>
                                setState(() => _focusedDay = d),
                            primary: primary,
                            theme: theme,
                            isDark: isDark,
                          ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  Шапка — адаптируется под режим (calendar / day)
// ════════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  const _Header({
    required this.primary,
    required this.isDark,
    required this.theme,
    required this.showBack,
    required this.selectedDay,
    required this.onBack,
    required this.onPrev,
    required this.onNext,
    required this.markedCount,
  });

  final Color primary;
  final bool isDark;
  final ThemeData theme;
  final bool showBack;
  final DateTime? selectedDay;
  final VoidCallback onBack;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final int markedCount;

  String _formatDate(DateTime d) {
    const months = [
      '',
      'янв',
      'фев',
      'мар',
      'апр',
      'май',
      'июн',
      'июл',
      'авг',
      'сен',
      'окт',
      'ноя',
      'дек',
    ];
    return '${d.day} ${months[d.month]}';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                primary.withAlpha(isDark ? 24 : 16),
                primary.withAlpha(isDark ? 10 : 6),
              ],
            ),
            border: Border.all(
              color: primary.withAlpha(isDark ? 34 : 22),
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: showBack
                    ? GestureDetector(
                        key: const ValueKey('back'),
                        onTap: onBack,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: primary.withAlpha(isDark ? 34 : 22),
                            border: Border.all(
                              color: primary.withAlpha(isDark ? 50 : 34),
                              width: 0.8,
                            ),
                          ),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: primary,
                            size: 20,
                          ),
                        ),
                      )
                    : Container(
                        key: const ValueKey('icon'),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: primary.withAlpha(isDark ? 28 : 18),
                        ),
                        child: Icon(
                          Icons.history_rounded,
                          color: primary,
                          size: 18,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: showBack && selectedDay != null
                      ? Column(
                          key: ValueKey('date_$selectedDay'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatDate(selectedDay!),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Сохранённый день',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color:
                                    theme.colorScheme.onSurface.withAlpha(120),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          key: const ValueKey('title'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'История',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              if (showBack) ...[
                _NavBtn(
                  icon: Icons.chevron_left,
                  onTap: onPrev,
                  primary: primary,
                  isDark: isDark,
                ),
                const SizedBox(width: 4),
                _NavBtn(
                  icon: Icons.chevron_right,
                  onTap: onNext,
                  primary: primary,
                  isDark: isDark,
                ),
              ] else if (markedCount > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: primary.withAlpha(isDark ? 28 : 18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: primary.withAlpha(isDark ? 40 : 26),
                      width: 0.7,
                    ),
                  ),
                  child: Text(
                    '$markedCount дн.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  const _NavBtn({
    required this.icon,
    required this.onTap,
    required this.primary,
    required this.isDark,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final Color primary;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final active = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? primary.withAlpha(isDark ? 30 : 18)
              : primary.withAlpha(isDark ? 10 : 6),
          border: Border.all(
            color: active
                ? primary.withAlpha(isDark ? 45 : 30)
                : primary.withAlpha(isDark ? 15 : 10),
            width: 0.8,
          ),
        ),
        child: Icon(
          icon,
          color: active ? primary : primary.withAlpha(60),
          size: 18,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  Календарь
// ════════════════════════════════════════════════════════════════

class _CalendarView extends StatelessWidget {
  const _CalendarView({
    super.key,
    required this.markedDays,
    required this.focusedDay,
    required this.selectedDay,
    required this.onDaySelected,
    required this.onPageChanged,
    required this.primary,
    required this.theme,
    required this.isDark,
  });

  final Set<DateTime> markedDays;
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final void Function(DateTime, DateTime) onDaySelected;
  final ValueChanged<DateTime> onPageChanged;
  final Color primary;
  final ThemeData theme;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (markedDays.isEmpty) {
      final empty = Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              primary.withAlpha(isDark ? 18 : 10),
              primary.withAlpha(isDark ? 8 : 4),
            ],
          ),
          border: Border.all(
            color: primary.withAlpha(isDark ? 30 : 18),
            width: 0.8,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primary.withAlpha(isDark ? 25 : 15),
                border: Border.all(
                  color: primary.withAlpha(isDark ? 35 : 22),
                  width: 0.8,
                ),
              ),
              child: Icon(
                Icons.history_toggle_off_rounded,
                size: 24,
                color: primary.withAlpha(150),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'История пока пуста',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'После первой загрузки расписания сохранённые дни появятся здесь автоматически.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withAlpha(120),
                height: 1.35,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
      return LayoutBuilder(
        builder: (context, c) {
          if (c.maxHeight.isFinite && c.maxHeight < 220) {
            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: empty,
            );
          }
          return Center(child: SingleChildScrollView(child: empty));
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxHeight;
        const hintBlockH = 56.0;
        const calHeaderH = 32.0;
        const dowH = 24.0;
        final availForGrid =
            (available - hintBlockH - 28).clamp(0.0, double.infinity);
        final rowH = ((availForGrid - calHeaderH - dowH) / 6).clamp(32.0, 44.0);
        final gridH = calHeaderH + dowH + 6 * rowH;
        final calendarBox = SizedBox(
          height: gridH,
          child: TableCalendar(
            firstDay: DateTime(2020),
            lastDay: DateTime.now().add(const Duration(days: 365)),
            focusedDay: focusedDay,
            selectedDayPredicate: (d) =>
                selectedDay != null && isSameDay(d, selectedDay),
            onDaySelected: onDaySelected,
            onPageChanged: onPageChanged,
            startingDayOfWeek: StartingDayOfWeek.monday,
            locale: 'ru_RU',
            calendarFormat: CalendarFormat.month,
            availableCalendarFormats: const {CalendarFormat.month: ''},
            rowHeight: rowH,
            daysOfWeekHeight: dowH,
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: theme.textTheme.titleSmall!.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
              leftChevronIcon: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primary.withAlpha(isDark ? 28 : 18),
                ),
                child: Icon(Icons.chevron_left, color: primary, size: 16),
              ),
              rightChevronIcon: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primary.withAlpha(isDark ? 28 : 18),
                ),
                child: Icon(Icons.chevron_right, color: primary, size: 16),
              ),
              headerPadding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
              leftChevronPadding: EdgeInsets.zero,
              rightChevronPadding: EdgeInsets.zero,
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: theme.textTheme.bodySmall!.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 10,
                color: theme.colorScheme.onSurface.withAlpha(160),
              ),
              weekendStyle: theme.textTheme.bodySmall!.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 10,
                color: theme.colorScheme.error.withAlpha(180),
              ),
            ),
            calendarStyle: CalendarStyle(
              cellMargin: const EdgeInsets.all(1.5),
              outsideDaysVisible: false,

              // Сегодня
              todayDecoration: BoxDecoration(
                color: primary.withAlpha(isDark ? 35 : 25),
                shape: BoxShape.circle,
              ),
              todayTextStyle: TextStyle(
                color: primary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),

              // Выбранный день
              selectedDecoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: const Alignment(-0.6, -0.6),
                  end: const Alignment(0.8, 0.8),
                  colors: [
                    Color.alphaBlend(Colors.white.withAlpha(30), primary),
                    primary,
                    Color.alphaBlend(Colors.black.withAlpha(20), primary),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              selectedTextStyle: TextStyle(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),

              // Маркер (есть данные)
              markerDecoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primary, primary.withAlpha(200)],
                ),
                shape: BoxShape.circle,
              ),
              markerSize: 4.0,
              markersMaxCount: 1,
              markerMargin: const EdgeInsets.only(top: 0),

              // Обычные дни
              defaultTextStyle: theme.textTheme.bodySmall!.copyWith(
                fontSize: 12,
              ),
              weekendTextStyle: theme.textTheme.bodySmall!.copyWith(
                fontSize: 12,
                color: theme.colorScheme.error.withAlpha(200),
              ),
              disabledTextStyle: theme.textTheme.bodySmall!.copyWith(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withAlpha(50),
              ),
            ),
            eventLoader: (day) {
              final d = DateTime(day.year, day.month, day.day);
              return markedDays.contains(d) ? [true] : [];
            },
          ),
        );
        final body = Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    begin: const Alignment(-0.8, -1.0),
                    end: const Alignment(0.9, 1.0),
                    colors: [
                      primary.withAlpha(isDark ? 20 : 12),
                      primary.withAlpha(isDark ? 8 : 4),
                    ],
                  ),
                  border: Border.all(
                    color: primary.withAlpha(isDark ? 28 : 18),
                    width: 0.8,
                  ),
                ),
                child: calendarBox,
              ),
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: theme.colorScheme.onSurface.withAlpha(isDark ? 12 : 6),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [primary, primary.withAlpha(200)],
                        ),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        'Точка означает сохранённый день. Нажмите на дату.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          color: theme.colorScheme.onSurface.withAlpha(115),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

        if (available < gridH + hintBlockH + 28) {
          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: body,
          );
        }
        return Align(
          alignment: Alignment.topCenter,
          child: body,
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  Скелетон-загрузка дня
// ════════════════════════════════════════════════════════════════

class _DayLoadingSkeleton extends StatefulWidget {
  const _DayLoadingSkeleton(
      {super.key, required this.theme, required this.primary});
  final ThemeData theme;
  final Color primary;

  @override
  State<_DayLoadingSkeleton> createState() => _DayLoadingSkeletonState();
}

class _DayLoadingSkeletonState extends State<_DayLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final opacity = 0.3 + _anim.value * 0.4;
        final body = Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
                4,
                (i) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: widget.primary.withValues(
                                  alpha: widget.primary.a * opacity * 0.5),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  height: 13,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: widget.theme.colorScheme.onSurface
                                        .withValues(
                                      alpha:
                                          widget.theme.colorScheme.onSurface.a *
                                              opacity *
                                              0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  height: 10,
                                  width: 120,
                                  decoration: BoxDecoration(
                                    color: widget.theme.colorScheme.onSurface
                                        .withValues(
                                      alpha:
                                          widget.theme.colorScheme.onSurface.a *
                                              opacity *
                                              0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )),
          ),
        );
        return LayoutBuilder(
          builder: (context, c) {
            if (c.maxHeight.isFinite && c.maxHeight < 260) {
              return SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: body,
              );
            }
            return body;
          },
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  Вид конкретного дня
// ════════════════════════════════════════════════════════════════

class _DayView extends StatelessWidget {
  const _DayView({
    super.key,
    required this.day,
    required this.college,
    required this.holiday,
    required this.selectedDay,
    required this.onBack,
    required this.primary,
    required this.theme,
    required this.isDark,
    required this.onPrev,
    required this.onNext,
    required this.hasMarkedDays,
  });

  final DaySchedule day;
  final String college;
  final Holiday? holiday;
  final DateTime selectedDay;
  final VoidCallback onBack;
  final Color primary;
  final ThemeData theme;
  final bool isDark;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final bool hasMarkedDays;

  @override
  Widget build(BuildContext context) {
    final items = day.items.toList()
      ..sort((a, b) => a.lessonNumber.compareTo(b.lessonNumber));

    // Праздничный день красим целиком — как на основном расписании.
    final accent = holiday == null ? primary : Color(holiday!.color);
    final dayTheme = holiday == null
        ? theme
        : theme.copyWith(
            colorScheme: theme.colorScheme.copyWith(primary: accent),
          );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 600) onBack();
      },
      onHorizontalDragEnd: (d) {
        if (!hasMarkedDays) return;
        final v = d.primaryVelocity ?? 0;
        // Свайп влево (отриц. velocity) → следующий день, вправо → предыдущий
        if (v < -380) {
          HapticFeedback.selectionClick();
          onNext();
        } else if (v > 380) {
          HapticFeedback.selectionClick();
          onPrev();
        }
      },
      child: ListView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        children: [
          // В пустой день карточки дня нет — праздник показываем сам по себе.
          if (items.isEmpty) ...[
            if (holiday != null) HolidayCard(holiday!),
            _EmptyDay(primary: accent, theme: dayTheme, isDark: isDark),
          ] else
            _DayCard(
              day: day,
              college: college,
              holiday: holiday,
              items: items,
              primary: accent,
              theme: dayTheme,
              isDark: isDark,
            ),
        ],
      ),
    );
  }
}

String _formatHistoryDayAsText(DaySchedule day) {
  final items = day.items.toList()
    ..sort((a, b) {
      final byLesson = a.lessonNumber.compareTo(b.lessonNumber);
      if (byLesson != 0) return byLesson;
      return (a.subgroup ?? 0).compareTo(b.subgroup ?? 0);
    });

  final lines = <String>[
    '${_capitalizeHistory(day.day)}, ${day.date}',
    '',
  ];

  if (items.isEmpty) {
    lines.add('Нет занятий');
    return lines.join('\n');
  }

  for (final item in items) {
    final parts = <String>[
      '${item.lessonNumber}. ${item.subject ?? '—'}',
    ];
    if (item.teacher != null && item.teacher!.trim().isNotEmpty) {
      parts.add(item.teacher!.trim());
    }
    if (item.classroom != null && item.classroom!.trim().isNotEmpty) {
      parts.add('каб. ${item.classroom!.trim()}');
    }
    if (item.subgroup != null) {
      parts.add('подгр. ${item.subgroup}');
    }
    lines.add(parts.join(' • '));
  }

  return lines.join('\n');
}

String _capitalizeHistory(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

// ── Пустой день ──────────────────────────────────────────────────────────────

class _EmptyDay extends StatelessWidget {
  const _EmptyDay({
    required this.primary,
    required this.theme,
    required this.isDark,
  });
  final Color primary;
  final ThemeData theme;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primary.withAlpha(isDark ? 18 : 12),
            primary.withAlpha(isDark ? 8 : 5),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: primary.withAlpha(isDark ? 28 : 18),
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          Icon(Icons.event_available_outlined,
              size: 32, color: primary.withAlpha(140)),
          const SizedBox(height: 10),
          Text(
            'Нет занятий',
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'В этот день пары не запланированы',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(110),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Карточка дня с парами ────────────────────────────────────────────────────

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.day,
    required this.college,
    required this.holiday,
    required this.items,
    required this.primary,
    required this.theme,
    required this.isDark,
  });

  final DaySchedule day;
  final String college;
  final Holiday? holiday;
  final List<ScheduleItem> items;
  final Color primary;
  final ThemeData theme;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final cardColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    // Обычный день — едва заметная подложка; праздничный заливаем заметно.
    int tint(int base) =>
        holiday == null ? base : (base * 2.4).round().clamp(0, 255);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onLongPress: () => showDayShareSheet(
          context,
          day: day,
          college: college,
          shareText: _formatHistoryDayAsText(day),
          subtitle: "Сохранённый день",
        ),
        child: Container(
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: const Alignment(-0.7, -0.8),
              end: const Alignment(1.0, 1.0),
              stops: const [0.0, 0.35, 0.75, 1.0],
              colors: [
                Color.alphaBlend(
                    primary.withAlpha(tint(isDark ? 42 : 28)), cardColor),
                Color.alphaBlend(
                    primary.withAlpha(tint(isDark ? 22 : 14)), cardColor),
                Color.alphaBlend(
                    primary.withAlpha(tint(isDark ? 10 : 6)), cardColor),
                cardColor,
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: primary.withAlpha(tint(isDark ? 35 : 22)),
              width: 0.8,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Заголовок карточки
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 18,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [primary, primary.withAlpha(140)],
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _capitalize(day.day),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      day.date,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(130),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            primary.withAlpha(isDark ? 38 : 26),
                            primary.withAlpha(isDark ? 22 : 14),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: primary.withAlpha(isDark ? 45 : 30),
                            width: 0.7),
                      ),
                      child: Text(
                        '${items.map((item) => item.lessonNumber).toSet().length} ${_lessonsWord(items.map((item) => item.lessonNumber).toSet().length)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Разделитель
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Container(
                  height: 0.6,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        primary.withAlpha(0),
                        primary.withAlpha(isDark ? 45 : 30),
                        primary.withAlpha(isDark ? 45 : 30),
                        primary.withAlpha(0),
                      ],
                      stops: const [0.0, 0.15, 0.85, 1.0],
                    ),
                  ),
                ),
              ),

              if (holiday != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                  child: HolidayCard(holiday!),
                ),

              // Список пар (как на основном расписании: одна цифра — несколько подгрупп)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                child: Column(
                  children: _groupItemsByLesson(items)
                      .map(
                        (e) => _HistoryLessonGroup(
                          lessonNumber: e.key,
                          lessonItems: e.value,
                          theme: theme,
                          primary: primary,
                          isDark: isDark,
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _lessonsWord(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'пара';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) {
      return 'пары';
    }
    return 'пар';
  }
}

List<MapEntry<int, List<ScheduleItem>>> _groupItemsByLesson(
    List<ScheduleItem> items) {
  final sorted = items.toList()
    ..sort((a, b) {
      final c = a.lessonNumber.compareTo(b.lessonNumber);
      if (c != 0) return c;
      return (a.subgroup ?? 0).compareTo(b.subgroup ?? 0);
    });
  final map = <int, List<ScheduleItem>>{};
  for (final i in sorted) {
    map.putIfAbsent(i.lessonNumber, () => []).add(i);
  }
  return map.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
}

/// Один номер пары: как в schedule_page — несколько строк с чипами п/г.
class _HistoryLessonGroup extends StatelessWidget {
  const _HistoryLessonGroup({
    required this.lessonNumber,
    required this.lessonItems,
    required this.theme,
    required this.primary,
    required this.isDark,
  });

  final int lessonNumber;
  final List<ScheduleItem> lessonItems;
  final ThemeData theme;
  final Color primary;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final hasMultiple = lessonItems.length > 1;
    final hasAnySub = lessonItems.any((i) => i.subgroup != null);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  primary.withAlpha(isDark ? 50 : 36),
                  primary.withAlpha(isDark ? 30 : 20),
                ],
              ),
              border: Border.all(
                color: primary.withAlpha(isDark ? 55 : 38),
                width: 0.7,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              '$lessonNumber',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: !hasMultiple && !hasAnySub
                ? _historySingleSlot(lessonItems.first)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: lessonItems
                        .map((item) => _historySubgroupSlot(item))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _historySingleSlot(ScheduleItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.subject ?? '—',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
        if (_hasDetails(item)) ...[
          const SizedBox(height: 2),
          _detailsRow(item),
        ],
      ],
    );
  }

  Widget _historySubgroupSlot(ScheduleItem item) {
    final sg = item.subgroup;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.subject ?? '—',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                if (_hasDetails(item)) ...[
                  const SizedBox(height: 2),
                  _detailsRow(item),
                ],
              ],
            ),
          ),
          if (sg != null) ...[
            const SizedBox(width: 8),
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: primary.withAlpha(isDark ? 40 : 25),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.groups_outlined,
                    size: 13,
                    color: primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$sg п/г',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _hasDetails(ScheduleItem item) =>
      (item.classroom?.isNotEmpty == true) ||
      (item.teacher?.isNotEmpty == true);

  Widget _detailsRow(ScheduleItem item) {
    return Row(
      children: [
        if (item.classroom?.isNotEmpty == true) ...[
          Icon(
            Icons.meeting_room_outlined,
            size: 11,
            color: theme.colorScheme.onSurface.withAlpha(120),
          ),
          const SizedBox(width: 3),
          Text(
            item.classroom!,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withAlpha(150),
            ),
          ),
        ],
        if (item.classroom?.isNotEmpty == true &&
            item.teacher?.isNotEmpty == true)
          Text(
            ' · ',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withAlpha(80),
            ),
          ),
        if (item.teacher?.isNotEmpty == true) ...[
          Icon(
            Icons.person_outline_rounded,
            size: 11,
            color: theme.colorScheme.onSurface.withAlpha(120),
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              item.teacher!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withAlpha(150),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
