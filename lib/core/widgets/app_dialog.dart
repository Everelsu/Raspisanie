import "package:flutter/material.dart";

import "app_action_button.dart";

/// Диалог в стиле приложения: иконка в цветном кружке, заголовок,
/// необязательная подпись, содержимое и кнопки [AppActionButton].
///
/// Заменяет голый AlertDialog: у материаловского другой радиус, другие
/// отступы и другие кнопки, из-за чего всплывашки выбивались из карточек.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.icon,
    required this.title,
    required this.actions,
    this.subtitle,
    this.content,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? content;

  /// До двух кнопок встают в строку, больше — столбиком: три подписи в
  /// строке не помещаются и режутся многоточием.
  final List<AppActionButton> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.primary.withAlpha(24),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 20, color: cs.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (content != null) ...[
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(child: content),
              ),
            ],
            const SizedBox(height: 18),
            if (actions.length <= 2)
              Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: actions[i]),
                  ],
                ],
              )
            else
              Column(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    SizedBox(width: double.infinity, child: actions[i]),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}
