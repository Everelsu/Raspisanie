import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  @override
  State<BottomBarWithSheet> createState() => _BottomBarWithSheetState();

  /// Нижний отступ для контента который не должен перекрываться баром.
  /// Учитывает safe area устройства и масштаб текста.
  static double contentBottomPadding(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final barH = scale <= 1.15
        ? barHeight
        : (barHeight + 8).clamp(barHeight, barHeight + 14);
    return safeBottom + barH + 16;
  }
}

class _BottomBarWithSheetState extends State<BottomBarWithSheet>
    with TickerProviderStateMixin {
  // ─── Константы ──────────────────────────────────────────────────────────────
  static const _sheetMax = 420.0;
  static const _barH = BottomBarWithSheet.barHeight;
  static const _dur = Duration(milliseconds: 320);
  static const _curve = Curves.easeOutCubic;
  static const _sheetMinContentH = 250.0;
  static const _sheetHandleBlockH = 20.0;
  static const _closeSnapThreshold = 0.55;

  // Горизонтальный отступ — одинаковый для бара и шторки
  static const _hPad = 12.0;
  // Нижний отступ бара
  static const _bPad = 10.0;
  // Верхний отступ бара
  static const _tPad = 8.0;
  // Радиус — одинаковый для бара и шторки
  static const _radius = 26.0;

  static const _items = <(IconData, IconData, String)>[
    (Icons.calendar_today_outlined, Icons.calendar_today, 'Расписание'),
    (Icons.bar_chart_outlined, Icons.bar_chart, 'Итоги'),
    (Icons.language_outlined, Icons.language, 'Сеть'),
    (Icons.settings_outlined, Icons.settings, 'Настройки'),
  ];

  late final AnimationController _sheetCtrl;
  late final CurvedAnimation _sheetAnim;
  late final AnimationController _btnCtrl;
  late final CurvedAnimation _btnAnim;
  late final AnimationController _leadCtrl;
  late final AnimationController _followCtrl;
  late final List<AnimationController> _itemScaleCtrl;
  late final List<Animation<double>> _itemScaleAnim;
  bool _closingByDrag = false;
  bool _measureQueued = false;

  final GlobalKey _barKey = GlobalKey();
  final List<GlobalKey> _navKeys = List.generate(4, (_) => GlobalKey());
  List<(double x, double w)>? _itemSlots;
  Rect? _leadFrom, _leadTo, _followFrom, _followTo;

  void _measureSlots() {
    _measureQueued = false;
    final barBox = _barKey.currentContext?.findRenderObject() as RenderBox?;
    if (barBox == null) return;
    final list = <(double, double)>[];
    for (var i = 0; i < 4; i++) {
      final box = _navKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null) { list.add((0, 0)); continue; }
      final pos = barBox.globalToLocal(box.localToGlobal(Offset.zero));
      list.add((pos.dx, box.size.width));
    }
    if (!mounted) return;
    final changed = _itemSlots == null ||
        _itemSlots!.length != list.length ||
        list.asMap().entries.any((e) =>
            _itemSlots![e.key].$1 != e.value.$1 ||
            _itemSlots![e.key].$2 != e.value.$2);
    if (!changed && _itemSlots != null && _leadTo != null) return;
    setState(() {
      _itemSlots = list;
      if (list.length == 4 && _leadTo == null) {
        final bH = _effectiveBarHeight(context);
        final idx = widget.selectedIndex.clamp(0, 3);
        final r = Rect.fromLTWH(list[idx].$1, 0, list[idx].$2, bH);
        _leadFrom = _leadTo = _followFrom = _followTo = r;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _sheetCtrl = AnimationController(
        vsync: this, duration: _dur, value: widget.sheetOpen ? 1.0 : 0.0);
    _sheetAnim = CurvedAnimation(parent: _sheetCtrl, curve: _curve);
    _btnCtrl = AnimationController(
        vsync: this, duration: _dur, value: widget.sheetOpen ? 1.0 : 0.0);
    _btnAnim = CurvedAnimation(parent: _btnCtrl, curve: _curve);
    _leadCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180));
    _followCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 340));
    _itemScaleCtrl = List.generate(
      4,
      (_) => AnimationController(
          vsync: this, duration: const Duration(milliseconds: 220)),
    );
    _itemScaleAnim = _itemScaleCtrl.map((c) {
      return TweenSequence<double>([
        TweenSequenceItem(
            tween: Tween(begin: 1.0, end: 0.78)
                .chain(CurveTween(curve: Curves.easeIn)),
            weight: 35),
        TweenSequenceItem(
            tween: Tween(begin: 0.78, end: 1.12)
                .chain(CurveTween(curve: Curves.easeOut)),
            weight: 40),
        TweenSequenceItem(
            tween: Tween(begin: 1.12, end: 1.0)
                .chain(CurveTween(curve: Curves.easeInOut)),
            weight: 25),
      ]).animate(c);
    }).toList();
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
      final bH = _effectiveBarHeight(context);
      final target = Rect.fromLTWH(
        _itemSlots![widget.selectedIndex].$1, 0,
        _itemSlots![widget.selectedIndex].$2, bH,
      );
      _leadFrom = _leadTo ?? target;
      _leadTo = target;
      _followFrom = _followTo ?? target;
      _followTo = target;
      _leadCtrl.forward(from: 0);
      _followCtrl.forward(from: 0);
      _itemScaleCtrl[widget.selectedIndex].forward(from: 0);
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
    for (final c in _itemScaleCtrl) { c.dispose(); }
    super.dispose();
  }

  double _effectiveBarHeight(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    if (scale <= 1.15) return _barH;
    return (_barH + 8).clamp(_barH, _barH + 14).toDouble();
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final navBg = theme.navigationBarTheme.backgroundColor ?? cs.surface;
    final unselected = theme.navigationBarTheme.iconTheme?.resolve({})?.color ??
        cs.onSurfaceVariant;
    final barH = _effectiveBarHeight(context);

    // Единый цвет фона для бара и шторки. Почти непрозрачный:
    // BackdropFilter убран — blur под баром пере-рендерил контент каждый
    // кадр скролла и был главным источником лагов.
    final sharedBg = Color.alphaBlend(
      cs.primary.withAlpha(isDark ? 16 : 10),
      navBg.withAlpha(isDark ? 242 : 246),
    );

    return SafeArea(
      top: false,
      child: Padding(
        // Единый горизонтальный отступ для всего блока
        padding: const EdgeInsets.fromLTRB(_hPad, 0, _hPad, _bPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Шторка — та же ширина, те же скруглённые края сверху
            Flexible(
              child: _sheet(sharedBg, cs, barH, isDark),
            ),
            const SizedBox(height: _tPad),
            // Бар
            _bar(sharedBg, cs.primary, cs.onPrimary, unselected, theme, barH, isDark),
          ],
        ),
      ),
    );
  }

  // ─── Sheet ──────────────────────────────────────────────────────────────────

  Widget _sheet(Color bg, ColorScheme cs, double barH, bool isDark) {
    return AnimatedBuilder(
      animation: _sheetAnim,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final screenH = media.size.height;
        // safeBottom уже снят SafeArea выше, но считаем для правильного maxSheet
        final safeBottom = media.padding.bottom;
        final availableH =
            math.max(0.0, screenH - barH - safeBottom - _tPad - _bPad);
        final maxSheet = math.min(_sheetMax, availableH * 0.78);
        final h = _sheetAnim.value * maxSheet;
        if (h < 1) return const SizedBox.shrink();

        final revealAt = math.min(_sheetMinContentH, maxSheet * 0.42);
        final contentOpacity =
            ((h - _sheetHandleBlockH) / (revealAt - _sheetHandleBlockH))
                .clamp(0.0, 1.0);
        final showHandle = h >= _sheetHandleBlockH;

        return LayoutBuilder(builder: (context, pc) {
          final actualH = math.min(h, pc.maxHeight);
          if (actualH < 1) return const SizedBox.shrink();
          final contentH = math.min(maxSheet, pc.maxHeight.isFinite
              ? pc.maxHeight
              : maxSheet);

          return ClipRRect(
            // Верхние углы совпадают с радиусом бара
            borderRadius: const BorderRadius.all(Radius.circular(_radius)),
            child: Container(
              height: actualH,
              width: double.infinity,
              decoration: BoxDecoration(
                color: bg,
                // Тонкий бордер — тот же стиль что у бара
                border: Border.all(
                  color: cs.primary.withAlpha(isDark ? 28 : 18),
                  width: 0.8,
                ),
                borderRadius: const BorderRadius.all(Radius.circular(_radius)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(isDark ? 42 : 22),
                    blurRadius: 20,
                    spreadRadius: -4,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragStart: (_) {},
                onVerticalDragUpdate: (d) {
                  if (!widget.sheetOpen) return;
                  final next =
                      (_sheetCtrl.value - (d.delta.dy / maxSheet))
                          .clamp(0.0, 1.0);
                  _sheetCtrl.value = next;
                  _btnCtrl.value = next;
                },
                onVerticalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  final shouldClose =
                      _sheetCtrl.value < _closeSnapThreshold || v > 700;
                  if (shouldClose && widget.sheetOpen && !_closingByDrag) {
                    _triggerDragClose();
                    return;
                  }
                  if (widget.sheetOpen) {
                    _sheetCtrl.forward();
                    _btnCtrl.forward();
                  }
                },
                // OverflowBox держит контент на полной высоте шторки:
                // при анимации высоты меняется только клип, а календарь
                // не перелэйаутится каждый кадр (главный источник лагов).
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: contentH,
                    maxHeight: contentH,
                    child: Column(
                      children: [
                        if (showHandle)
                          Padding(
                            padding: const EdgeInsets.only(top: 10, bottom: 6),
                            child: Container(
                              width: 36, height: 4,
                              decoration: BoxDecoration(
                                color: cs.onSurface.withAlpha(45),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        Expanded(
                          child: IgnorePointer(
                            ignoring: contentOpacity < 0.98,
                            child: Opacity(
                              opacity: contentOpacity,
                              child: RepaintBoundary(child: child!),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        });
      },
      child: widget.sheetChild,
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

  // ─── Bar ────────────────────────────────────────────────────────────────────

  Widget _bar(Color bg, Color primary, Color onPrimary, Color unselected,
      ThemeData theme, double barH, bool isDark) {
    if (!_measureQueued) {
      _measureQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureSlots());
    }

    return RepaintBoundary(
      child: ClipRRect(
      borderRadius: BorderRadius.circular(_radius),
      child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(_radius),
            border: Border.all(
              color: primary.withAlpha(isDark ? 28 : 18),
              width: 0.8,
            ),
            boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(isDark ? 42 : 22),
                      blurRadius: 20,
                      spreadRadius: -4,
                      offset: const Offset(0, 6),
                    ),
              BoxShadow(
                color: primary.withAlpha(isDark ? 18 : 10),
                blurRadius: 0,
                spreadRadius: 0,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: SizedBox(
              key: _barKey,
              height: barH,
              child: Stack(
                children: [
                  Row(
                    children: [
                      _navItem(0, primary, unselected, barH, theme),
                      _navItem(1, primary, unselected, barH, theme),
                      _centerBtn(primary, onPrimary, isDark),
                      _navItem(2, primary, unselected, barH, theme),
                      _navItem(3, primary, unselected, barH, theme),
                    ],
                  ),
                  if (_itemSlots != null &&
                      _leadFrom != null && _leadTo != null &&
                      _followFrom != null && _followTo != null)
                    IgnorePointer(child: _jellyLayer(primary, barH, isDark)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Jelly ──────────────────────────────────────────────────────────────────

  Widget _jellyLayer(Color primary, double barH, bool isDark) {
    final leadCurve =
        CurvedAnimation(parent: _leadCtrl, curve: Curves.easeOutCubic);
    final followCurve =
        CurvedAnimation(parent: _followCtrl, curve: Curves.easeOutBack);
    return RepaintBoundary(
      child: ListenableBuilder(
        listenable: Listenable.merge([leadCurve, followCurve]),
        builder: (context, _) {
          final leadR = Rect.lerp(_leadFrom!, _leadTo!, leadCurve.value)!;
          final followR =
              Rect.lerp(_followFrom!, _followTo!, followCurve.value)!;
          const pad = 4.0;
          const r = 18.0;
          return Stack(
            children: [
              Positioned(
                left: followR.left + pad, top: followR.top + pad,
                width: followR.width - pad * 2,
                height: followR.height - pad * 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        primary.withAlpha(isDark ? 30 : 22),
                        primary.withAlpha(isDark ? 18 : 12),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(r),
                  ),
                ),
              ),
              Positioned(
                left: leadR.left + pad, top: leadR.top + pad,
                width: leadR.width - pad * 2,
                height: leadR.height - pad * 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        primary.withAlpha(isDark ? 60 : 44),
                        primary.withAlpha(isDark ? 40 : 28),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(r),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ─── Nav item ───────────────────────────────────────────────────────────────

  Widget _navItem(int i, Color primary, Color unselected, double barH,
      ThemeData theme) {
    final sel = widget.selectedIndex == i;
    final item = _items[i];
    final color = sel ? primary : unselected;
    return Expanded(
      key: _navKeys[i],
      child: Semantics(
        label: sel ? '${item.$3}, выбран' : item.$3,
        selected: sel,
        button: true,
        child: Material(
          color: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: () => widget.onIndexChanged(i),
            onLongPress: widget.onNavItemLongPress != null
                ? () {
                    HapticFeedback.mediumImpact();
                    widget.onNavItemLongPress!(i);
                  }
                : null,
            splashFactory: InkRipple.splashFactory,
            splashColor: primary.withAlpha(35),
            highlightColor: primary.withAlpha(18),
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: barH,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _itemScaleAnim[i],
                    builder: (_, child) => Transform.scale(
                      scale: sel ? _itemScaleAnim[i].value : 1.0,
                      child: child,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, anim) => ScaleTransition(
                        scale: anim,
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: Icon(
                        sel ? item.$2 : item.$1,
                        key: ValueKey('${i}_$sel'),
                        color: color, size: 23,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
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
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Centre FAB ─────────────────────────────────────────────────────────────

  Widget _centerBtn(Color primary, Color onPrimary, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Semantics(
        label: widget.sheetOpen ? 'Закрыть календарь' : 'Открыть календарь',
        button: true,
        child: AnimatedBuilder(
          animation: _btnAnim,
          builder: (context, _) {
            final t = _btnAnim.value;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onSheetToggle?.call(),
              child: Transform.scale(
                scale: 1.0 + t * 0.06,
                child: SizedBox(
                  width: 50, height: 50,
                  child: Transform.rotate(
                    angle: t * math.pi,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: const Alignment(-0.7, -0.7),
                          end: const Alignment(0.9, 0.9),
                          stops: const [0.0, 0.5, 1.0],
                          colors: [
                            Color.alphaBlend(
                                Colors.white.withAlpha(isDark ? 20 : 30),
                                primary),
                            primary,
                            Color.alphaBlend(
                                Colors.black.withAlpha(isDark ? 30 : 20),
                                primary),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: primary.withAlpha(
                                widget.sheetOpen ? 100 : 70),
                            blurRadius: widget.sheetOpen ? 18 : 12,
                            spreadRadius: widget.sheetOpen ? -2 : -4,
                            offset: const Offset(0, 4),
                          ),
                          BoxShadow(
                            color: Colors.white.withAlpha(isDark ? 20 : 35),
                            blurRadius: 0,
                            offset: const Offset(0, -1),
                          ),
                        ],
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, anim) => ScaleTransition(
                          scale: anim,
                          child: FadeTransition(opacity: anim, child: child),
                        ),
                        child: Icon(
                          t < 0.5
                              ? Icons.calendar_month_rounded
                              : Icons.close_rounded,
                          key: ValueKey(t < 0.5),
                          color: onPrimary, size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
