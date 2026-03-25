/// Bundled artwork — single source of truth for launcher / in-app branding.
abstract final class AppAssets {
  /// Same file used by [flutter_launcher_icons] (`pubspec.yaml` → `image_path`).
  static const String appIconPng = "assets/icon/app_icon.png";

  /// Must match [flutter_native_splash] `color` in `pubspec.yaml` (authentic launch screen).
  static const int splashBackgroundArgb = 0xFF000000;
}
