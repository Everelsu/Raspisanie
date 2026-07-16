import "dart:convert";

import "package:flutter/foundation.dart";

import "github_http_client.dart";
import "github_references.dart";
import "github_update_service.dart";

/// Манифест обновления `latest.json` из ветки `updater` репозитория.
/// Генерируется релизным workflow (см. .github/workflows/release.yml).
class UpdateManifest {
  const UpdateManifest({
    required this.version,
    required this.apkUrl,
    this.sha256,
    this.size,
    this.notes = "",
  });

  final String version;
  final String apkUrl;

  /// SHA-256 APK для проверки целостности загрузки (может отсутствовать
  /// при фолбэке на GitHub API).
  final String? sha256;

  /// Размер APK в байтах (если известен).
  final int? size;

  /// Release-ноты в markdown (запись из CHANGELOG.md).
  final String notes;
}

/// URL манифеста в ветке `updater` (raw — без лимитов GitHub API).
String get updateManifestUrl =>
    "https://raw.githubusercontent.com/${GitHubReferences.owner}/${GitHubReferences.repo}/updater/latest.json";

/// Загружает манифест обновления. Основной источник — latest.json из ветки
/// `updater`; если его ещё нет (старые релизы) — фолбэк на GitHub Releases API.
Future<UpdateManifest?> fetchUpdateManifest() async {
  try {
    final response = await GitHubHttpClient.get(updateManifestUrl);
    if (response.statusCode == 200) {
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final raw = data["version"] as String? ?? "";
      final version = raw.startsWith("v") ? raw.substring(1) : raw;
      final apk = data["apk"] as Map<String, dynamic>?;
      final url = apk?["url"] as String? ?? "";
      if (version.isNotEmpty && url.isNotEmpty) {
        return UpdateManifest(
          version: version,
          apkUrl: url,
          sha256: (apk?["sha256"] as String?)?.toLowerCase(),
          size: (apk?["size"] as num?)?.toInt(),
          notes: (data["notes"] as String? ?? "").trim(),
        );
      }
    }
  } catch (e) {
    if (kDebugMode) debugPrint("Update manifest fetch error: $e");
  }
  final release = await getLatestGitHubRelease();
  if (release == null) return null;
  return UpdateManifest(
    version: release.version,
    apkUrl: release.apkUrl,
    notes: release.releaseNotes.trim(),
  );
}
