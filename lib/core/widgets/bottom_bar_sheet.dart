import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../motion.dart';
import 'glass.dart';
import 'pressable.dart';

/// Нижний бар в духе Liquid Glass (iOS 26): стеклянная капсула вкладок;
/// выбранное «Расписание» раздаётся и «разделяет» линзу на две половинки —
/// вторая открывает календарь (HistoryCalendarSheet), выезжающий над баром.
///
/// Выбранную вкладку отмечает «линза»: едет на пружине ([AppMotion]),
/// тянется по скорости, а по бару можно вести пальцем — линза идёт за
/// ним, цвет иконок перетекает, на отпускании защёлкивается на ближайшей.
class BottomBarWithSheet extends StatefulWidget {
  const BottomBarWithSheet({
    super.key,
    required this.selectedIndex,
    required this.onIndexChanged,
    required this.sheetChild,
    this.onSheetToggle,
    this.onSheetClosedByDrag,
    required this.sheetOpen,
    this.onNavItemLongPress,
  });

  final int selectedIndex;
  final ValueChanged<int> onIndexChanged;
  final Widget sheetChild;
  final VoidCallback? onSheetToggle;

  /// Вызывается когда шторка закрыта свайпом — всегда означает «закрыть»,
  /// в отличие от [onSheetToggle] (toggle). Это предотвращает гонку состояний
  /// когда пользователь успевает нажать кнопку до перерисовки.
  final VoidCallback? onSheetClosedByDrag;
  final bool sheetOpen;

  /// Длинное нажатие на вкладку с индексом [i]. Используется для скрытых фич.
  final void Function(int i)? onNavItemLongPress;

  static const double barHeight = 64.0;

  /// Отступ бара от нижнего края (над safe area).
  static const double bottomGap = 10.0;

  @override
  State<BottomBarWithSheet> createState() => _BottomBarWithSheetState();
}

class _BottomBarWithSheetState extends State<BottomBarWithSheet>
    with TickerProviderStateMixin {
  // ─── Константы ──────────────────────────────────────────────────────────────
  static const _sheetMax = 420.0;
  static const _barH = BottomBarWithSheet.barHeight;
  static const _closeSnapThreshold = 0.55;

  // Горизонтальный отступ — одинаковый для бара и шторки
  static const _hPad = 12.0;
  static const _bPad = BottomBarWithSheet.bottomGap;
  // Зазор между шторкой и баром и между капсулой и кнопкой
  static const _gap = 8.0;
  static const _sheetRadius = 30.0;
  static const _lensInset = 4.0;
  // Ширина календарной половинки «Расписания».
  static const _calW = 42.0;

  static const _items = <(IconData, IconData, String)>[
    (Icons.calendar_today_outlined, Icons.calendar_today, 'Расписание'),
    (Icons.bar_chart_outlined, Icons.bar_chart, 'Итоги'),
    (Icons.language_outlined, Icons.language, 'Сеть'),
    (Icons.settings_outlined, Icons.settings, 'Настройки'),
  ];

  /// 0 — шторка закрыта, 1 — открыта.
  late final AnimationController _sheet;

  /// Позиция линзы в «индексах вкладок»; без границ — пружине нужен
  /// перелёт за цель.
  late final AnimationController _pill;

  /// 0..1 — линза «приподнята» (палец ведёт её по бару).
  late final AnimationController _lift;
  bool _closingByDrag = false;
  double _releaseVelocity = 0;
  // Флаг, а не `_lift.value == 0`: пружина гаснет не ровно в ноль, и после
  // первого перетаскивания линза переставала анимироваться совсем.
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _sheet =
        AnimationController(vsync: this, value: widget.sheetOpen ? 1.0 : 0.0);
    _pill = AnimationController.unbounded(
        vsync: this, value: widget.selectedIndex.toDouble());
    _lift = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(BottomBarWithSheet old) {
    super.didUpdateWidget(old);
    if (widget.sheetOpen != old.sheetOpen) {
      _springTo(
          _sheet, widget.sheetOpen ? 1 : 0, AppMotion.smooth, _releaseVelocity);
      _releaseVelocity = 0;
    }
    if (widget.selectedIndex != old.selectedIndex && !_dragging) {
      _springTo(_pill, widget.selectedIndex.toDouble(), AppMotion.snappy,
          _pill.velocity);
    }
  }

  @override
  void dispose() {
    _sheet.dispose();
    _pill.dispose();
    _lift.dispose();
    super.dispose();
  }

  void _springTo(AnimationController c, double target, SpringDescription spring,
      [double velocity = 0]) {
    if (AppMotion.reduced(context)) {
      c.value = target;
      return;
    }
    c.animateWith(SpringSimulation(spring, c.value, target, velocity));
  }

  double _effectiveBarHeight(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    if (scale <= 1.15) return _barH;
    return (_barH + 8).clamp(_barH, _barH + 14).toDouble();
  }

  // ─── Перетаскивание линзы ───────────────────────────────────────────────────

  void _dragStart() {
    _dragging = true;
    _pill.stop();
    _springTo(_lift, 1, AppMotion.smooth);
  }

  void _dragUpdate(DragUpdateDetails d, double itemW) {
    _pill.value = (_pill.value + d.delta.dx / itemW).clamp(-0.25, 3.25);
  }

  void _dragEnd(DragEndDetails d, double itemW) {
    final v = d.velocity.pixelsPerSecond.dx / itemW;
    // Короткий бросок досылает линзу на соседнюю вкладку, как в iOS.
    final target =
        (_pill.value + (v * 0.08).clamp(-0.5, 0.5)).round().clamp(0, 3);
    _dragging = false;
    _springTo(_lift, 0, AppMotion.smooth);
    _springTo(_pill, target.toDouble(), AppMotion.snappy, v);
    if (target != widget.selectedIndex) widget.onIndexChanged(target);
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final barH = _effectiveBarHeight(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_hPad, 0, _hPad, _bPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: _buildSheet(theme, isDark, barH)),
            const SizedBox(height: _gap),
            SizedBox(
              height: barH,
              child: RepaintBoundary(
                child: _buildCapsule(theme, barH, isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Sheet ──────────────────────────────────────────────────────────────────

  Widget _buildSheet(ThemeData theme, bool isDark, double barH) {
    final cs = theme.colorScheme;
    final screenH = MediaQuery.sizeOf(context).height;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final availableH =
        math.max(0.0, screenH - barH - safeBottom - _gap - _bPad);
    final maxSheet = math.min(_sheetMax, availableH * 0.78);
    final radius = BorderRadius.circular(_sheetRadius);
    // Шторка большая и анимируется — без размытия (дорого на всю площадь),
    // почти непрозрачная, в той же гамме, что стекло бара.
    final navBg = theme.navigationBarTheme.backgroundColor ?? cs.surface;
    final decoration = ShapeDecoration(
      color: Color.alphaBlend(
        cs.primary.withAlpha(isDark ? 14 : 8),
        navBg.withAlpha(isDark ? 246 : 250),
      ),
      shape: RoundedSuperellipseBorder(
        borderRadius: radius,
        side: BorderSide(
          color:
              isDark ? Colors.white.withAlpha(30) : Colors.black.withAlpha(14),
          width: 0.8,
        ),
      ),
      shadows: [
        BoxShadow(
          color: Colors.black.withAlpha(isDark ? 70 : 26),
          blurRadius: 26,
          spreadRadius: -6,
          offset: const Offset(0, 10),
        ),
      ],
    );

    return AnimatedBuilder(
      animation: _sheet,
      child: RepaintBoundary(child: widget.sheetChild),
      builder: (context, child) {
        final h = _sheet.value * maxSheet;
        // Закрытая шторка не выбрасывается, а уходит в Offstage (тикеры
        // выключены): иначе каждое открытие заново строило календарь и
        // ходило в SQLite прямо в первых кадрах анимации.
        return Visibility(
          visible: h >= 1,
          maintainState: true,
          child: SizedBox(
            height: h,
            width: double.infinity,
            child: DecoratedBox(
              decoration: decoration,
              child: ClipRSuperellipse(
                borderRadius: radius,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragStart: (_) {},
                  onVerticalDragUpdate: (d) {
                    if (!widget.sheetOpen) return;
                    _sheet.value =
                        (_sheet.value - d.delta.dy / maxSheet).clamp(0.0, 1.0);
                  },
                  onVerticalDragEnd: (d) {
                    if (!widget.sheetOpen) return;
                    // px/с вниз → «долей шторки»/с вверх, для пружины.
                    final v = d.primaryVelocity ?? 0;
                    final velocity = -v / maxSheet;
                    if (_sheet.value < _closeSnapThreshold || v > 700) {
                      if (!_closingByDrag) {
                        _releaseVelocity = velocity;
                        _triggerDragClose();
                      }
                      return;
                    }
                    _springTo(_sheet, 1, AppMotion.smooth, velocity);
                  },
                  // OverflowBox держит контент на полной высоте шторки: при
                  // анимации меняется только клип, календарь не перелэйаутится
                  // каждый кадр. Контент «выезжает» из-за бара вместе с краем.
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: maxSheet,
                    maxHeight: maxSheet,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 10, bottom: 6),
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: cs.onSurface.withAlpha(45),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        Expanded(child: child!),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _triggerDragClose() {
    _closingByDrag = true;
    // Используем явный колбэк «закрыть» вместо toggle-колбэка,
    // чтобы избежать гонки: если пользователь нажмёт кнопку до перерисовки,
    // два вызова toggle аннулировали бы друг друга → шторка не открывалась.
    (widget.onSheetClosedByDrag ?? widget.onSheetToggle)?.call();
    Future<void>.delayed(
        const Duration(milliseconds: 250), () => _closingByDrag = false);
  }

  // ─── Капсула вкладок ────────────────────────────────────────────────────────

  /// Слоты вкладок для «насколько линза на Расписании» [v]: «Расписание»
  /// раздаётся на [_calW] × v под календарную половинку, остальные
  /// поровну поджимаются. Возвращает (x, ширина) каждого слота.
  List<(double, double)> _slots(double inner, double v) {
    final b = inner / 4;
    final extra = _calW * v;
    final w0 = b + extra;
    final wo = b - extra / 3;
    return [(0, w0), (w0, wo), (w0 + wo, wo), (w0 + 2 * wo, wo)];
  }

  Widget _buildCapsule(ThemeData theme, double barH, bool isDark) {
    final cs = theme.colorScheme;
    final unselected = theme.navigationBarTheme.iconTheme?.resolve({})?.color ??
        cs.onSurfaceVariant;
    return Glass(
      radius: BorderRadius.circular(barH / 2),
      child: LayoutBuilder(builder: (context, c) {
        final inner = c.maxWidth - _lensInset * 2;
        final baseW = inner / 4;
        return GestureDetector(
          // Линза идёт за пальцем с момента касания, а не с точки, где
          // жест выиграл арену (иначе отставала на ширину touch slop).
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragStart: (_) => _dragStart(),
          onHorizontalDragUpdate: (d) => _dragUpdate(d, baseW),
          onHorizontalDragEnd: (d) => _dragEnd(d, baseW),
          onHorizontalDragCancel: () => _dragEnd(DragEndDetails(), baseW),
          child: AnimatedBuilder(
            animation: Listenable.merge([_pill, _lift, _sheet]),
            builder: (context, _) {
              final t = _pill.value;
              // Насколько «Расписание» раскрыто под календарь: следом за
              // линзой (и за пальцем), а при открытой шторке — полностью.
              final v = math.max(
                _sheet.value,
                Curves.easeOutCubic.transform((1 - t).clamp(0.0, 1.0)),
              );
              final slots = _slots(inner, v);
              return Stack(
                fit: StackFit.expand,
                children: [
                  _lens(cs.primary, slots, t, baseW, inner, barH, isDark),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _lensInset),
                    child: Row(
                      children: [
                        for (var i = 0; i < 4; i++)
                          SizedBox(
                            width: slots[i].$2,
                            child: i == 0
                                ? _scheduleSlot(cs, unselected, t, v)
                                : _navItem(i, cs, unselected, t),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      }),
    );
  }

  Widget _navItem(int i, ColorScheme cs, Color unselected, double t,
      {VoidCallback? onTap}) {
    return _NavItem(
      item: _items[i],
      selected: widget.selectedIndex == i,
      // Цвет тянется за линзой, а не за индексом.
      tint: (1 - (t - i).abs()).clamp(0.0, 1.0),
      primary: cs.primary,
      unselected: unselected,
      onTap: onTap ?? () => widget.onIndexChanged(i),
      onLongPress: widget.onNavItemLongPress == null
          ? null
          : () {
              HapticFeedback.mediumImpact();
              widget.onNavItemLongPress!(i);
            },
    );
  }

  /// «Расписание» + календарная половинка за тонкой перегородкой.
  /// Повторный тап по уже выбранному «Расписанию» тоже открывает календарь.
  Widget _scheduleSlot(ColorScheme cs, Color unselected, double t, double v) {
    final main = _navItem(
      0,
      cs,
      unselected,
      t,
      onTap: () {
        if (widget.selectedIndex == 0) {
          widget.onSheetToggle?.call();
        } else {
          widget.onIndexChanged(0);
        }
      },
    );
    if (v < 0.02) return main;
    final s = _sheet.value.clamp(0.0, 1.0);
    final iconColor = Color.lerp(cs.primary, cs.onPrimary, s)!;
    return Row(
      children: [
        Expanded(child: main),
        SizedBox(
          width: _calW * v,
          child: Opacity(
            opacity: v.clamp(0.0, 1.0),
            child: Semantics(
              label:
                  widget.sheetOpen ? 'Закрыть календарь' : 'Открыть календарь',
              button: true,
              excludeSemantics: true,
              child: Pressable(
                scale: 0.84,
                onTap: () => widget.onSheetToggle?.call(),
                child: Row(
                  children: [
                    // Перегородка — линза «разделяется» на две половинки.
                    Container(
                      width: 1,
                      height: 24,
                      color: cs.primary.withAlpha((70 * (1 - s)).round()),
                    ),
                    Expanded(
                      child: Center(
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: ShapeDecoration(
                            color: cs.primary.withValues(alpha: s),
                            shape: const CircleBorder(),
                          ),
                          // Иконки перетекают вслед за шторкой (и за пальцем,
                          // когда её тянут): четверть оборота + прозрачность.
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Transform.rotate(
                                angle: s * math.pi / 2,
                                child: Icon(Icons.calendar_month_rounded,
                                    size: 19,
                                    color: iconColor.withValues(alpha: 1 - s)),
                              ),
                              Transform.rotate(
                                angle: (s - 1) * math.pi / 2,
                                child: Icon(Icons.close_rounded,
                                    size: 19,
                                    color: iconColor.withValues(alpha: s)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Линза под выбранной вкладкой: между слотами её край и ширина
  /// интерполируются, тянется по скорости и «приподнимается» под пальцем.
  Widget _lens(Color primary, List<(double, double)> slots, double t,
      double baseW, double inner, double barH, bool isDark) {
    final i = t.floor().clamp(0, 3);
    final f = t - i;
    final double left;
    final double w;
    if (t < 0) {
      left = t * baseW;
      w = slots[0].$2;
    } else if (i >= 3) {
      left = slots[3].$1 + f * baseW;
      w = slots[3].$2;
    } else {
      left = slots[i].$1 + (slots[i + 1].$1 - slots[i].$1) * f;
      w = slots[i].$2 + (slots[i + 1].$2 - slots[i].$2) * f;
    }
    final x = _lensInset + left.clamp(0.0, inner - w);
    final h = barH - _lensInset * 2;
    final stretch = (_pill.velocity.abs() * 0.03).clamp(0.0, 0.2);
    final lift = _lift.value;
    final sx = 1 + stretch + lift * 0.1;
    final sy = 1 - stretch * 0.3 + lift * 0.14;
    return Positioned(
      left: 0,
      top: _lensInset,
      width: w,
      height: h,
      child: Transform(
        transform: Matrix4.translationValues(x, 0, 0)
          ..scaleByDouble(sx, sy, 1, 1),
        alignment: Alignment.center,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              // Линза в цвет акцента темы; под пальцем — чуть ярче.
              colors: [
                primary.withAlpha((isDark ? 56 : 40) + (lift * 18).round()),
                primary.withAlpha((isDark ? 30 : 20) + (lift * 12).round()),
              ],
            ),
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(h / 2),
              side: BorderSide(
                color: primary.withAlpha(isDark ? 70 : 50),
                width: 0.8,
              ),
            ),
            shadows: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withAlpha(18),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}

/// Вкладка: иконка и подпись. [tint] (0..1) — насколько над ней линза:
/// цвет перетекает непрерывно, пока линза едет или её ведут пальцем.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.tint,
    required this.primary,
    required this.unselected,
    required this.onTap,
    this.onLongPress,
  });

  final (IconData, IconData, String) item;
  final bool selected;
  final double tint;
  final Color primary;
  final Color unselected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final (iconOff, iconOn, label) = item;
    final color = Color.lerp(unselected, primary, tint)!;
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      excludeSemantics: true,
      child: Pressable(
        scale: 0.86,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(tint > 0.5 ? iconOn : iconOff, color: color, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler:
                  MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: tint > 0.5 ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
