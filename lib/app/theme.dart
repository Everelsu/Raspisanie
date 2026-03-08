import "package:flutter/material.dart";

class AppThemeColors {
  final Color primary;
  final Color surface;
  final Color card;
  final Color onSurface;
  final Color onSurfaceSecondary;
  final Color navBar;
  final Brightness brightness;

  const AppThemeColors({
    required this.primary,
    required this.surface,
    required this.card,
    required this.onSurface,
    required this.onSurfaceSecondary,
    required this.navBar,
    required this.brightness,
  });
}

class AppThemes {
  static const _colors = <String, AppThemeColors>{
    "dark": AppThemeColors(
      primary: Color(0xFF7CB8F7),
      surface: Color(0xFF101010),
      card: Color(0xFF1C1C1E),
      onSurface: Color(0xFFE5E5EA),
      onSurfaceSecondary: Color(0xFF8E8E93),
      navBar: Color(0xFF1C1C1E),
      brightness: Brightness.dark,
    ),
    "light": AppThemeColors(
      primary: Color(0xFF7EB5D8),
      surface: Color(0xFFF2F2F7),
      card: Color(0xFFFFFFFF),
      onSurface: Color(0xFF1C1C1E),
      onSurfaceSecondary: Color(0xFF8E8E93),
      navBar: Color(0xFFF9F9F9),
      brightness: Brightness.light,
    ),
    "green": AppThemeColors(
      primary: Color(0xFF34C759),
      surface: Color(0xFF0C1A0C),
      card: Color(0xFF1A2E1A),
      onSurface: Color(0xFFD4F5D4),
      onSurfaceSecondary: Color(0xFF7AB87A),
      navBar: Color(0xFF152815),
      brightness: Brightness.dark,
    ),
    "pink": AppThemeColors(
      primary: Color(0xFFFF6B9D),
      surface: Color(0xFF140A10),
      card: Color(0xFF241620),
      onSurface: Color(0xFFFCE4EC),
      onSurfaceSecondary: Color(0xFFA06080),
      navBar: Color(0xFF1E1218),
      brightness: Brightness.dark,
    ),
    "blue": AppThemeColors(
      primary: Color(0xFF5AC8FA),
      surface: Color(0xFF0A1620),
      card: Color(0xFF142638),
      onSurface: Color(0xFFD6EFFF),
      onSurfaceSecondary: Color(0xFF6C9DB8),
      navBar: Color(0xFF102030),
      brightness: Brightness.dark,
    ),
    "gray": AppThemeColors(
      primary: Color(0xFFA0A0A8),
      surface: Color(0xFF18181A),
      card: Color(0xFF28282C),
      onSurface: Color(0xFFE5E5EA),
      onSurfaceSecondary: Color(0xFF8E8E93),
      navBar: Color(0xFF222224),
      brightness: Brightness.dark,
    ),
    "purple": AppThemeColors(
      primary: Color(0xFFB388FF),
      surface: Color(0xFF120D1F),
      card: Color(0xFF241A36),
      onSurface: Color(0xFFF2ECFF),
      onSurfaceSecondary: Color(0xFFB39DDB),
      navBar: Color(0xFF1B1430),
      brightness: Brightness.dark,
    ),
    "orange": AppThemeColors(
      primary: Color(0xFFFF9F1C),
      surface: Color(0xFF211307),
      card: Color(0xFF342010),
      onSurface: Color(0xFFFFF1DE),
      onSurfaceSecondary: Color(0xFFE9B06D),
      navBar: Color(0xFF2B1A0C),
      brightness: Brightness.dark,
    ),
  };

  static ThemeData forKey(
    String key, {
    TextTheme Function(TextTheme base)? textThemeBuilder,
  }) {
    final c = _colors[key] ?? _colors["dark"]!;
    final isLight = c.brightness == Brightness.light;
    final baseTextTheme = _buildTextTheme(c);
    final textTheme = textThemeBuilder == null
        ? baseTextTheme
        : textThemeBuilder(baseTextTheme);

    final scheme = ColorScheme(
      brightness: c.brightness,
      primary: c.primary,
      onPrimary: isLight ? Colors.white : Colors.black,
      secondary: c.primary,
      onSecondary: isLight ? Colors.white : Colors.black,
      error: const Color(0xFFFF453A),
      onError: Colors.white,
      surface: c.surface,
      onSurface: c.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: c.brightness,
      scaffoldBackgroundColor: c.surface,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: c.card,
        elevation: isLight ? 2 : 0,
        shadowColor: isLight ? Colors.black.withAlpha(22) : Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: isLight
              ? BorderSide.none
              : BorderSide(color: c.onSurfaceSecondary.withAlpha(20)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.navBar,
        elevation: 0,
        indicatorColor: c.primary.withAlpha(30),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              color: c.primary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.15,
            );
          }
          return TextStyle(
            color: c.onSurfaceSecondary,
            fontSize: 11,
            letterSpacing: 0.15,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: c.primary, size: 24);
          }
          return IconThemeData(color: c.onSurfaceSecondary, size: 24);
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.primary;
          return c.onSurfaceSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return c.primary.withAlpha(80);
          }
          return c.card;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.transparent;
          return c.onSurfaceSecondary.withAlpha(40);
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.primary,
        inactiveTrackColor: c.primary.withAlpha(40),
        thumbColor: c.primary,
        overlayColor: c.primary.withAlpha(20),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.card,
        selectedColor: c.primary.withAlpha(40),
        labelStyle: TextStyle(color: c.onSurface, fontSize: 13),
        side: BorderSide(color: c.onSurfaceSecondary.withAlpha(40)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: TextStyle(color: c.onSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        fillColor: c.card,
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.onSurfaceSecondary.withAlpha(50)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.onSurfaceSecondary.withAlpha(50)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.primary, width: 2),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: c.onSurfaceSecondary.withAlpha(30),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.primary,
        foregroundColor: isLight ? Colors.white : Colors.black,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.card,
        contentTextStyle: TextStyle(color: c.onSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      textTheme: textTheme,
    );
  }

  static TextTheme _buildTextTheme(AppThemeColors c) {
    const fallback = <String>["Inter", "SF Pro Text", "Segoe UI", "Roboto"];
    return TextTheme(
      headlineLarge: TextStyle(
        color: c.onSurface,
        fontWeight: FontWeight.w700,
        fontSize: 26,
        height: 1.18,
        letterSpacing: -0.2,
        fontFamilyFallback: fallback,
      ),
      headlineMedium: TextStyle(
        color: c.onSurface,
        fontWeight: FontWeight.w700,
        fontSize: 22,
        height: 1.2,
        letterSpacing: -0.1,
        fontFamilyFallback: fallback,
      ),
      titleLarge: TextStyle(
        color: c.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: 19,
        height: 1.24,
        letterSpacing: 0.0,
        fontFamilyFallback: fallback,
      ),
      titleMedium: TextStyle(
        color: c.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: 15,
        height: 1.28,
        letterSpacing: 0.1,
        fontFamilyFallback: fallback,
      ),
      titleSmall: TextStyle(
        color: c.onSurfaceSecondary,
        fontWeight: FontWeight.w600,
        fontSize: 12,
        height: 1.3,
        letterSpacing: 0.25,
        fontFamilyFallback: fallback,
      ),
      bodyLarge: TextStyle(
        color: c.onSurface,
        fontSize: 15,
        height: 1.36,
        letterSpacing: 0.1,
        fontFamilyFallback: fallback,
      ),
      bodyMedium: TextStyle(
        color: c.onSurface,
        fontSize: 13.5,
        height: 1.38,
        letterSpacing: 0.1,
        fontFamilyFallback: fallback,
      ),
      bodySmall: TextStyle(
        color: c.onSurfaceSecondary,
        fontSize: 11.5,
        height: 1.32,
        letterSpacing: 0.15,
        fontFamilyFallback: fallback,
      ),
      labelLarge: TextStyle(
        color: c.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: 13,
        letterSpacing: 0.15,
        fontFamilyFallback: fallback,
      ),
      labelMedium: TextStyle(
        color: c.onSurfaceSecondary,
        fontSize: 11,
        letterSpacing: 0.15,
        fontFamilyFallback: fallback,
      ),
    );
  }

  static AppThemeColors colorsFor(String key) =>
      _colors[key] ?? _colors["dark"]!;

  static LinearGradient primaryGradient(String key) {
    final c = _colors[key] ?? _colors["dark"]!;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [c.primary, Color.alphaBlend(c.primary.withAlpha(180), c.surface)],
    );
  }

  static const allThemes = <String, String>{
    "dark": "Тёмная",
    "light": "Светлая",
    "green": "Зелёная",
    "pink": "Розовая",
    "blue": "Синяя",
    "gray": "Серая",
    "purple": "Фиолетовая",
    "orange": "Оранжевая",
  };
}
