import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import "package:custom_refresh_indicator/custom_refresh_indicator.dart";

class CustomRefreshWrapper extends StatefulWidget {
  final Widget child;
  final Future<void> Function() onRefresh;
  final Color? color;

  const CustomRefreshWrapper({
    super.key,
    required this.child,
    required this.onRefresh,
    this.color,
  });

  @override
  State<CustomRefreshWrapper> createState() => _CustomRefreshWrapperState();
}

class _CustomRefreshWrapperState extends State<CustomRefreshWrapper>
    with TickerProviderStateMixin {
  late final AnimationController _rotationCtrl;

  @override
  void initState() {
    super.initState();
    _rotationCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  @override
  void dispose() {
    _rotationCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.color ?? Theme.of(context).colorScheme.primary;
    return CustomRefreshIndicator(
      onRefresh: widget.onRefresh,
      offsetToArmed: 100,
      onStateChanged: (change) {
        if (change.didChange(to: IndicatorState.armed)) {
          HapticFeedback.mediumImpact();
        }
      },
      builder: (context, child, controller) {
        final value = controller.value.clamp(0.0, 1.4);
        final isRefreshing = controller.state.isLoading;
        final willRefresh =
            controller.state == IndicatorState.armed || value >= 1.0;
        final offset = (value * 95).clamp(0.0, 110.0);
        final scale = willRefresh ? 0.96 : 1.0;
        final hasOffset = offset > 1;

        if (isRefreshing && !_rotationCtrl.isAnimating) {
          _rotationCtrl.repeat();
        } else if (!isRefreshing && _rotationCtrl.isAnimating) {
          _rotationCtrl.stop();
        }

        return Stack(
          children: [
            if (hasOffset)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: offset,
                child: Center(
                  child: _RefreshIndicator(
                    accent: accent,
                    progress: value.clamp(0.0, 1.0),
                    isRefreshing: isRefreshing,
                    willRefresh: willRefresh,
                    rotationCtrl: _rotationCtrl,
                  ),
                ),
              ),
            AnimatedScale(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              scale: scale,
              alignment: Alignment.topCenter,
              child: Transform.translate(
                offset: Offset(0, offset),
                child: ClipRRect(
                  borderRadius: hasOffset
                      ? const BorderRadius.vertical(top: Radius.circular(16))
                      : BorderRadius.zero,
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

class _RefreshIndicator extends StatelessWidget {
  final Color accent;
  final double progress;
  final bool isRefreshing;
  final bool willRefresh;
  final AnimationController rotationCtrl;

  const _RefreshIndicator({
    required this.accent,
    required this.progress,
    required this.isRefreshing,
    required this.willRefresh,
    required this.rotationCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final size = 40.0 + (willRefresh ? 4.0 : 0.0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withAlpha(isRefreshing ? 50 : 30),
            accent.withAlpha(isRefreshing ? 80 : 50),
          ],
        ),
        boxShadow: willRefresh || isRefreshing
            ? [
                BoxShadow(
                  color: accent.withAlpha(40),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size - 8,
            height: size - 8,
            child: CircularProgressIndicator(
              value: isRefreshing ? null : progress,
              strokeWidth: 2.0,
              color: accent,
              backgroundColor: accent.withAlpha(20),
            ),
          ),
          RotationTransition(
            turns: isRefreshing
                ? rotationCtrl
                : AlwaysStoppedAnimation(progress * 0.75),
            child: AnimatedScale(
              scale: willRefresh || isRefreshing ? 1.0 : 0.7 + progress * 0.3,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.refresh_rounded,
                size: 20,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
