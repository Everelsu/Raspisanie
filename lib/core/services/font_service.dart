import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "package:shared_preferences/shared_preferences.dart";

enum AppFont {
  nunito,
  golosText,
  jost,
  manrope,
  robotoSlab,
  spaceMono,
}

class FontService extends ChangeNotifier {
  static const _prefsKey = "selected_font";

  AppFont _current = AppFont.nunito;
  AppFont get current => _current;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved == null) return;
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
      case AppFont.golosText:
        return "Golos Text";
      case AppFont.jost:
        return "Jost";
      case AppFont.manrope:
        return "Manrope";
      case AppFont.robotoSlab:
        return "Roboto Slab";
      case AppFont.spaceMono:
        return "Space Mono";
    }
  }

  TextTheme applyTo(TextTheme base) {
    switch (_current) {
      case AppFont.nunito:
        return GoogleFonts.nunitoTextTheme(base);
      case AppFont.golosText:
        return _mapThemeWithGoogleFont(base, "Golos Text");
      case AppFont.jost:
        return GoogleFonts.jostTextTheme(base);
      case AppFont.manrope:
        return GoogleFonts.manropeTextTheme(base);
      case AppFont.robotoSlab:
        return GoogleFonts.robotoSlabTextTheme(base);
      case AppFont.spaceMono:
        return GoogleFonts.spaceMonoTextTheme(base);
    }
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
      case AppFont.golosText:
        return GoogleFonts.getFont(
          "Golos Text",
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
      case AppFont.spaceMono:
        return GoogleFonts.spaceMono(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
        );
    }
  }

  TextTheme _mapThemeWithGoogleFont(TextTheme base, String fontFamily) {
    TextStyle? map(TextStyle? style) {
      if (style == null) return null;
      try {
        return GoogleFonts.getFont(
          fontFamily,
          textStyle: style,
        );
      } catch (_) {
        return style;
      }
    }

    return base.copyWith(
      displayLarge: map(base.displayLarge),
      displayMedium: map(base.displayMedium),
      displaySmall: map(base.displaySmall),
      headlineLarge: map(base.headlineLarge),
      headlineMedium: map(base.headlineMedium),
      headlineSmall: map(base.headlineSmall),
      titleLarge: map(base.titleLarge),
      titleMedium: map(base.titleMedium),
      titleSmall: map(base.titleSmall),
      bodyLarge: map(base.bodyLarge),
      bodyMedium: map(base.bodyMedium),
      bodySmall: map(base.bodySmall),
      labelLarge: map(base.labelLarge),
      labelMedium: map(base.labelMedium),
      labelSmall: map(base.labelSmall),
    );
  }

}
