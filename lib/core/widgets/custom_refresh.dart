import 'dart:math' as math;

import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Минималистичный pull-to-refresh.
///
/// Визуально:
///   • Контент плавно съезжает вниз, скругляются верхние углы
///   • Появляется одно кольцо: при тяге заполняется по прогрессу,
///     при loading — крутится бесконечно
///   • При armed — haptic + лёгкий scale-pop кольца
///
/// Никакого CustomPainter, никаких лишних контроллеров —
/// один AnimationController, один RepaintBoundary.
class CustomRefreshWrapper extends StatefulWidget {
  final Widget child;
  final Future<void> Function() onRefresh;
  final Color? color;
  final double indicatorTopPadding;

  const CustomRefreshWrapper({
    super.key,
    required this.child,
    required this.onRefresh,
    this.color,
    this.indicatorTopPadding = 0,
  });

  @override
  State<CustomRefreshWrapper> createState() => _CustomRefreshWrapperState();
}

class _CustomRefreshWrapperState extends State<CustomRefreshWrapper>
    with SingleTickerProviderStateMixin {

  AnimationController? _ctrl;

  bool _wasArmed = false;
  /// Максимальный прогресс за текущую тягу — дуга только растёт, не откатывается
  double _maxPullProgress = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    _ctrl = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.color ?? Theme.of(context).colorScheme.primary;

    return CustomRefreshIndicator(
      onRefresh: widget.onRefresh,
      offsetToArmed: 72,
      onStateChanged: (change) {
        final isArmed    = change.currentState == IndicatorState.armed;
        final isLoading  = change.currentState.isLoading;
        final isIdle     = change.currentState == IndicatorState.idle;

        if (isArmed && !_wasArmed) {
          HapticFeedback.lightImpact();
        }
        _wasArmed = isArmed;

        if (isLoading) {
          _ctrl?.repeat();
        } else if (isIdle) {
          _maxPullProgress = 0;
          _ctrl?.stop();
          _ctrl?.reset();
        }
      },
      builder: (context, child, controller) {
        final t       = controller.value.clamp(0.0, 1.5);
        final p       = t.clamp(0.0, 1.0);
        final loading = controller.state.isLoading;
        final armed   = controller.state == IndicatorState.armed || t >= 1.0;

        // Дуга только растёт: запоминаем пик прогресса, при отпускании не откатываем
        if (!loading) {
          if (p > _maxPullProgress) _maxPullProgress = p;
        }
        final displayProgress = loading ? 1.0 : _maxPullProgress;

        // Rubber-band смещение контента
        const zone = 72.0;
        final offset = t <= 1.0 ? t * zone : zone + (t - 1.0) * zone * 0.12;
        // Скругление растёт с тягой (0 → 16px)
        final radius = offset < 1 ? 0.0 : (offset / zone).clamp(0.0, 1.0) * 16.0;
        // Кольцо спрятано выше — выезжает с границы экрана
        final emerge = Curves.easeOutCubic.transform(displayProgress);
        final ringSlideY = 88.0 * (1.0 - emerge);

        // Показывать индикатор только при тяге или загрузке — иначе за контентом не видно кружка
        final isIdle = controller.state == IndicatorState.idle;
        final showIndicator = loading || (!isIdle && displayProgress >= 0.02);

        return Stack(
          children: [
            // Индикатор — только когда тянем или грузим; съезжает сверху
            if (showIndicator)
              Positioned(
                top: widget.indicatorTopPadding,
                left: 0,
                right: 0,
                height: zone,
                child: Transform.translate(
                  offset: Offset(0, -ringSlideY),
                  child: RepaintBoundary(
                    child: _Ring(
                      accent: accent,
                      progress: displayProgress,
                      loading: loading,
                      armed: armed,
                      ctrl: _ctrl!,
                    ),
                  ),
                ),
              ),

            // Контент
            Transform.translate(
              offset: Offset(0, offset),
              child: AnimatedScale(
                scale: armed ? 0.98 : 1.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: ClipRRect(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
                  child: child,
                ),
              ),
            ),
          ],
        );
      },
      child: widget.child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Ring extends StatelessWidget {
  final Color accent;
  final double progress;
  final bool loading;
  final bool armed;
  final AnimationController ctrl;

  const _Ring({
    required this.accent,
    required this.progress,
    required this.loading,
    required this.armed,
    required this.ctrl,
  });

  @override
  Widget build(BuildContext context) {
    final easedProgress = Curves.easeOutCubic.transform(progress);
    final stableProgress = (armed && !loading) ? 1.0 : easedProgress;
    // При загрузке — полное кольцо (360°), крутится; без загрузки — по прогрессу
    final sweep = loading ? 360.0 : stableProgress * 360.0;
    final isFullRing = !loading && sweep >= 355.0;

    return Center(
      child: AnimatedBuilder(
        animation: ctrl,
        builder: (_, __) {
          final spin = ctrl.value;
          const ringSize = 40.0;
          final startDeg = loading ? spin * 360.0 - 90.0 : -90.0;
          final scale = armed ? 1.06 : 1.0;
          // Вращение полного кольца при загрузке
          final rotationRad = loading ? spin * 2.0 * math.pi : 0.0;

          return TweenAnimationBuilder<double>(
            tween: Tween(end: scale),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            builder: (_, s, __) => Transform.scale(
              scale: s,
              child: SizedBox(
                width: ringSize + 20,
                height: ringSize + 20,
                child: CustomPaint(
                  painter: _RingPainter(
                    accent: accent,
                    progress: stableProgress,
                    loading: loading,
                    startDeg: startDeg,
                    sweepDeg: sweep,
                    ringSize: ringSize,
                    isFullRing: isFullRing || loading,
                    rotationRad: rotationRad,
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

// ─────────────────────────────────────────────────────────────────────────────

class _RingPainter extends CustomPainter {
  final Color accent;
  final double progress;
  final bool loading;
  final double startDeg;
  final double sweepDeg;
  final double ringSize;
  final bool isFullRing;
  final double rotationRad;

  const _RingPainter({
    required this.accent,
    required this.progress,
    required this.loading,
    required this.startDeg,
    required this.sweepDeg,
    this.ringSize = 40.0,
    this.isFullRing = false,
    this.rotationRad = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // В idle при нулевом прогрессе ничего не рисуем — не показывать кружок за контентом
    if (!loading && sweepDeg < 1) return;

    final center = Offset(size.width / 2, size.height / 2);
    if (rotationRad != 0) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rotationRad);
      canvas.translate(-center.dx, -center.dy);
    }

    final rect = Rect.fromCenter(
      center: center,
      width: ringSize,
      height: ringSize,
    );
    final r = ringSize / 2;

    // Подложка и трек — только когда есть что показывать (дуга или полное кольцо)
    canvas.drawCircle(
      center,
      r + 2,
      Paint()
        ..color = accent.withValues(alpha: 0.06)
        ..style = PaintingStyle.fill,
    );

    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = accent.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round,
    );

    if (sweepDeg < 1) {
      if (rotationRad != 0) canvas.restore();
      return;
    }

    final startRad = _deg(startDeg);

    // Полное кольцо — одним цветом, без градиента и точки; при загрузке крутится
    if (isFullRing) {
      canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..color = accent.withValues(alpha: 0.95)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0
          ..strokeCap = StrokeCap.round,
      );
      if (rotationRad != 0) canvas.restore();
      return;
    }

    // Дуга с градиентом и точкой на конце
    final endRad = startRad + _deg(sweepDeg);
    final sweepShader = SweepGradient(
      startAngle: startRad,
      endAngle: endRad,
      stops: const [0.0, 0.25, 0.6, 1.0],
      colors: [
        accent.withValues(alpha: loading ? 0.5 : 0.3 + progress * 0.2),
        accent.withValues(alpha: loading ? 0.75 : 0.55 + progress * 0.25),
        accent.withValues(alpha: loading ? 0.95 : 0.85 + progress * 0.12),
        accent.withValues(alpha: loading ? 1.0 : 0.92 + progress * 0.08),
      ],
    ).createShader(rect.inflate(4));

    canvas.drawArc(
      rect,
      startRad,
      _deg(sweepDeg),
      false,
      Paint()
        ..shader = sweepShader
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round,
    );

    final headAngle = startRad + _deg(sweepDeg);
    final headCenter = Offset(
      center.dx + r * math.cos(headAngle),
      center.dy + r * math.sin(headAngle),
    );
    canvas.drawCircle(
      headCenter,
      3.5,
      Paint()
        ..color = accent.withValues(alpha: loading ? 1.0 : 0.9 + progress * 0.1)
        ..style = PaintingStyle.fill,
    );
    if (rotationRad != 0) canvas.restore();
  }

  static double _deg(double d) => d * math.pi / 180.0;

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.startDeg != startDeg ||
      old.sweepDeg != sweepDeg ||
      old.progress != progress ||
      old.loading != loading ||
      old.ringSize != ringSize ||
      old.isFullRing != isFullRing ||
      old.rotationRad != rotationRad;
}