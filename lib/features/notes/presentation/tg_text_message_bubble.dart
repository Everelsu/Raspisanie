import "package:flutter/material.dart";
import "package:flutter_markdown/flutter_markdown.dart";
import "package:markdown/markdown.dart" as md;

/// Текстовый пузырь в стиле Telegram: Markdown (**жирный**, *курсив*) и кликабельные ссылки.
class TgTextMessageBubble extends StatelessWidget {
  const TgTextMessageBubble({
    super.key,
    required this.text,
    required this.isSentByMe,
    required this.onLinkTap,
  });

  final String text;
  final bool isSentByMe;
  final void Function(String url) onLinkTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final body = theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 16);

    final bgColor = isSentByMe ? cs.primary : cs.surfaceContainerHighest;
    final textColor = isSentByMe ? cs.onPrimary : cs.onSurface;
    final linkColor = isSentByMe ? cs.onPrimary : cs.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Align(
        alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Material(
          color: bgColor,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: MarkdownBody(
              data: text.isEmpty ? " " : text,
              extensionSet: md.ExtensionSet.gitHubFlavored,
              styleSheet: MarkdownStyleSheet(
                p: body.copyWith(color: textColor, height: 1.35),
                strong: body.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                ),
                em: body.copyWith(
                  color: textColor,
                  fontStyle: FontStyle.italic,
                ),
                a: body.copyWith(
                  color: linkColor,
                  decoration: TextDecoration.underline,
                  decorationColor: linkColor,
                ),
                listBullet: body.copyWith(color: textColor),
                listIndent: 24,
                code: body.copyWith(
                  color: textColor,
                  fontSize: 14,
                  fontFamily: "monospace",
                ),
              ),
              onTapLink: (text, href, title) {
                if (href != null && href.isNotEmpty) onLinkTap(href);
              },
              shrinkWrap: true,
            ),
          ),
        ),
      ),
    );
  }
}
