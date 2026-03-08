import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_markdown_plus/flutter_markdown_plus.dart";
import "package:url_launcher/url_launcher.dart";

import "app_update_service.dart";
import "github_update_service.dart";

/// Диалог «Доступно обновление» с релиз-нотами и кнопкой «Установить».
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({
    super.key,
    required this.release,
    required this.currentVersion,
    required this.theme,
  });
  final GitHubReleaseInfo release;
  final String currentVersion;
  final ThemeData theme;

  static const String releasesUrl = "https://github.com/Everelsu/Raspisanie/releases";

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: theme.cardTheme.color ?? theme.colorScheme.surface,
      title: Row(
        children: [
          Icon(Icons.system_update_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Доступно обновление",
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Версия ${release.version} (у вас $currentVersion)",
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          if (release.releaseNotes.isNotEmpty) ...[
            Text("Что нового:", style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            SizedBox(
              height: 180,
              child: SingleChildScrollView(
                child: MarkdownBody(
                  data: release.releaseNotes,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                    p: theme.textTheme.bodySmall,
                    listBullet: theme.textTheme.bodySmall,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Позже"),
        ),
        if (Platform.isAndroid)
          FilledButton.icon(
            onPressed: () => _startDownload(context),
            icon: const Icon(Icons.download_rounded, size: 20),
            label: const Text("Установить"),
          )
        else
          TextButton.icon(
            onPressed: () => _openReleases(context),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text("Скачать на GitHub"),
          ),
      ],
    );
  }

  Future<void> _startDownload(BuildContext context) async {
    Navigator.pop(context);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DownloadProgressDialog(apkUrl: release.apkUrl),
    );
  }

  Future<void> _openReleases(BuildContext context) async {
    Navigator.pop(context);
    final uri = Uri.parse(releasesUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}

/// Диалог с прогрессом загрузки и установкой.
class _DownloadProgressDialog extends StatefulWidget {
  const _DownloadProgressDialog({required this.apkUrl});
  final String apkUrl;

  @override
  State<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  double _progress = 0;
  String _status = "Загрузка…";
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final path = await downloadApk(widget.apkUrl, onProgress: (p) {
      if (mounted) setState(() => _progress = p);
    });
    if (!mounted) return;
    if (path == null) {
      setState(() {
        _error = "Не удалось скачать обновление";
        _done = true;
      });
      return;
    }
    setState(() => _status = "Установка…");
    final ok = await installApk(path);
    if (!mounted) return;
    setState(() {
      _done = true;
      if (ok) {
        _status = "Готово. Откройте установщик.";
      } else {
        _error = "Не удалось запустить установку";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text("Обновление"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            )
          else ...[
            Text(_status, style: theme.textTheme.bodyMedium),
            if (!_done) ...[
              const SizedBox(height: 8),
              Text(
                "${(_progress * 100).round()}%",
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: _done ? 1.0 : _progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (_done)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
      ],
    );
  }
}
