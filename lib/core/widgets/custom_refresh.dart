import 'dart:math' as math;
import 'dart:ui';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';

class CustomRefreshWrapper extends StatelessWidget {
  const CustomRefreshWrapper({
    super.key,
    required this.child,
    required this.onRefresh,
    this.color,
    this.appBarExtent = 0,
  });

  final Widget child;
  final Future<void> Function() onRefresh;
  final Color? color;
  final double appBarExtent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;

    return EasyRefresh(
      onRefresh: onRefresh,
      onLoad: null,
      header: BuilderHeader(
        triggerOffset: 80,
        clamping: false,
        hapticFeedback: true,
        safeArea: false,
        processedDuration: const Duration(milliseconds: 700),
        position: IndicatorPosition.locator,
        builder: (context, state) => _RefreshPill(
          state: state,
          accent: accent,
          isDark: isDark,
        ),
      ),
      child: child,
    );
  }
}

// ── Pill ──────────────────────────────────────────────────────────────────────

class _RefreshPill extends StatelessWidget {
  const _RefreshPill({
    required this.state,
    required this.accent,
    required this.isDark,
  });

  final IndicatorState state;
  final Color accent;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final mode = state.mode;
    final progress = (state.offset / state.actualTriggerOffset).clamp(0.0, 1.0);

    final isSpinning =
        mode == IndicatorMode.processing || mode == IndicatorMode.ready;
    final isProcessed = mode == IndicatorMode.processed;
    final isArmed = mode == IndicatorMode.armed;
    final isDone = mode == IndicatorMode.done || mode == IndicatorMode.inactive;

    final opacity = isDone
        ? 0.0
        : isProcessed
            ? 1.0
            : (progress < 0.15
                ? 0.0
                : ((progress - 0.15) / 0.30).clamp(0.0, 1.0));

    final scale = (isSpinning || isProcessed)
        ? 1.0
        : (0.55 + 0.45 * progress).clamp(0.55, 1.0);

    return SizedBox(
      width: double.infinity,
      height: state.offset,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AnimatedOpacity(
            opacity: opacity,
            duration: const Duration(milliseconds: 200),
            child: AnimatedScale(
              scale: scale,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutBack,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (isArmed) _PulseRing(color: accent),
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: CustomPaint(
                      painter: _ArcRingPainter(
                        progress: (isSpinning || isProcessed) ? 1.0 : progress,
                        color: accent,
                        isProcessed: isProcessed,
                      ),
                    ),
                  ),
                  _CirclePill(
                    isSpinning: isSpinning,
                    isProcessed: isProcessed,
                    isArmed: isArmed,
                    accent: accent,
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Circle pill ──────────────────────────────────────────────────────────────

class _CirclePill extends StatelessWidget {
  const _CirclePill({
    required this.isSpinning,
    required this.isProcessed,
    required this.isArmed,
    required this.accent,
    required this.isDark,
  });

  final bool isSpinning;
  final bool isProcessed;
  final bool isArmed;
  final Color accent;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bgBase = isDark ? Colors.black : Colors.white;
    final bgColor = Color.alphaBlend(
      accent.withValues(alpha: isDark ? 0.14 : 0.10),
      bgBase.withValues(alpha: isDark ? 0.60 : 0.82),
    );

    Widget icon;
    if (isSpinning) {
      icon = SizedBox(
        key: const ValueKey('spin'),
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.0,
          color: accent,
          strokeCap: StrokeCap.round,
        ),
      );
    } else if (isProcessed) {
      icon = Icon(
        key: const ValueKey('check'),
        Icons.check_rounded,
        size: 22,
        color: accent,
      );
    } else {
      icon = AnimatedRotation(
        key: ValueKey(isArmed),
        turns: isArmed ? 0.5 : 0.0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
        child: Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 22,
          color: accent.withValues(alpha: isArmed ? 1.0 : 0.75),
        ),
      );
    }

    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bgColor,
            border: Border.all(
              color: accent.withValues(alpha: isDark ? 0.28 : 0.20),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.10),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: anim,
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: icon,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Arc ring ──────────────────────────────────────────────────────────────────

class _ArcRingPainter extends CustomPainter {
  _ArcRingPainter({
    required this.progress,
    required this.color,
    required this.isProcessed,
  });

  final double progress;
  final Color color;
  final bool isProcessed;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2.5;

    // Track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );

    if (progress <= 0) return;

    if (isProcessed) {
      // Solid full ring for the "done" state
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      );
      return;
    }

    final sweepAngle = 2 * math.pi * progress;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: -math.pi / 2 + sweepAngle,
        colors: [color.withValues(alpha: 0.35), color],
        tileMode: TileMode.clamp,
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_ArcRingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.isProcessed != isProcessed;
}

// ── Pulse ring ────────────────────────────────────────────────────────────────

class _PulseRing extends StatefulWidget {
  const _PulseRing({required this.color});
  final Color color;

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    _scale = Tween<double>(begin: 1.0, end: 1.7).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _opacity = Tween<double>(begin: 0.50, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Transform.scale(
        scale: _scale.value,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.color.withValues(alpha: _opacity.value),
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
