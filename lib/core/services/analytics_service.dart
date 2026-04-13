import "package:firebase_analytics/firebase_analytics.dart";
import "package:flutter/foundation.dart";

class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  FirebaseAnalytics? _analytics;
  FirebaseAnalyticsObserver? _observer;
  bool _enabled = true;

  FirebaseAnalyticsObserver? get observer => _observer;
  bool get enabled => _enabled;

  Future<void> init() async {
    _analytics ??= FirebaseAnalytics.instance;
    _observer ??= FirebaseAnalyticsObserver(analytics: _analytics!);
  }

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    final a = _analytics;
    if (a == null) return;
    await a.setAnalyticsCollectionEnabled(enabled);
  }

  Future<void> setUserProperty(String name, String? value) async {
    final a = _analytics;
    if (a == null || !_enabled) return;
    await a.setUserProperty(name: name, value: value);
  }

  Future<void> logAppStart({
    required String appVersion,
    required String platform,
  }) async {
    await setUserProperty("app_version", appVersion);
    await setUserProperty("platform", platform);
    await logEvent("app_start", {
      "app_version": appVersion,
      "platform": platform,
      "k_release_mode": kReleaseMode,
    });
  }

  Future<void> logScreen(String name) async {
    final a = _analytics;
    if (a == null || !_enabled) return;
    await a.logScreenView(screenName: name);
  }

  Future<void> logThemeChanged(String themeKey) async {
    final a = _analytics;
    if (a == null || !_enabled) return;
    await a.setUserProperty(name: "theme", value: themeKey);
    await a.logEvent(name: "theme_changed", parameters: {"theme": themeKey});
  }

  Future<void> logFontChanged(String fontName) async {
    final a = _analytics;
    if (a == null || !_enabled) return;
    await a.setUserProperty(name: "font", value: fontName);
    await a.logEvent(name: "font_changed", parameters: {"font": fontName});
  }

  Future<void> logCollegeChanged(String collegeId) async {
    final a = _analytics;
    if (a == null || !_enabled) return;
    await a.setUserProperty(name: "college", value: collegeId);
    await a.logEvent(name: "college_changed", parameters: {"college": collegeId});
  }

  Future<void> logUserModeChanged(String mode) async {
    final a = _analytics;
    if (a == null || !_enabled) return;
    await a.setUserProperty(name: "user_mode", value: mode);
    await a.logEvent(name: "user_mode_changed", parameters: {"mode": mode});
  }

  Future<void> logGroupSelected({
    required String groupName,
    required bool isTeacherMode,
  }) async {
    final a = _analytics;
    if (a == null || !_enabled) return;
    await a.setUserProperty(name: "group", value: groupName);
    await a.logEvent(name: "group_selected", parameters: {
      "group": groupName,
      "is_teacher_mode": isTeacherMode,
    });
  }

  Future<void> logAccentChanged({
    required String themeKey,
    required int? accentValue,
    required String source,
  }) async {
    await logEvent("accent_changed", {
      "theme": themeKey,
      "accent": accentValue,
      "source": source,
    });
  }

  Future<void> logEvent(String name, Map<String, Object?> params) async {
    final a = _analytics;
    if (a == null || !_enabled) return;
    await a.logEvent(name: name, parameters: Map<String, Object>.fromEntries(
      params.entries.where((e) => e.value != null).map(
            (e) => MapEntry(e.key, e.value!),
          ),
    ));
  }
}

