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
      primary: Color(0xFFFFFFFF),
      surface: Color(0xFF101010),
      card: Color(0xFF1C1C1E),
      onSurface: Color(0xFFE5E5EA),
      onSurfaceSecondary: Color(0xFF8E8E93),
      navBar: Color(0xFF1C1C1E),
      brightness: Brightness.dark,
    ),
    "light": AppThemeColors(
      primary: Color(0xFF111111),
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
    "red": AppThemeColors(
      primary: Color(0xFFFF453A),
      surface: Color(0xFF1A0A0A),
      card: Color(0xFF2E1414),
      onSurface: Color(0xFFFFE5E3),
      onSurfaceSecondary: Color(0xFFE07A72),
      navBar: Color(0xFF251010),
      brightness: Brightness.dark,
    ),
    "teal": AppThemeColors(
      primary: Color(0xFFE8E37A),
      surface: Color(0xFF1A1807),
      card: Color(0xFF2A260B),
      onSurface: Color(0xFFF8F3D0),
      onSurfaceSecondary: Color(0xFFC6C09A),
      navBar: Color(0xFF211E09),
      brightness: Brightness.dark,
    ),
  };

  static ThemeData forKey(
    String key, {
    TextTheme Function(TextTheme base)? textThemeBuilder,
    Color? accentColorOverride,
  }) {
    final c = _colors[key] ?? _colors["dark"]!;
    final primary = accentColorOverride ?? c.primary;
    final isLight = c.brightness == Brightness.light;
    // Текст на акценте: белый на тёмном, чёрный на светлом (по яркости акцента)
    final onPrimary = primary.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    final baseTextTheme = _buildTextTheme(c);
    final textTheme = textThemeBuilder == null
        ? baseTextTheme
        : textThemeBuilder(baseTextTheme);

    final scheme = ColorScheme(
      brightness: c.brightness,
      primary: primary,
      onPrimary: onPrimary,
      secondary: primary,
      onSecondary: onPrimary,
      error: const Color(0xFFFF453A),
      onError: Colors.white,
      surface: c.surface,
      onSurface: c.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: c.brightness,
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: c.surface,
      splashFactory: InkSparkle.splashFactory,
      iconTheme: IconThemeData(color: c.onSurfaceSecondary, size: 24),
      primaryIconTheme: IconThemeData(color: primary, size: 24),
      // iOS/macOS не переопределяем: дефолт PageTransitionsTheme уже
      // использует Cupertino-переход там, и так не зависим от точного имени
      // класса — оно менялось между версиями Flutter (см. падение CI на
      // stable 3.44 из-за "Method not found: CupertinoPageTransitionsBuilder").
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: c.onSurface.withAlpha(25),
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: c.card,
        elevation: isLight ? 2 : 0,
        shadowColor: isLight ? Colors.black.withAlpha(28) : Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: isLight
              ? BorderSide.none
              : BorderSide(color: c.onSurfaceSecondary.withAlpha(18)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: primary.withAlpha(40),
        circularTrackColor: primary.withAlpha(40),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.navBar,
        elevation: 0,
        indicatorColor: primary.withAlpha(30),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              color: primary,
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
            return IconThemeData(color: primary, size: 24);
          }
          return IconThemeData(color: c.onSurfaceSecondary, size: 24);
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary;
          return c.onSurfaceSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primary.withAlpha(80);
          }
          return c.card;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.transparent;
          return c.onSurfaceSecondary.withAlpha(40);
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: primary.withAlpha(40),
        thumbColor: primary,
        overlayColor: primary.withAlpha(26),
        trackHeight: 4,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.card,
        selectedColor: primary.withAlpha(40),
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
          borderSide: BorderSide(color: primary, width: 2),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: c.onSurfaceSecondary.withAlpha(30),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: primary,
        selectionColor: primary.withAlpha(72),
        selectionHandleColor: primary,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.card,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.card,
        elevation: 3,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: textTheme.bodyMedium,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        showDuration: const Duration(seconds: 3),
        verticalOffset: 10,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            c.onSurface.withAlpha(c.brightness == Brightness.dark ? 216 : 36),
            c.card,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: TextStyle(
          color: c.brightness == Brightness.dark ? c.surface : c.onSurface,
          fontSize: 12.5,
          height: 1.25,
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(5),
        radius: const Radius.circular(8),
        thumbVisibility: WidgetStateProperty.all(false),
        thumbColor: WidgetStatePropertyAll(primary.withAlpha(90)),
        crossAxisMargin: 2,
        mainAxisMargin: 4,
        interactive: true,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.onSurfaceSecondary,
        textColor: c.onSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        minVerticalPadding: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        dragHandleColor: c.onSurface.withAlpha(76),
        showDragHandle: false,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.card,
        contentTextStyle: TextStyle(color: c.onSurface),
        actionTextColor: primary,
        elevation: 4,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
    if (c.brightness == Brightness.light) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const [0.0, 0.42, 1.0],
        colors: [
          const Color(0xFF050505),
          const Color(0xFF232323),
          const Color(0xFF4A4A4A),
        ],
      );
    }
    final mid = Color.alphaBlend(c.primary.withAlpha(235), c.surface);
    final end = Color.alphaBlend(c.primary.withAlpha(195), c.surface);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      stops: const [0.0, 0.35, 0.7, 1.0],
      colors: [c.primary, mid, mid, end],
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
    "red": "Красная",
    "teal": "Жёлтая",
  };

  /// Палитра цветов для выбора акцента (во всплывающем меню настроек).
  static const accentPalette = <Color>[
    Color(0xFFFFFFFF), // dark default
    Color(0xFF111111), // light default
    Color(0xFF34C759), // green
    Color(0xFFFF6B9D), // pink
    Color(0xFF5AC8FA), // blue
    Color(0xFFA0A0A8), // gray
    Color(0xFFB388FF), // purple
    Color(0xFFFF9F1C), // orange
    Color(0xFFFF453A), // red
    Color(0xFFE8E37A), // soft yellow
    Color(0xFF1FA37A), // mint
  ];
}

/// Отступ сверху для списков под [AnimatedAppBar] ([extendBodyBehindAppBar]).
///
/// На части Android у `body` [viewPadding.top] бывает 0, а реальный inset — в
/// [padding.top] (уже «под шапку»). Тогда `viewPadding + toolbar` даёт мало — контент
/// уезжает вверх. Если же складывать `padding.top + toolbar` всегда — огромная щель.
double contentTopUnderAppBar(BuildContext context) {
  final v = MediaQuery.viewPaddingOf(context).top;
  final p = MediaQuery.paddingOf(context).top;
  final barBottom = v + kToolbarHeight;
  const tuck = 12.0;
  /// Зазор под шапкой; +5 ≈ опустить контент на ~5 px.
  const gapBelowBar = 26.0;

  if (p >= barBottom - 16) {
    return p - tuck + gapBelowBar;
  }
  if (v < 20 && p > 52) {
    return p - tuck + gapBelowBar;
  }
  return v + kToolbarHeight - tuck + gapBelowBar;
}

/// Высота нижнего бара (без safe area).
const double kBottomBarHeight = 64.0;

/// Нижний отступ для контента под [BottomBarWithSheet].
///
/// Учитывает safe area устройства и масштаб текста, поэтому правильно
/// работает на устройствах как с жестовой навигацией (safeBottom ≈ 34px),
/// так и без неё (safeBottom = 0).
double contentBottomPadding(BuildContext context) {
  final safeBottom = MediaQuery.paddingOf(context).bottom;
  final scale = MediaQuery.textScalerOf(context).scale(1);
  final barH = scale <= 1.15 ? kBottomBarHeight : (kBottomBarHeight + 8).clamp(kBottomBarHeight, kBottomBarHeight + 14);
  return safeBottom + barH + 16;
}
