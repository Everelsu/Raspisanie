import "dart:convert";

import "package:flutter/foundation.dart";
import "package:http/http.dart" as http;

import "github_references.dart";

/// Результат последнего релиза с GitHub.
class GitHubReleaseInfo {
  const GitHubReleaseInfo({
    required this.version,
    required this.apkUrl,
    required this.releaseNotes,
  });
  final String version;
  final String apkUrl;
  final String releaseNotes;
}

/// Получает последний релиз из GitHub API и ссылку на APK.
Future<GitHubReleaseInfo?> getLatestGitHubRelease() async {
  final url = "https://api.github.com/repos/${GitHubReferences.owner}/${GitHubReferences.repo}/releases/latest";
  final headers = <String, String>{
    "Accept": "application/vnd.github.v3+json",
  };
  if (GitHubReferences.token.isNotEmpty) {
    headers["Authorization"] = "Bearer ${GitHubReferences.token}";
  }
  try {
    final response = await http.get(Uri.parse(url), headers: headers);
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final tagName = data["tag_name"] as String? ?? "";
    final version = tagName.startsWith("v") ? tagName.substring(1) : tagName;
    final body = data["body"] as String? ?? "";
    final assets = data["assets"] as List<dynamic>? ?? [];
    String? apkUrl;
    for (final asset in assets) {
      final name = (asset as Map<String, dynamic>)["name"] as String? ?? "";
      if (!name.endsWith(".apk")) continue;
      if (GitHubReferences.apkKey.isEmpty) {
        apkUrl = asset["browser_download_url"] as String?;
        break;
      }
      if (name.contains(GitHubReferences.apkKey)) {
        apkUrl = asset["browser_download_url"] as String?;
        break;
      }
    }
    if (apkUrl == null || apkUrl.isEmpty) return null;
    return GitHubReleaseInfo(version: version, apkUrl: apkUrl, releaseNotes: body);
  } catch (e) {
    if (kDebugMode) debugPrint("GitHub release fetch error: $e");
    return null;
  }
}
