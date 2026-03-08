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
  late final AnimationController _leadCtrl;
  late final AnimationController _followCtrl;
  bool _closingByDrag = false;

  final GlobalKey _barKey = GlobalKey();
  final List<GlobalKey> _navKeys = List.generate(4, (_) => GlobalKey());
  List<(double x, double w)>? _itemSlots;
  Rect? _leadFrom;
  Rect? _leadTo;
  Rect? _followFrom;
  Rect? _followTo;

  void _measureSlots() {
    final barBox = _barKey.currentContext?.findRenderObject() as RenderBox?;
    if (barBox == null) return;
    final list = <(double, double)>[];
    for (var i = 0; i < 4; i++) {
      final box = _navKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null) {
        list.add((0, 0));
        continue;
      }
      final pos = barBox.globalToLocal(box.localToGlobal(Offset.zero));
      list.add((pos.dx, box.size.width));
    }
    if (!mounted) return;
    final slotsChanged = _itemSlots == null ||
        _itemSlots!.length != list.length ||
        list.asMap().entries.any((e) =>
            _itemSlots![e.key].$1 != e.value.$1 || _itemSlots![e.key].$2 != e.value.$2);
    if (!slotsChanged && _itemSlots != null && _itemSlots!.length == 4 && _leadTo != null) return;
    setState(() {
      _itemSlots = list;
      if (list.length == 4 && _leadTo == null) {
        final barH = _effectiveBarHeight(context);
        final idx = widget.selectedIndex.clamp(0, 3);
        final r = Rect.fromLTWH(list[idx].$1, 0, list[idx].$2, barH);
        _leadFrom = r;
        _leadTo = r;
        _followFrom = r;
        _followTo = r;
      }
    });
  }

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

    _leadCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _followCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void didUpdateWidget(BottomBarWithSheet old) {
    super.didUpdateWidget(old);
    if (widget.sheetOpen != old.sheetOpen) {
      if (widget.sheetOpen) {
        _sheetCtrl.forward();
        _btnCtrl.forward();
      } else {
        _sheetCtrl.reverse();
        _btnCtrl.reverse();
      }
    }
    if (widget.selectedIndex != old.selectedIndex && _itemSlots != null) {
      final barH = _effectiveBarHeight(context);
      final target = Rect.fromLTWH(
        _itemSlots![widget.selectedIndex].$1,
        0,
        _itemSlots![widget.selectedIndex].$2,
        barH,
      );
      _leadFrom = _leadTo ?? target;
      _leadTo = target;
      _followFrom = _followTo ?? target;
      _followTo = target;
      _leadCtrl.forward(from: 0);
      _followCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _sheetAnim.dispose();
    _btnAnim.dispose();
    _leadCtrl.dispose();
    _followCtrl.dispose();
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
        Flexible(child: _sheet(cardBg, cs, barH)),
        ColoredBox(
            color: divider.withAlpha(80),
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
        return LayoutBuilder(
          builder: (context, parentConstraints) {
            final actualH = math.min(h, parentConstraints.maxHeight);
            if (actualH < 1) return const SizedBox.shrink();
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: SizedBox(
                height: actualH,
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
                            padding: const EdgeInsets.only(top: 12, bottom: 8),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: cs.onSurface.withAlpha(56),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const SizedBox(width: 44, height: 5),
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureSlots());
    return Material(
      color: bg,
      elevation: 10,
      shadowColor: Colors.black.withAlpha(26),
      child: SafeArea(
        top: false,
        child: SizedBox(
          key: _barKey,
          height: barH,
          child: Stack(
            children: [
              Row(
                children: [
                  _navItem(0, primary, unselected, barH),
                  _navItem(1, primary, unselected, barH),
                  _centerBtn(primary, onPrimary),
                  _navItem(2, primary, unselected, barH),
                  _navItem(3, primary, unselected, barH),
                ],
              ),
              if (_itemSlots != null &&
                  _leadFrom != null &&
                  _leadTo != null &&
                  _followFrom != null &&
                  _followTo != null)
                IgnorePointer(child: _jellyLayer(primary, barH)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _jellyLayer(Color primary, double barH) {
    final leadCurve = CurvedAnimation(parent: _leadCtrl, curve: Curves.easeOutCubic);
    final followCurve = CurvedAnimation(parent: _followCtrl, curve: Curves.easeOutBack);
    return RepaintBoundary(
      child: ListenableBuilder(
        listenable: Listenable.merge([leadCurve, followCurve]),
        builder: (context, _) {
          final leadR = Rect.lerp(_leadFrom!, _leadTo!, leadCurve.value)!;
          final followR = Rect.lerp(_followFrom!, _followTo!, followCurve.value)!;
          return Stack(
            children: [
              Positioned(
                left: followR.left + 2,
                top: followR.top + 2,
                width: followR.width - 4,
                height: followR.height - 4,
                child: Container(
                  decoration: BoxDecoration(
                    color: primary.withAlpha(36),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              Positioned(
                left: leadR.left + 2,
                top: leadR.top + 2,
                width: leadR.width - 4,
                height: leadR.height - 4,
                child: Container(
                  decoration: BoxDecoration(
                    color: primary.withAlpha(55),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _navItem(int i, Color primary, Color unselected, double barH) {
    final sel = widget.selectedIndex == i;
    final item = _items[i];
    final color = sel ? primary : unselected;

    return Expanded(
      key: _navKeys[i],
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => widget.onIndexChanged(i),
          splashFactory: InkRipple.splashFactory,
          splashColor: primary.withAlpha(40),
          highlightColor: primary.withAlpha(20),
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: barH,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: sel && _itemSlots == null
                      ? primary.withAlpha(26)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: AnimatedScale(
                  scale: sel ? 1.1 : 1.0,
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOutCubic,
                  child: Icon(sel ? item.$2 : item.$1, color: color, size: 24),
                ),
              ),
              const SizedBox(height: 2),
              AnimatedSize(
                duration: const Duration(milliseconds: 150),
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
                          begin: Alignment(-0.8, -0.8),
                          end: Alignment(1.0, 1.0),
                          stops: const [0.0, 0.4, 0.85, 1.0],
                          colors: [
                            primary,
                            primary.withAlpha(250),
                            primary.withAlpha(218),
                            primary.withAlpha(188),
                          ],
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
