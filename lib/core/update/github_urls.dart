import "github_references.dart";

/// Единая точка URL для данных репозитория [GitHubReferences] (raw + API).
class GitHubProjectUrls {
  GitHubProjectUrls._();

  /// Каноническое имя файла времени пар на GitHub.
  static const String scheduleTimesFile = "schedule_times.json";

  /// URL raw JSON времени пар (синхрон с репозиторием).
  static String get scheduleTimesRaw =>
      "https://raw.githubusercontent.com/${GitHubReferences.owner}/${GitHubReferences.repo}/master/$scheduleTimesFile";

  static String get lessonTimesLegacyRaw =>
      "https://raw.githubusercontent.com/${GitHubReferences.owner}/${GitHubReferences.repo}/master/lesson_times.json";

  static String get releasesLatestApi =>
      "https://api.github.com/repos/${GitHubReferences.owner}/${GitHubReferences.repo}/releases/latest";
}
