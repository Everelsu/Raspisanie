import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "package:shared_preferences/shared_preferences.dart";

enum AppFont {
  nunito,
  jost,
  manrope,
  robotoSlab,
  ndot77,
  spaceGrotesk,
}

class FontService extends ChangeNotifier {
  static const _prefsKey = "selected_font";

  AppFont _current = AppFont.nunito;
  AppFont get current => _current;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved == null) return;
    if (saved == "spaceGroteskLocal") {
      _current = AppFont.spaceGrotesk;
      return;
    }
    _current = AppFont.values.firstWhere(
      (e) => e.name == saved,
      orElse: () => AppFont.nunito,
    );
  }

  Future<void> setFont(AppFont font) async {
    if (_current == font) return;
    _current = font;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, font.name);
  }

  String displayName(AppFont font) {
    switch (font) {
      case AppFont.nunito:
        return "Nunito";
      case AppFont.jost:
        return "Jost";
      case AppFont.manrope:
        return "Manrope";
      case AppFont.robotoSlab:
        return "Roboto Slab";
      case AppFont.ndot77:
        return "Ndot 77";
      case AppFont.spaceGrotesk:
        return "Space Grotesk";
    }
  }

  TextTheme applyTo(TextTheme base) {
    switch (_current) {
      case AppFont.nunito:
        return GoogleFonts.nunitoTextTheme(base);
      case AppFont.jost:
        return GoogleFonts.jostTextTheme(base);
      case AppFont.manrope:
        return GoogleFonts.manropeTextTheme(base);
      case AppFont.robotoSlab:
        return GoogleFonts.robotoSlabTextTheme(base);
      case AppFont.ndot77:
        return _mapThemeWithFontFamily(base, "Ndot77JPExtended");
      case AppFont.spaceGrotesk:
        return _mapThemeWithFontFamily(base, "SpaceGrotesk");
    }
  }

  /// Текст на canvas (например PNG «поделиться днём») — тот же шрифт, что в приложении.
  TextStyle textForCanvas(
    Color color, {
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    double? height,
  }) {
    return previewStyle(
      _current,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
    ).copyWith(height: height);
  }

  TextStyle previewStyle(
    AppFont font, {
    required Color color,
    double fontSize = 22,
    FontWeight fontWeight = FontWeight.w700,
  }) {
    switch (font) {
      case AppFont.nunito:
        return GoogleFonts.nunito(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
        );
      case AppFont.jost:
        return GoogleFonts.jost(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
        );
      case AppFont.manrope:
        return GoogleFonts.manrope(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
        );
      case AppFont.robotoSlab:
        return GoogleFonts.robotoSlab(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
        );
      case AppFont.ndot77:
        return TextStyle(
          fontFamily: "Ndot77JPExtended",
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
        );
      case AppFont.spaceGrotesk:
        return TextStyle(
          fontFamily: "SpaceGrotesk",
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
        );
    }
  }

  TextTheme _mapThemeWithFontFamily(TextTheme base, String fontFamily) {
    TextStyle copyWithFont(TextStyle? style) {
      if (style == null) return const TextStyle();
      return style.copyWith(fontFamily: fontFamily);
    }
    return TextTheme(
      displayLarge: copyWithFont(base.displayLarge),
      displayMedium: copyWithFont(base.displayMedium),
      displaySmall: copyWithFont(base.displaySmall),
      headlineLarge: copyWithFont(base.headlineLarge),
      headlineMedium: copyWithFont(base.headlineMedium),
      headlineSmall: copyWithFont(base.headlineSmall),
      titleLarge: copyWithFont(base.titleLarge),
      titleMedium: copyWithFont(base.titleMedium),
      titleSmall: copyWithFont(base.titleSmall),
      bodyLarge: copyWithFont(base.bodyLarge),
      bodyMedium: copyWithFont(base.bodyMedium),
      bodySmall: copyWithFont(base.bodySmall),
      labelLarge: copyWithFont(base.labelLarge),
      labelMedium: copyWithFont(base.labelMedium),
      labelSmall: copyWithFont(base.labelSmall),
    );
  }

}
