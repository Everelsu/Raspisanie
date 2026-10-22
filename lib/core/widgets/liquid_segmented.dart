import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../motion.dart';
import 'pressable.dart';

/// Сегментный переключатель с той же «линзой», что у таб-бара: подложка
/// выбранного сегмента едет на пружине и тянется по скорости, по ней
/// можно вести пальцем, цвет подписи перетекает вслед за линзой.
class LiquidSegmented<T> extends StatefulWidget {
  const LiquidSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.height = 46,
  });

  /// (значение, подпись, иконка или null).
  final List<(T, String, IconData?)> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final double height;

  @override
  State<LiquidSegmented<T>> createState() => _LiquidSegmentedState<T>();
}

class _LiquidSegmentedState<T> extends State<LiquidSegmented<T>>
    with SingleTickerProviderStateMixin {
  static const _inset = 4.0;
  late final AnimationController _pos;
  bool _dragging = false;

  int get _index =>
      widget.segments.indexWhere((s) => s.$1 == widget.value).clamp(0, 99);

  @override
  void initState() {
    super.initState();
    _pos = AnimationController.unbounded(vsync: this, value: _index.toDouble());
  }

  @override
  void didUpdateWidget(LiquidSegmented<T> old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value && !_dragging) _springTo(_index);
  }

  @override
  void dispose() {
    _pos.dispose();
    super.dispose();
  }

  void _springTo(int i, [double velocity = 0]) {
    if (AppMotion.reduced(context)) {
      _pos.value = i.toDouble();
      return;
    }
    _pos.animateWith(
        SpringSimulation(AppMotion.snappy, _pos.value, i.toDouble(), velocity));
  }

  void _select(int i) {
    if (widget.segments[i].$1 == widget.value) return;
    HapticFeedback.selectionClick();
    widget.onChanged(widget.segments[i].$1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final n = widget.segments.length;
    final h = widget.height;
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - _inset * 2) / n;
      return GestureDetector(
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (_) {
          _dragging = true;
          _pos.stop();
        },
        onHorizontalDragUpdate: (d) {
          _pos.value = (_pos.value + d.delta.dx / w).clamp(-0.2, n - 1 + 0.2);
        },
        onHorizontalDragEnd: (d) {
          _dragging = false;
          final v = d.velocity.pixelsPerSecond.dx / w;
          final target = (_pos.value + (v * 0.08).clamp(-0.5, 0.5))
              .round()
              .clamp(0, n - 1);
          _springTo(target, v);
          _select(target);
        },
        child: Container(
          height: h,
          decoration: ShapeDecoration(
            color: cs.onSurface.withAlpha(14),
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(h / 2),
            ),
          ),
          child: AnimatedBuilder(
            animation: _pos,
            builder: (context, _) {
              final t = _pos.value;
              final stretch = (_pos.velocity.abs() * 0.025).clamp(0.0, 0.15);
              // expand: подписи растянуты на всю высоту и центрированы
              // вместе с линзой (иначе ряд прижимался к верху — «съезжал»).
              return Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    left: 0,
                    top: _inset,
                    width: w,
                    height: h - _inset * 2,
                    child: Transform(
                      transform: Matrix4.translationValues(
                          _inset + t.clamp(-0.2, n - 0.8) * w, 0, 0)
                        ..scaleByDouble(1 + stretch, 1 - stretch * 0.3, 1, 1),
                      alignment: Alignment.center,
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              cs.primary.withAlpha(60),
                              cs.primary.withAlpha(34),
                            ],
                          ),
                          shape: RoundedSuperellipseBorder(
                            borderRadius:
                                BorderRadius.circular((h - _inset * 2) / 2),
                            side: BorderSide(
                                color: cs.primary.withAlpha(80), width: 0.8),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _inset),
                    child: Row(
                      children: [
                        for (var i = 0; i < n; i++)
                          SizedBox(
                            width: w,
                            child: Pressable(
                              scale: 0.92,
                              onTap: () => _select(i),
                              child: _segment(theme, i,
                                  (1 - (t - i).abs()).clamp(0.0, 1.0)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    });
  }

  Widget _segment(ThemeData theme, int i, double tint) {
    final cs = theme.colorScheme;
    final (_, label, icon) = widget.segments[i];
    final color = Color.lerp(cs.onSurfaceVariant, cs.primary, tint)!;
    return Semantics(
      button: true,
      selected: i == _index,
      label: label,
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: tint > 0.5 ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
