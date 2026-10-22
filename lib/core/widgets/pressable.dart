import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../motion.dart';

/// Нажимаемая область с «вдавливанием» как у iOS-контролов: сжимается под
/// пальцем сразу и мягко отпружинивает. Без ripple — он чужд HIG.
///
/// Отклик идёт от сырых событий указателя, а не от onTapDown: тот при
/// конкуренции жестов (long press, свайпы) приходит вместе с отпусканием,
/// и быстрый тап не давал видимого нажатия вовсе.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.94,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Масштаб в нажатом состоянии: мелким элементам — сильнее, крупным
  /// карточкам — едва заметно.
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  /// Минимум «вдавленности»: короче глаз не замечает.
  static const _minHold = Duration(milliseconds: 90);

  bool _down = false;
  Offset _origin = Offset.zero;
  final _held = Stopwatch();
  Timer? _release;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _press(PointerDownEvent e) {
    _release?.cancel();
    _origin = e.position;
    _held
      ..reset()
      ..start();
    setState(() => _down = true);
  }

  void _unpress() {
    if (!_down) return;
    final wait = _minHold - _held.elapsed;
    _release?.cancel();
    if (wait <= Duration.zero) {
      setState(() => _down = false);
    } else {
      _release = Timer(wait, () {
        if (mounted) setState(() => _down = false);
      });
    }
  }

  @override
  void dispose() {
    _release?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pressed = _down && !AppMotion.reduced(context);
    return Listener(
      onPointerDown: _enabled ? _press : null,
      onPointerUp: (_) => _unpress(),
      onPointerCancel: (_) => _unpress(),
      // Палец поехал — это скролл, а не нажатие: отпускаем сразу.
      onPointerMove: (e) {
        if (_down && (e.position - _origin).distance > kTouchSlop) {
          _unpress();
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: pressed ? widget.scale : 1,
          duration: Duration(milliseconds: pressed ? 100 : 380),
          curve: pressed ? Curves.easeOut : Curves.easeOutBack,
          child: widget.child,
        ),
      ),
    );
  }
}
