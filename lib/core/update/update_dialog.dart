import "dart:io";
import "../widgets/app_snack.dart";

import "package:flutter/material.dart";
import "package:flutter_markdown_plus/flutter_markdown_plus.dart";
import "package:url_launcher/url_launcher.dart";

import "app_update_controller.dart";
import "changelog_page.dart";

/// Показывает диалог обновления для [AppUpdateController.available].
/// Закрытие любым способом, кроме запуска установки, откладывает следующее
/// напоминание на сутки ([AppUpdateController.snoozePrompt]).
Future<void> showAppUpdateDialog(
  BuildContext context, {
  required String currentVersion,
}) async {
  final controller = AppUpdateController.instance;
  if (controller.available == null) return;
  final installing = await showDialog<bool>(
    context: context,
    builder: (ctx) => UpdateDialog(currentVersion: currentVersion),
  );
  if (installing != true) {
    await controller.snoozePrompt();
  }
}

/// Диалог «Доступно обновление» / «Обновление скачано».
/// Подписан на [AppUpdateController]: показывает прогресс автозагрузки,
/// release-ноты из манифеста и кнопку «Установить», когда APK готов.
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key, required this.currentVersion});
  final String currentVersion;

  static const String releasesUrl =
      "https://github.com/Everelsu/Raspisanie/releases";

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = AppUpdateController.instance;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final update = controller.available;
        if (update == null) {
          // Обновление исчезло (например, уже установлено) — закрываемся.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.canPop(context)) Navigator.pop(context);
          });
          return const SizedBox.shrink();
        }
        final downloaded = controller.stage == AppUpdateStage.downloaded;
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.system_update_rounded,
                  color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  downloaded ? "Обновление скачано" : "Доступно обновление",
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Версия ${update.version} (у вас $currentVersion)",
                style: theme.textTheme.titleSmall,
              ),
              if (update.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text("Что нового:", style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: SingleChildScrollView(
                    child: MarkdownBody(
                      data: update.notes,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                        p: theme.textTheme.bodySmall,
                        listBullet: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                ),
              ],
              if (controller.downloading) ...[
                const SizedBox(height: 14),
                Text(
                  "Загрузка… ${(controller.progress * 100).round()}%",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: controller.progress > 0 ? controller.progress : null,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
              ] else if (controller.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  controller.error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ChangelogPage(),
                    ),
                  ),
                  child: const Text("Весь журнал изменений"),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Позже"),
            ),
            if (!Platform.isAndroid)
              TextButton.icon(
                onPressed: () => _openReleases(context),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text("Скачать на GitHub"),
              )
            else if (downloaded)
              FilledButton.icon(
                onPressed: () => _install(context, controller),
                icon: const Icon(Icons.install_mobile_rounded, size: 20),
                label: const Text("Установить"),
              )
            else
              FilledButton.icon(
                onPressed:
                    controller.downloading ? null : () => controller.download(),
                icon: const Icon(Icons.download_rounded, size: 20),
                label: Text(controller.error != null ? "Повторить" : "Скачать"),
              ),
          ],
        );
      },
    );
  }

  Future<void> _install(
    BuildContext context,
    AppUpdateController controller,
  ) async {
    final ok = await controller.install();
    if (!context.mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      showAppSnack(
        context,
        "Не удалось запустить установку",
        isError: true,
      );
    }
  }

  Future<void> _openReleases(BuildContext context) async {
    Navigator.pop(context, true);
    try {
      await launchUrl(
        Uri.parse(releasesUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  }
}
