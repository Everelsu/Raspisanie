import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';

import 'refresh_logo_mark.dart';

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

    return EasyRefresh(
      onRefresh: onRefresh,
      onLoad: null,
      header: BuilderHeader(
        triggerOffset: 80,
        clamping: false,
        hapticFeedback: true,
        safeArea: false,
        processedDuration: const Duration(milliseconds: 600),
        position: IndicatorPosition.locator,
        builder: (context, state) => _RefreshMark(
          state: state,
          accent: accent,
        ),
      ),
      child: child,
    );
  }
}

/// Простой индикатор: логотип приложения. Тянешь — поворачивается и
/// проявляется, загрузка — крутится, готово — галочка. Без стеклянных
/// кругов и дуг.
class _RefreshMark extends StatelessWidget {
  const _RefreshMark({required this.state, required this.accent});

  final IndicatorState state;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final mode = state.mode;
    final progress = (state.offset / state.actualTriggerOffset).clamp(0.0, 1.0);

    final isSpinning =
        mode == IndicatorMode.processing || mode == IndicatorMode.ready;
    final isProcessed = mode == IndicatorMode.processed;
    final isDone = mode == IndicatorMode.done || mode == IndicatorMode.inactive;

    final opacity = isDone
        ? 0.0
        : (isSpinning || isProcessed)
            ? 1.0
            : (progress < 0.1
                ? 0.0
                : ((progress - 0.1) / 0.35).clamp(0.0, 1.0));

    final Widget mark;
    if (isProcessed) {
      mark = Icon(
        key: const ValueKey('check'),
        Icons.check_rounded,
        size: 26,
        color: accent,
      );
    } else if (isSpinning) {
      mark = RefreshLogoMark(
        key: const ValueKey('spin'),
        size: 26,
        color: accent,
        spinning: true,
      );
    } else {
      // Пока тянут — лого доворачивается на пол-оборота с прогрессом.
      mark = Transform.rotate(
        key: const ValueKey('pull'),
        angle: progress * 3.1415926,
        child: RefreshLogoMark(size: 26, color: accent),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: state.offset,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: AnimatedOpacity(
            opacity: opacity,
            duration: const Duration(milliseconds: 150),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: anim,
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: mark,
            ),
          ),
        ),
      ),
    );
  }
}
