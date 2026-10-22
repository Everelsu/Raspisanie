import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "pressable.dart";

class AnimatedAppBarVisuals {
  const AnimatedAppBarVisuals._();

  static const double defaultBottomRadius = 20.0;

  static double totalHeight(BuildContext context, {double? barHeight}) {
    return MediaQuery.paddingOf(context).top + (barHeight ?? kToolbarHeight);
  }

  static Color baseColor(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final surface = theme.colorScheme.surface;
    // Почти непрозрачный фон: BackdropFilter убран ради производительности
    // (blur заставлял пере-рендерить весь контент под баром каждый кадр),
    // лёгкая полупрозрачность сохраняет ощущение «стекла».
    return Color.alphaBlend(
      primary.withAlpha(isDark ? 18 : 10),
      surface.withValues(alpha: isDark ? 0.93 : 0.95),
    );
  }
}

/// Шапка с почти непрозрачным фоном, анимированным заголовком и экшенами.
class AnimatedAppBar extends StatefulWidget implements PreferredSizeWidget {
  const AnimatedAppBar({
    super.key,
    required this.title,
    required this.tabIndex,
    this.subtitle,
    this.actions = const [],
    this.titleWidget,
    this.bottomRadius = AnimatedAppBarVisuals.defaultBottomRadius,
    this.height,
  });

  final String title;
  final String? subtitle;
  final int tabIndex;
  final List<Widget> actions;
  final Widget? titleWidget;
  final double bottomRadius;
  final double? height;

  @override
  Size get preferredSize => Size.fromHeight(height ?? kToolbarHeight);

  @override
  State<AnimatedAppBar> createState() => _AnimatedAppBarState();
}

class _AnimatedAppBarState extends State<AnimatedAppBar> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final topPadding = MediaQuery.paddingOf(context).top;
    final barH = widget.height ?? kToolbarHeight;
    final totalH = topPadding + barH;

    final baseColor = AnimatedAppBarVisuals.baseColor(theme);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: SizedBox(
        height: totalH,
        child: ClipRRect(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(widget.bottomRadius),
            bottomRight: Radius.circular(widget.bottomRadius),
          ),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: topPadding + barH * 0.72,
                child: ColoredBox(color: baseColor),
              ),
              Positioned(
                top: topPadding + barH * 0.72,
                left: 0,
                right: 0,
                height: barH * 0.28 + 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.55, 1.0],
                      colors: [
                        baseColor,
                        baseColor.withValues(alpha: 0.45),
                        baseColor.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              Column(
                children: [
                  SizedBox(height: topPadding),
                  SizedBox(
                    height: barH,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 240),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeOutCubic,
                              layoutBuilder: (currentChild, previousChildren) {
                                return Stack(
                                  alignment: Alignment.centerLeft,
                                  children: <Widget>[
                                    ...previousChildren,
                                    if (currentChild != null) currentChild,
                                  ],
                                );
                              },
                              transitionBuilder: (child, animation) {
                                // HIG: короткий кроссфейд с едва
                                // заметным сдвигом — смена контекста
                                // читается, но не отвлекает.
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0, 0.12),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                );
                              },
                              child: KeyedSubtree(
                                key: ValueKey(
                                  "${widget.tabIndex}:${widget.title}:${widget.subtitle ?? ""}",
                                ),
                                child: widget.titleWidget ??
                                    _Title(
                                      title: widget.title,
                                      subtitle: widget.subtitle,
                                      primary: primary,
                                      theme: theme,
                                    ),
                              ),
                            ),
                          ),
                          // Экшены появляются/уходят мягко (fade + scale),
                          // а не выскакивают мгновенно при смене вкладки.
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              final scale = Tween<double>(
                                begin: 0.55,
                                end: 1.0,
                              ).animate(animation);
                              return FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: scale,
                                  child: child,
                                ),
                              );
                            },
                            child: widget.actions.isEmpty
                                ? const SizedBox(
                                    key: ValueKey("appbar_actions_none"))
                                : Row(
                                    key: ValueKey(
                                        "appbar_actions_${widget.tabIndex}"),
                                    mainAxisSize: MainAxisSize.min,
                                    children: widget.actions,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({
    required this.title,
    required this.subtitle,
    required this.primary,
    required this.theme,
  });

  final String title;
  final String? subtitle;
  final Color primary;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final hasSub = subtitle != null && subtitle!.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.start,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            height: 1.0,
          ),
        ),
        if (hasSub) ...[
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 4,
                height: 4,
                margin: const EdgeInsets.only(right: 5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primary.withAlpha(200),
                ),
              ),
              Flexible(
                child: Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: primary.withAlpha(210),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.1,
                    height: 1.0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class GlassActionButton extends StatelessWidget {
  const GlassActionButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.badge = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    Widget btn = Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primary.withAlpha(isDark ? 40 : 28),
            primary.withAlpha(isDark ? 22 : 14),
          ],
        ),
        border: Border.all(
          color: primary.withAlpha(isDark ? 60 : 42),
          width: 0.9,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(icon, size: 20, color: primary),
          if (badge)
            Positioned(
              top: 7,
              right: 7,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.error,
                  border: Border.all(
                    color: theme.colorScheme.surface,
                    width: 1.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (tooltip != null) {
      btn = Tooltip(message: tooltip!, child: btn);
    }

    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Pressable(
        scale: 0.86,
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: btn,
      ),
    );
  }
}
