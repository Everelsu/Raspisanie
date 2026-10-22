import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../motion.dart';

/// Цвет «стекла» в духе Liquid Glass — из темы: фон бара темы с подмесом
/// акцента, полупрозрачный, чтобы сквозь размытие читался контент.
Color glassBase(ThemeData theme, {double? opacity}) {
  final cs = theme.colorScheme;
  final isDark = theme.brightness == Brightness.dark;
  final navBg = theme.navigationBarTheme.backgroundColor ?? cs.surface;
  return Color.alphaBlend(cs.primary.withAlpha(isDark ? 24 : 12), navBg)
      .withValues(alpha: opacity ?? (isDark ? 0.7 : 0.74));
}

/// Кант стекла: светлая кромка с оттенком акцента.
Color glassRim(ThemeData theme) {
  final isDark = theme.brightness == Brightness.dark;
  return Color.alphaBlend(
    theme.colorScheme.primary.withAlpha(isDark ? 40 : 26),
    isDark ? Colors.white.withAlpha(26) : Colors.black.withAlpha(12),
  );
}

/// Стеклянная плашка: размытие фона только в пределах формы, заливка темы
/// с бликом сверху и тонкий кант. Суперэллипс — непрерывные углы как в iOS.
///
/// [grouped] — для нескольких стёкол рядом под общим [BackdropGroup]
/// (одно чтение фона на всех).
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.radius,
    required this.child,
    this.color,
    this.blur = 18,
    this.grouped = false,
    this.shadow = true,
  });

  final BorderRadius radius;
  final Widget child;
  final Color? color;
  final double blur;
  final bool grouped;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final base = color ?? glassBase(theme);
    final filter = ImageFilter.blur(sigmaX: blur, sigmaY: blur);
    final fill = DecoratedBox(
      decoration: ShapeDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(Colors.white.withAlpha(isDark ? 22 : 70), base),
            base,
          ],
        ),
        shape: RoundedSuperellipseBorder(
          borderRadius: radius,
          side: BorderSide(color: glassRim(theme), width: 0.8),
        ),
      ),
      child: child,
    );
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: RoundedSuperellipseBorder(borderRadius: radius),
        shadows: shadow
            ? [
                BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 50 : 22),
                  blurRadius: 18,
                  spreadRadius: -8,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: ClipRSuperellipse(
        borderRadius: radius,
        child: grouped
            ? BackdropFilter.grouped(filter: filter, child: fill)
            : BackdropFilter(filter: filter, child: fill),
      ),
    );
  }
}

/// Плавающая стеклянная шторка (как листы iOS 26): отступ от краёв,
/// непрерывные углы, ручка, iOS-кривая выезда. Контент шторки — только
/// своё содержимое: фон, ручку и скругления даёт обёртка.
///
/// [heightFactor] — фиксированная доля высоты экрана (для списков);
/// без него шторка по высоте контента.
Future<T?> showGlassSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double? heightFactor,
}) {
  return showModalBottomSheet<T>(
    context: context,
    sheetAnimationStyle: AppMotion.sheet,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: Colors.black.withAlpha(90),
    builder: (ctx) {
      final media = MediaQuery.of(ctx);
      final theme = Theme.of(ctx);
      // Шторка большая — стекло почти непрозрачное: меньше размытия на
      // всю площадь, контент читается на любом фоне.
      final panel = Glass(
        radius: BorderRadius.circular(32),
        blur: 24,
        color: glassBase(theme, opacity: 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withAlpha(50),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (heightFactor != null)
              Expanded(child: builder(ctx))
            else
              Flexible(child: builder(ctx)),
          ],
        ),
      );
      return Padding(
        // Клавиатура поднимает шторку, а не перекрывает поле поиска.
        padding: EdgeInsets.fromLTRB(8, 0, 8, 8 + media.viewInsets.bottom),
        child: heightFactor == null
            ? panel
            : SizedBox(
                height: (media.size.height - media.viewInsets.bottom) *
                    heightFactor,
                child: panel,
              ),
      );
    },
  );
}
