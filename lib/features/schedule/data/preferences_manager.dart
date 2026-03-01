import "dart:convert";

import "package:shared_preferences/shared_preferences.dart";

import "lesson_times.dart";

class CollegeSource {
  const CollegeSource({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.builtIn = false,
  });

  final String id;
  final String name;
  final String baseUrl;
  final bool builtIn;

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "baseUrl": baseUrl,
      };

  factory CollegeSource.fromJson(Map<String, dynamic> json) => CollegeSource(
        id: (json["id"] ?? "").toString(),
        name: (json["name"] ?? "").toString(),
        baseUrl: (json["baseUrl"] ?? "").toString(),
      );
}

class PreferencesManager {
  PreferencesManager(this._prefs);

  final SharedPreferences _prefs;

  static const collegeDefault = "chtotib";
  static const collegeZabgc = "zabgc";

  static const themeDark = "dark";
  static const themeLight = "light";
  static const themeGreen = "green";
  static const themePink = "pink";
  static const themeBlue = "blue";
  static const themeGray = "gray";
  static const themePurple = "purple";
  static const themeOrange = "orange";

  static const builtInCollegeSources = <String, CollegeSource>{
    collegeDefault: CollegeSource(
      id: collegeDefault,
      name: "ЧТОТиБ",
      baseUrl: "https://www.chtotib.ru/schedule_gl/",
      builtIn: true,
    ),
    collegeZabgc: CollegeSource(
      id: collegeZabgc,
      name: "ЗабГК",
      baseUrl: "https://bbb.zabgc.ru/",
      builtIn: true,
    ),
  };

  static const fontSizeSmall = "small";
  static const fontSizeNormal = "normal";
  static const fontSizeLarge = "large";
  static const fontSizeExtraLarge = "extra_large";
  static const defaultLessonTimesRemoteUrl =
      "https://raw.githubusercontent.com/Everelsu/Raspisanie/master/lesson_times.json";

  // --- College ---
  String get college => _prefs.getString("college") ?? collegeDefault;
  set college(String v) => _prefs.setString("college", v);

  // --- Group ---
  String get selectedGroupFile => _prefs.getString("selected_group") ?? "";
  set selectedGroupFile(String v) => _prefs.setString("selected_group", v);

  String get selectedGroupName =>
      _prefs.getString("selected_group_name") ?? "";
  set selectedGroupName(String v) =>
      _prefs.setString("selected_group_name", v);

  bool get isGroupSelected =>
      selectedGroupFile.isNotEmpty && selectedGroupName.isNotEmpty;

  // --- Theme ---
  String get theme => _prefs.getString("theme") ?? themeDark;
  set theme(String v) => _prefs.setString("theme", v);

  // --- Widget ---
  bool get widgetUseAppTheme => _prefs.getBool("widget_use_app_theme") ?? true;
  set widgetUseAppTheme(bool v) => _prefs.setBool("widget_use_app_theme", v);

  String get widgetTheme => _prefs.getString("widget_theme") ?? themeDark;
  set widgetTheme(String v) => _prefs.setString("widget_theme", v);

  double get widgetFontScale => _prefs.getDouble("widget_font_scale") ?? 1.0;
  set widgetFontScale(double v) => _prefs.setDouble("widget_font_scale", v);

  String get effectiveWidgetTheme => widgetUseAppTheme ? theme : widgetTheme;

  // --- Display options ---
  bool get showBreaks => _prefs.getBool("show_breaks") ?? true;
  set showBreaks(bool v) => _prefs.setBool("show_breaks", v);

  bool get showLunch => _prefs.getBool("show_lunch") ?? true;
  set showLunch(bool v) => _prefs.setBool("show_lunch", v);

  bool get showTime => _prefs.getBool("show_time") ?? true;
  set showTime(bool v) => _prefs.setBool("show_time", v);

  bool get showLessonStatus => _prefs.getBool("show_lesson_status") ?? true;
  set showLessonStatus(bool v) => _prefs.setBool("show_lesson_status", v);

  bool get showProgressLine => _prefs.getBool("show_progress_line") ?? false;
  set showProgressLine(bool v) => _prefs.setBool("show_progress_line", v);

  bool get showPastDays => _prefs.getBool("show_past_days") ?? false;
  set showPastDays(bool v) => _prefs.setBool("show_past_days", v);

  // --- Font ---
  String get fontSize => _prefs.getString("font_size") ?? fontSizeNormal;
  set fontSize(String v) => _prefs.setString("font_size", v);

  double get fontSizeMultiplier => switch (fontSize) {
        fontSizeSmall => 0.85,
        fontSizeLarge => 1.15,
        fontSizeExtraLarge => 1.3,
        _ => 1.0,
      };

  // --- Cache ---
  bool get cacheEnabled => _prefs.getBool("cache_enabled") ?? true;
  set cacheEnabled(bool v) => _prefs.setBool("cache_enabled", v);

  // --- User Mode (student / teacher) ---
  String get userMode {
    final mode = _prefs.getString("user_mode");
    if (mode != null) return mode;
    final legacyIsTeacher = _prefs.getBool("is_teacher_mode");
    if (legacyIsTeacher == true) return "teacher";
    return "student";
  }

  set userMode(String v) {
    _prefs.setString("user_mode", v);
    _prefs.setBool("is_teacher_mode", v == "teacher");
  }

  bool get isTeacherMode => userMode == "teacher";

  // --- Notifications ---
  bool get notificationsEnabled =>
      _prefs.getBool("notifications_enabled") ?? false;
  set notificationsEnabled(bool v) =>
      _prefs.setBool("notifications_enabled", v);

  int get notificationOffset =>
      _prefs.getInt("notification_offset_minutes") ?? 10;
  set notificationOffset(int v) =>
      _prefs.setInt("notification_offset_minutes", v);

  bool get notifyScheduleChanges =>
      _prefs.getBool("notify_schedule_changes") ?? true;
  set notifyScheduleChanges(bool v) =>
      _prefs.setBool("notify_schedule_changes", v);

  bool get notifyNoLessons =>
      _prefs.getBool("notify_no_lessons_today") ?? true;
  set notifyNoLessons(bool v) =>
      _prefs.setBool("notify_no_lessons_today", v);

  // --- Auto refresh ---
  bool get autoRefreshEnabled =>
      _prefs.getBool("auto_refresh_enabled") ?? true;
  set autoRefreshEnabled(bool v) =>
      _prefs.setBool("auto_refresh_enabled", v);

  int get autoRefreshInterval =>
      _prefs.getInt("auto_refresh_interval") ?? 60;
  set autoRefreshInterval(int v) =>
      _prefs.setInt("auto_refresh_interval", v);

  // --- Favorites ---
  Set<String> get favoriteGroups {
    final raw = _prefs.getString("favorite_groups") ?? "";
    if (raw.isEmpty) return {};
    return raw.split(",").toSet();
  }

  void addFavoriteGroup(String name) {
    if (name.isEmpty) return;
    final fav = favoriteGroups.toSet()..add(name);
    _prefs.setString("favorite_groups", fav.join(","));
  }

  void removeFavoriteGroup(String name) {
    if (name.isEmpty) return;
    final fav = favoriteGroups.toSet()..remove(name);
    _prefs.setString("favorite_groups", fav.join(","));
  }

  bool isFavoriteGroup(String name) => favoriteGroups.contains(name);

  // --- Notes ---
  String get notesText => _prefs.getString("notes_text") ?? "";
  set notesText(String v) => _prefs.setString("notes_text", v);
  String get notesJson => _prefs.getString("notes_json") ?? "";
  set notesJson(String v) => _prefs.setString("notes_json", v);

  bool get notesDarkCards => _prefs.getBool("notes_dark_cards") ?? false;
  set notesDarkCards(bool v) => _prefs.setBool("notes_dark_cards", v);

  // --- Remote lesson times ---
  String get lessonTimesRemoteUrl =>
      _normalizeLessonTimesRemoteUrl(
        _prefs.getString("lesson_times_remote_url") ?? defaultLessonTimesRemoteUrl,
      );
  set lessonTimesRemoteUrl(String v) =>
      _prefs.setString("lesson_times_remote_url", _normalizeLessonTimesRemoteUrl(v));

  int? get lessonTimesRemoteSyncedAt {
    final ts = _prefs.getInt("lesson_times_remote_synced_at");
    return ts == null || ts <= 0 ? null : ts;
  }

  set lessonTimesRemoteSyncedAt(int? value) {
    if (value == null || value <= 0) {
      _prefs.remove("lesson_times_remote_synced_at");
      return;
    }
    _prefs.setInt("lesson_times_remote_synced_at", value);
  }

  int? get lessonTimesRemoteCheckedAt {
    final ts = _prefs.getInt("lesson_times_remote_checked_at");
    return ts == null || ts <= 0 ? null : ts;
  }

  set lessonTimesRemoteCheckedAt(int? value) {
    if (value == null || value <= 0) {
      _prefs.remove("lesson_times_remote_checked_at");
      return;
    }
    _prefs.setInt("lesson_times_remote_checked_at", value);
  }

  String get lessonTimesRemoteFingerprint =>
      _prefs.getString("lesson_times_remote_fingerprint") ?? "";
  set lessonTimesRemoteFingerprint(String value) =>
      _prefs.setString("lesson_times_remote_fingerprint", value);

  String _normalizeLessonTimesRemoteUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return defaultLessonTimesRemoteUrl;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return trimmed;

    // Convert GitHub "blob" URL to raw content URL.
    if (uri.host.toLowerCase() == "github.com") {
      final segments = uri.pathSegments;
      if (segments.length >= 5 && segments[2] == "blob") {
        final user = segments[0];
        final repo = segments[1];
        final branch = segments[3];
        final filePath = segments.sublist(4).join("/");
        return "https://raw.githubusercontent.com/$user/$repo/$branch/$filePath";
      }
    }
    return trimmed;
  }

  Map<int, LessonTime>? getCustomLessonTimes(String college) {
    final raw = _prefs.getString("lesson_times_$college");
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final out = <int, LessonTime>{};
      for (final entry in decoded.entries) {
        final lessonNumber = int.tryParse(entry.key);
        final value = entry.value;
        if (lessonNumber == null || value is! Map<String, dynamic>) continue;
        final start = value["start"] as String?;
        final end = value["end"] as String?;
        if (start == null || end == null) continue;
        out[lessonNumber] = LessonTime(lessonNumber, start, end);
      }
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  void setCustomLessonTimes(String college, Map<int, LessonTime> times) {
    final serializable = <String, Map<String, String>>{};
    final keys = times.keys.toList()..sort();
    for (final key in keys) {
      final t = times[key];
      if (t == null) continue;
      serializable["$key"] = {
        "start": t.startTime,
        "end": t.endTime,
      };
    }
    _prefs.setString("lesson_times_$college", jsonEncode(serializable));
  }

  void clearCustomLessonTimes(String college) {
    _prefs.remove("lesson_times_$college");
  }

  List<CollegeSource> get customCollegeSources {
    final raw = _prefs.getString("custom_college_sources");
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <CollegeSource>[];
      for (final e in decoded) {
        if (e is! Map<String, dynamic>) continue;
        final source = CollegeSource.fromJson(e);
        if (source.id.isEmpty || source.name.isEmpty || source.baseUrl.isEmpty) {
          continue;
        }
        out.add(source);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  List<CollegeSource> get allCollegeSources {
    return [
      ...builtInCollegeSources.values,
      ...customCollegeSources,
    ];
  }

  Map<String, String> get customCollegeBaseUrls {
    final map = <String, String>{};
    for (final s in customCollegeSources) {
      map[s.id] = s.baseUrl;
    }
    return map;
  }

  void saveCustomCollegeSources(List<CollegeSource> sources) {
    final safe = sources
        .where((s) => !builtInCollegeSources.containsKey(s.id))
        .map((s) => s.toJson())
        .toList();
    _prefs.setString("custom_college_sources", jsonEncode(safe));
  }
}
