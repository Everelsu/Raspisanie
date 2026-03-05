import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_markdown/flutter_markdown.dart";

import "../../domain/chat_message.dart";

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.onLongPress,
  });

  final ChatMessage message;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
            child: Material(
              color: cs.primary,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: _buildContent(context, true),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool isSent) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final textColor = isSent ? cs.onPrimary : cs.onSurface;

    switch (message.type) {
      case "voice":
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_rounded, color: textColor, size: 24),
            const SizedBox(width: 8),
            Text(
              "Голосовое ${message.text} с",
              style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
            ),
          ],
        );
      case "image":
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.payload != null && message.payload!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildImage(message.payload!, textColor),
              ),
            if (message.text.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(message.text, style: theme.textTheme.bodyMedium?.copyWith(color: textColor)),
            ],
          ],
        );
      case "system":
        return Text(
          message.text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: textColor.withValues(alpha: 0.8),
            fontStyle: FontStyle.italic,
          ),
        );
      default:
        return MarkdownBody(
          data: message.text.isEmpty ? " " : message.text,
          styleSheet: MarkdownStyleSheet(
            p: theme.textTheme.bodyMedium?.copyWith(color: textColor, height: 1.35),
            strong: theme.textTheme.bodyMedium?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
            em: theme.textTheme.bodyMedium?.copyWith(
              color: textColor,
              fontStyle: FontStyle.italic,
            ),
          ),
          shrinkWrap: true,
        );
    }
  }

  Widget _buildImage(String path, Color textColor) {
    if (path.startsWith("http")) {
      return Image.network(
        path,
        width: 200,
        height: 200,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(Icons.broken_image, color: textColor, size: 48),
      );
    }
    final file = File(path);
    if (!file.existsSync()) {
      return Icon(Icons.broken_image, color: textColor, size: 48);
    }
    return Image.file(
      file,
      width: 200,
      height: 200,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Icon(Icons.broken_image, color: textColor, size: 48),
    );
  }
}
