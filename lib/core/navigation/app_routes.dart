import "package:flutter/material.dart";

/// iOS-like horizontal slide for full-screen push/pop.
class SlidePageRoute<T> extends PageRouteBuilder<T> {
  SlidePageRoute({
    required this.page,
    this.fromRight = true,
    super.settings,
  }) : super(
          transitionDuration: const Duration(milliseconds: 320),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (_, animation, secondaryAnimation, child) {
            final curve = CurvedAnimation(
              parent: animation,
              curve: const Cubic(0.32, 0.0, 0.15, 1.0),
              reverseCurve: Curves.easeOutCubic,
            );

            final begin = fromRight ? const Offset(1.0, 0) : const Offset(-1.0, 0);
            final enter = Tween<Offset>(begin: begin, end: Offset.zero).animate(curve);
            final fade = Tween<double>(begin: 0.98, end: 1.0).animate(curve);

            return FadeTransition(
              opacity: fade,
              child: SlideTransition(
                position: enter,
                child: child,
              ),
            );
          },
        );

  final Widget page;
  final bool fromRight;
}

/// Subtle scale + fade for details/cards.
class ScaleFadePageRoute<T> extends PageRouteBuilder<T> {
  ScaleFadePageRoute({
    required this.page,
    super.settings,
  }) : super(
          transitionDuration: const Duration(milliseconds: 260),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (_, animation, __, child) {
            final curve = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );

            final scale = Tween<double>(begin: 0.96, end: 1.0).animate(curve);
            final fade = Tween<double>(begin: 0.0, end: 1.0).animate(curve);

            return FadeTransition(
              opacity: fade,
              child: ScaleTransition(scale: scale, child: child),
            );
          },
        );

  final Widget page;
}

/// Lightweight transition for tab-like content swaps.
class TabFadeSwitcher extends StatelessWidget {
  const TabFadeSwitcher({
    super.key,
    required this.child,
    required this.tabKey,
  });

  final Widget child;
  final Object tabKey;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0.0, 0.03),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(tabKey),
        child: child,
      ),
    );
  }
}
