import 'dart:math' as math;

import 'package:flutter/material.dart';

class BottomBarWithSheet extends StatefulWidget {
  const BottomBarWithSheet({
    super.key,
    required this.selectedIndex,
    required this.onIndexChanged,
    required this.sheetChild,
    this.onSheetToggle,
    required this.sheetOpen,
  });

  final int selectedIndex;
  final ValueChanged<int> onIndexChanged;
  final Widget sheetChild;
  final VoidCallback? onSheetToggle;
  final bool sheetOpen;

  @override
  State<BottomBarWithSheet> createState() => _BottomBarWithSheetState();
}

class _BottomBarWithSheetState extends State<BottomBarWithSheet>
    with TickerProviderStateMixin {
  static const _sheetMax = 420.0;
  static const _barH = 62.0;
  static const _dur = Duration(milliseconds: 280);
  static const _curve = Curves.easeOutCubic;
  static const _sheetMinContentH = 250.0;
  static const _sheetHandleBlockH = 20.0;
  static const _closeSnapThreshold = 0.55;

  static const _items = <(IconData, IconData, String)>[
    (Icons.calendar_today_outlined, Icons.calendar_today, 'Расписание'),
    (Icons.bar_chart_outlined, Icons.bar_chart, 'Итоги'),
    (Icons.note_alt_outlined, Icons.note_alt, 'Заметки'),
    (Icons.settings_outlined, Icons.settings, 'Настройки'),
  ];

  late final AnimationController _sheetCtrl;
  late final CurvedAnimation _sheetAnim;
  late final AnimationController _btnCtrl;
  late final CurvedAnimation _btnAnim;
  bool _closingByDrag = false;

  @override
  void initState() {
    super.initState();
    _sheetCtrl = AnimationController(
      vsync: this,
      duration: _dur,
      value: widget.sheetOpen ? 1.0 : 0.0,
    );
    _sheetAnim = CurvedAnimation(parent: _sheetCtrl, curve: _curve);

    _btnCtrl = AnimationController(
      vsync: this,
      duration: _dur,
      value: widget.sheetOpen ? 1.0 : 0.0,
    );
    _btnAnim = CurvedAnimation(parent: _btnCtrl, curve: _curve);
  }

  @override
  void didUpdateWidget(BottomBarWithSheet old) {
    super.didUpdateWidget(old);
    if (widget.sheetOpen == old.sheetOpen) return;
    if (widget.sheetOpen) {
      _sheetCtrl.forward();
      _btnCtrl.forward();
    } else {
      _sheetCtrl.reverse();
      _btnCtrl.reverse();
    }
  }

  @override
  void dispose() {
    _sheetAnim.dispose();
    _btnAnim.dispose();
    _sheetCtrl.dispose();
    _btnCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final navBg = theme.navigationBarTheme.backgroundColor ?? cs.surface;
    final cardBg = theme.cardTheme.color ?? cs.surface;
    final divider = theme.dividerTheme.color ?? cs.outlineVariant;
    final unselected = theme.navigationBarTheme.iconTheme?.resolve({})?.color ??
        cs.onSurfaceVariant;

    final barH = _effectiveBarHeight(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _sheet(cardBg, cs, barH),
        ColoredBox(
            color: divider,
            child: const SizedBox(height: 0.5, width: double.infinity)),
        _bar(navBg, cs.primary, cs.onPrimary, unselected, theme, barH),
      ],
    );
  }

  Widget _sheet(Color bg, ColorScheme cs, double barH) {
    return AnimatedBuilder(
      animation: _sheetAnim,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final screenH = media.size.height;
        final safeBottom = media.padding.bottom;
        final availableH = math.max(0.0, screenH - barH - safeBottom);
        final maxSheet = math.min(_sheetMax, availableH * 0.78);
        final h = _sheetAnim.value * maxSheet;
        if (h < 1) return const SizedBox.shrink();
        final revealAt = math.min(_sheetMinContentH, maxSheet * 0.42);
        final contentOpacity =
            ((h - _sheetHandleBlockH) / (revealAt - _sheetHandleBlockH))
                .clamp(0.0, 1.0);
        final showHandle = h >= _sheetHandleBlockH;
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: SizedBox(
            height: h,
            width: double.infinity,
            child: ColoredBox(
              color: bg,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragStart: (_) {},
                onVerticalDragUpdate: (details) {
                  if (!widget.sheetOpen) return;
                  final next = (_sheetCtrl.value - (details.delta.dy / maxSheet))
                      .clamp(0.0, 1.0);
                  _sheetCtrl.value = next;
                  _btnCtrl.value = next;
                },
                onVerticalDragEnd: (details) {
                  final v = details.primaryVelocity ?? 0;
                  final shouldClose = _sheetCtrl.value < _closeSnapThreshold ||
                      v > 700;
                  if (shouldClose && widget.sheetOpen && !_closingByDrag) {
                    _triggerDragClose();
                    return;
                  }
                  if (widget.sheetOpen) {
                    _sheetCtrl.forward();
                    _btnCtrl.forward();
                  }
                },
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxHeight < _sheetHandleBlockH) {
                      return const SizedBox.expand();
                    }
                    return Column(
                      children: [
                        if (showHandle)
                          Padding(
                            padding: const EdgeInsets.only(top: 10, bottom: 6),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: cs.onSurface.withAlpha(46),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: const SizedBox(width: 40, height: 4),
                            ),
                          ),
                        Expanded(
                          child: IgnorePointer(
                            ignoring: contentOpacity < 0.98,
                            child: Opacity(
                              opacity: contentOpacity,
                              child: child!,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
      child: widget.sheetChild,
    );
  }

  void _triggerDragClose() {
    _closingByDrag = true;
    widget.onSheetToggle?.call();
    Future<void>.delayed(
      const Duration(milliseconds: 250),
      () => _closingByDrag = false,
    );
  }

  Widget _bar(
    Color bg,
    Color primary,
    Color onPrimary,
    Color unselected,
    ThemeData theme,
    double barH,
  ) {
    return Material(
      color: bg,
      elevation: 10,
      shadowColor: Colors.black.withAlpha(26),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: barH,
          child: Row(
            children: [
              _navItem(0, primary, unselected, barH),
              _navItem(1, primary, unselected, barH),
              _centerBtn(primary, onPrimary),
              _navItem(2, primary, unselected, barH),
              _navItem(3, primary, unselected, barH),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int i, Color primary, Color unselected, double barH) {
    final sel = widget.selectedIndex == i;
    final item = _items[i];
    final color = sel ? primary : unselected;

    return Expanded(
      child: InkWell(
        onTap: () => widget.onIndexChanged(i),
        splashFactory: InkSparkle.splashFactory,
        highlightColor: Colors.transparent,
        child: SizedBox(
          height: barH,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: sel ? primary.withAlpha(26) : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: AnimatedScale(
                  scale: sel ? 1.12 : 1.0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutBack,
                  child: Icon(sel ? item.$2 : item.$1, color: color, size: 24),
                ),
              ),
              const SizedBox(height: 2),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: sel
                    ? Text(
                        item.$3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _effectiveBarHeight(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    if (scale <= 1.15) return _barH;
    return (_barH + 8).clamp(_barH, _barH + 14).toDouble();
  }

  Widget _centerBtn(Color primary, Color onPrimary) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: AnimatedBuilder(
        animation: _btnAnim,
        builder: (context, _) {
          final scale = 1 + (_btnAnim.value * 0.06);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onSheetToggle?.call(),
            child: SizedBox(
              width: 48,
              height: 48,
              child: Transform.scale(
                scale: scale,
                child: Transform.rotate(
                  angle: _btnAnim.value * math.pi,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [primary, primary.withAlpha(200)],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: primary.withAlpha(widget.sheetOpen ? 85 : 60),
                          blurRadius: widget.sheetOpen ? 14 : 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      _btnAnim.value < 0.5
                          ? Icons.calendar_month_rounded
                          : Icons.close_rounded,
                      color: onPrimary,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
