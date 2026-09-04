import "package:flutter/material.dart";

import "../../app/theme.dart" show contentBottomPadding;

/// Всплывающее уведомление в стиле приложения.
///
/// Материаловский SnackBar по умолчанию садится у самого низа экрана, где его
/// перекрывает [BottomBarWithSheet], а бесхитростный тёмный прямоугольник
/// выбивается из карточек. Здесь: иконка в цветном квадрате, фон карточки с
/// подмешанным акцентом, рамка и отступ ровно над нижним баром.
void showAppSnack(
  BuildContext context,
  String message, {
  IconData? icon,
  bool isError = false,
  Duration duration = const Duration(milliseconds: 2200),
  SnackBarAction? action,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final accent = isError ? cs.error : cs.primary;
  final surface = theme.cardTheme.color ?? cs.surface;

  // Предыдущее сообщение не копим в очередь: подряд идущие действия
  // (скопировал, потом поделился) иначе показывались с задержкой.
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withAlpha(36),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              icon ??
                  (isError ? Icons.error_outline_rounded : Icons.check_rounded),
              size: 16,
              color: accent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      action: action,
      duration: duration,
      backgroundColor: Color.alphaBlend(accent.withAlpha(20), surface),
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accent.withAlpha(70)),
      ),
      // Тот же расчёт, что у контента списков, — уведомление встаёт вплотную
      // над нижним баром, а не зависает посреди экрана.
      margin: EdgeInsets.fromLTRB(12, 0, 12, contentBottomPadding(context) - 8),
      dismissDirection: DismissDirection.horizontal,
    ),
  );
}
