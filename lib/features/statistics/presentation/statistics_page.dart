import "package:easy_refresh/easy_refresh.dart";
import "package:flutter/material.dart";
import "package:flutter_staggered_animations/flutter_staggered_animations.dart";

import "../../../app/theme.dart";
import "../../../core/widgets/animated_app_bar.dart";
import "../../../core/widgets/custom_refresh.dart";
import "../../../core/widgets/empty_state_view.dart";
import "../../schedule/domain/models.dart";
import "../../schedule/presentation/schedule_controller.dart";

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key, required this.controller});
  final ScheduleController controller;

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  bool _loaded = false;
  // Увеличивается только при первой загрузке данных — AnimationLimiter
  // пересоздаётся ровно один раз, анимации при рефреше не повторяются.
  int _listAnimKey = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoad());
  }

  void _onController() {
    if (_listAnimKey == 0 &&
        widget.controller.statistics != null &&
        mounted) {
      setState(() => _listAnimKey = 1);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    super.dispose();
  }

  void _maybeLoad() {
    if (!_loaded && widget.controller.prefs.isGroupSelected) {
      _loaded = true;
      widget.controller.loadStatistics();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final stats = widget.controller.statistics;
        final isLoading = widget.controller.isLoadingStats;
        final isTeacher = widget.controller.prefs.isTeacherMode;

        if (!widget.controller.prefs.isGroupSelected) {
          final hint = isTeacher
              ? "Выберите преподавателя в настройках"
              : "Выберите группу в настройках";
          return EmptyStateView(
            icon: Icons.bar_chart_outlined,
            message: hint,
          );
        }

        if (isLoading && stats == null) {
          return const Center(child: CircularProgressIndicator());
        }

        if (stats == null || stats.disciplines.isEmpty) {
          return CustomRefreshWrapper(
            onRefresh: widget.controller.refreshStatistics,
            color: theme.colorScheme.primary,
            appBarExtent: AnimatedAppBarVisuals.totalHeight(context),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.only(
                      top: contentTopUnderAppBar(context)),
                ),
                const HeaderLocator.sliver(),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: EmptyStateView(
                      icon: Icons.bar_chart_outlined,
                      message: "Нет данных по дисциплинам",
                      subtitle: "Потяните вниз для обновления",
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        const headerCount = 3;
        final disciplineCount = stats.disciplines.length;
        final totalItems = headerCount + disciplineCount + 1;
        final useAnim = disciplineCount <= 30;

        Widget itemBuilder(BuildContext context, int index) {
          Widget child;
          if (index == 0) {
            child = _SummaryRow(stats: stats);
          } else if (index == 1) {
            child = const SizedBox(height: 20);
          } else if (index == 2) {
            child = Text("ДИСЦИПЛИНЫ",
                style:
                    theme.textTheme.titleSmall?.copyWith(letterSpacing: 1.2));
          } else if (index < headerCount + disciplineCount) {
            final i = index - headerCount;
            child = Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DisciplineCard(
                discipline: stats.disciplines[i],
                index: i,
                isTeacherMode: isTeacher,
              ),
            );
          } else {
            child = const SizedBox(height: 40);
          }
          if (!useAnim) return child;
          return AnimationConfiguration.staggeredList(
            position: index,
            duration: const Duration(milliseconds: 250),
            child: SlideAnimation(
              verticalOffset: 20.0,
              child: FadeInAnimation(child: child),
            ),
          );
        }

        final appBarTop = contentTopUnderAppBar(context);
        final listView = CustomScrollView(
          slivers: [
            SliverPadding(padding: EdgeInsets.only(top: appBarTop)),
            const HeaderLocator.sliver(),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, contentBottomPadding(context)),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  itemBuilder,
                  childCount: totalItems,
                ),
              ),
            ),
          ],
        );

        return CustomRefreshWrapper(
          onRefresh: widget.controller.refreshStatistics,
          color: theme.colorScheme.primary,
          appBarExtent: AnimatedAppBarVisuals.totalHeight(context),
          child: useAnim
              ? AnimationLimiter(key: ValueKey(_listAnimKey), child: listView)
              : listView,
        );
      },
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.stats});
  final GroupStatistics stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        _SummaryBadge(
          value: "${stats.totalHours ?? '—'}",
          label: "Всего",
          color: theme.brightness == Brightness.light
              ? theme.colorScheme.onSurface
              : Colors.white,
          theme: theme,
        ),
        const SizedBox(width: 8),
        _SummaryBadge(
          value: "${stats.completedHours ?? '—'}",
          label: "Факт",
          color: const Color(0xFF4CAF50),
          theme: theme,
        ),
        const SizedBox(width: 8),
        _SummaryBadge(
          value: "${stats.remainingHours ?? '—'}",
          label: "Остаток",
          color: const Color(0xFFFFC107),
          theme: theme,
        ),
        const SizedBox(width: 8),
        _SummaryBadge(
          value: "${stats.plannedHours ?? '—'}",
          label: "План",
          color: const Color.fromARGB(255, 54, 143, 244),
          theme: theme,
        ),
      ],
    );
  }
}

class _SummaryBadge extends StatelessWidget {
  const _SummaryBadge({
    required this.value,
    required this.label,
    required this.color,
    required this.theme,
  });

  final String value;
  final String label;
  final Color color;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.9, end: 1.0),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        builder: (_, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: const [0.0, 0.5, 1.0],
              colors: [
                theme.cardTheme.color ?? theme.cardColor,
                (theme.cardTheme.color ?? theme.cardColor).withAlpha(242),
                (theme.cardTheme.color ?? theme.cardColor).withAlpha(228),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withAlpha(70), width: 1),
            boxShadow: theme.brightness == Brightness.light
                ? [
                    BoxShadow(
                      color: Colors.black.withAlpha(18),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisciplineCard extends StatelessWidget {
  const _DisciplineCard({
    required this.discipline,
    required this.index,
    this.isTeacherMode = false,
  });

  final DisciplineStatistics discipline;
  final int index;
  final bool isTeacherMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = _computePercent();
    final pctText = _percentText(percent);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: percent / 100),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              builder: (_, value, __) => FractionallySizedBox(
                widthFactor: value,
                alignment: Alignment.centerLeft,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      stops: const [0.0, 0.5, 1.0],
                      colors: [
                        theme.colorScheme.primary.withAlpha(26),
                        theme.colorScheme.primary.withAlpha(12),
                        theme.colorScheme.primary.withAlpha(5),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.primary.withAlpha(28),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        discipline.number.isNotEmpty
                            ? discipline.number.replaceAll(RegExp(r'\.$'), '')
                            : "${index + 1}",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            discipline.discipline.isNotEmpty
                                ? discipline.discipline
                                : "—",
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (isTeacherMode && discipline.group.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              "Группа: ${discipline.group}",
                              style: theme.textTheme.bodySmall,
                            ),
                          ] else if (!isTeacherMode &&
                              discipline.teacher.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              discipline.teacher,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          pctText,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        if (discipline.lessonType.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              color: theme.colorScheme.onSurface.withAlpha(15),
                            ),
                            child: Text(
                              discipline.lessonType,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(fontSize: 11),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _HourStat(
                        label: "Всего",
                        value: "${discipline.totalHours ?? '—'}",
                        theme: theme),
                    _HourStat(
                        label: "План",
                        value: "${discipline.plannedHours ?? '—'}",
                        theme: theme),
                    _HourStat(
                        label: "Факт",
                        value: "${discipline.factHours ?? '—'}",
                        theme: theme),
                    _HourStat(
                        label: "Остаток",
                        value: "${discipline.remainingHours ?? '—'}",
                        theme: theme),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _computePercent() {
    if (discipline.completionPercent != null &&
        discipline.completionPercent!.isNotEmpty) {
      final m = RegExp(r"(\d+)").firstMatch(discipline.completionPercent!);
      if (m != null) return int.tryParse(m.group(1)!) ?? 0;
    }
    return discipline.completionPercentInt;
  }

  String _percentText(int percent) {
    if (discipline.completionPercent != null &&
        discipline.completionPercent!.isNotEmpty) {
      final raw = discipline.completionPercent!;
      return raw.contains("%") ? raw : "$raw%";
    }
    return "$percent%";
  }
}

class _HourStat extends StatelessWidget {
  const _HourStat({
    required this.label,
    required this.value,
    required this.theme,
  });

  final String label;
  final String value;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
          const SizedBox(height: 2),
          Text(value,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
