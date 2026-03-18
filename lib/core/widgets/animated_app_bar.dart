import "dart:ui";

import "package:flutter/material.dart";
import "package:flutter/services.dart";

/// AnimatedAppBar
///
/// Кастомный AppBar с:
/// - закруглёнными нижними углами
/// - fade+slide анимацией при смене вкладок/текста
/// - glassmorphism (BackdropFilter blur)
/// - градиентным фоном
/// - поддержкой subtitle (имя группы/преподавателя)
class AnimatedAppBar extends StatefulWidget implements PreferredSizeWidget {
  const AnimatedAppBar({
    super.key,
    required this.title,
    required this.tabIndex,
    this.subtitle,
    this.actions = const [],
    this.bottomRadius = 20.0,
    this.blurSigma = 22.0,
    this.height,
  });

  final String title;
  final String? subtitle;
  final int tabIndex;
  final List<Widget> actions;
  final double bottomRadius;
  final double blurSigma;
  final double? height;

  @override
  Size get preferredSize => Size.fromHeight(height ?? kToolbarHeight);

  @override
  State<AnimatedAppBar> createState() => _AnimatedAppBarState();
}

class _AnimatedAppBarState extends State<AnimatedAppBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  String _title = "";
  String? _subtitle;

  @override
  void initState() {
    super.initState();
    _title = widget.title;
    _subtitle = widget.subtitle;

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..value = 1.0;

    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);

    _slide = Tween<Offset>(begin: const Offset(0, 0.22), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
  }

  @override
  void didUpdateWidget(covariant AnimatedAppBar old) {
    super.didUpdateWidget(old);
    if (old.tabIndex != widget.tabIndex ||
        old.title != widget.title ||
        old.subtitle != widget.subtitle) {
      _swap();
    }
  }

  Future<void> _swap() async {
    await _ctrl.animateTo(
      0.0,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeIn,
    );
    if (mounted) {
      setState(() {
        _title = widget.title;
        _subtitle = widget.subtitle;
      });
    }
    if (mounted) {
      _ctrl.animateTo(
        1.0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final surface = theme.colorScheme.surface;
    final topPadding = MediaQuery.of(context).padding.top;
    final barH = widget.height ?? kToolbarHeight;
    final totalH = topPadding + barH;

    final baseColor = Color.alphaBlend(
      primary.withAlpha(isDark ? 18 : 10),
      surface.withValues(alpha: isDark ? 0.82 : 0.88),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: SizedBox(
        height: totalH,
        child: ClipRRect(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(widget.bottomRadius),
            bottomRight: Radius.circular(widget.bottomRadius),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: widget.blurSigma,
              sigmaY: widget.blurSigma,
            ),
            child: Stack(
              children: [
                // Layer 1: readable background for text area.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: topPadding + barH * 0.72,
                  child: ColoredBox(color: baseColor),
                ),
                // Layer 2: soft fade down to transparent (no hard line).
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
                // Layer 3: content (title + actions).
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
                              child: FadeTransition(
                                opacity: _opacity,
                                child: SlideTransition(
                                  position: _slide,
                                  child: _Title(
                                    title: _title,
                                    subtitle: _subtitle,
                                    primary: primary,
                                    theme: theme,
                                  ),
                                ),
                              ),
                            ),
                            if (widget.actions.isNotEmpty)
                              FadeTransition(
                                opacity: _opacity,
                                child: Row(
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

class GlassActionButton extends StatefulWidget {
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
  State<GlassActionButton> createState() => _GlassActionButtonState();
}

class _GlassActionButtonState extends State<GlassActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 180),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    Widget btn = ScaleTransition(
      scale: _scaleAnim,
      child: Container(
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
            Icon(widget.icon, size: 20, color: primary),
            if (widget.badge)
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
      ),
    );

    if (widget.tooltip != null) {
      btn = Tooltip(message: widget.tooltip!, child: btn);
    }

    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      onTapCancel: () => _pressCtrl.reverse(),
      child: Padding(
        padding: const EdgeInsets.only(right: 2),
        child: btn,
      ),
    );
  }
}

