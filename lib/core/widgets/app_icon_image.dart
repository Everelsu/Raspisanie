import "package:flutter/material.dart";

import "../../app/theme.dart" show AppThemeColors;
import "refresh_logo_mark.dart";

/// Рисует иконку приложения (круг + знак) в цветах темы [colors] —
/// всегда совпадает с тем, что реально стоит в лаунчере.
class AppIconImage extends StatelessWidget {
  const AppIconImage({
    super.key,
    required this.colors,
    this.size = 48,
  });

  final AppThemeColors colors;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.surface,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: RefreshLogoMark(size: size * 0.44, color: colors.primary),
      ),
    );
  }
}
