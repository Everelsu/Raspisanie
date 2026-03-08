/// Конфигурация репозитория для автообновления из GitHub Releases.
/// https://github.com/Everelsu/Raspisanie/releases
class GitHubReferences {
  static const String owner = "Everelsu";
  static const String repo = "Raspisanie";
  /// Фильтр по имени APK в релизе (если пусто — берётся первый .apk).
  static const String apkKey = "";
  /// Токен для приватного репозитория (для публичного оставить пустым).
  static const String token = "";
}
