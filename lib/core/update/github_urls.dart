import "github_references.dart";

/// Единая точка URL для данных репозитория [GitHubReferences] (raw + API).
class GitHubProjectUrls {
  GitHubProjectUrls._();

  /// Каноническое имя файла времени пар и источников на GitHub.
  static const String scheduleTimesFile = "schedule_times.json";

  /// Ветка с данными приложения (время пар, источники-техникумы).
  /// Отдельная orphan-ветка по образцу `updater`: правка данных — это
  /// коммит в `data`, без релиза и без изменений кода в master.
  static const String dataBranch = "data";

  /// URL raw JSON времени пар и источников — из ветки [dataBranch].
  static String get scheduleTimesRaw =>
      "https://raw.githubusercontent.com/${GitHubReferences.owner}/${GitHubReferences.repo}/$dataBranch/$scheduleTimesFile";

  /// Фолбэк: тот же файл в master — для старых установок и на случай,
  /// если ветка data недоступна.
  static String get scheduleTimesMasterFallbackRaw =>
      "https://raw.githubusercontent.com/${GitHubReferences.owner}/${GitHubReferences.repo}/master/$scheduleTimesFile";

  static String get lessonTimesLegacyRaw =>
      "https://raw.githubusercontent.com/${GitHubReferences.owner}/${GitHubReferences.repo}/master/lesson_times.json";

  static String get releasesLatestApi =>
      "https://api.github.com/repos/${GitHubReferences.owner}/${GitHubReferences.repo}/releases/latest";
}
