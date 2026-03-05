import "package:flutter/material.dart";

import "../../domain/chat_message.dart";

class PinnedBanner extends StatelessWidget {
  const PinnedBanner({
    super.key,
    required this.message,
    required this.onTap,
    required this.onClose,
  });

  final ChatMessage message;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final preview = _previewText(message);

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.4),
          width: 0.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Icon(Icons.push_pin_rounded, size: 16, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    preview,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface,
                      fontSize: 13,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
                  onPressed: onClose,
                  tooltip: "Открепить",
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _previewText(ChatMessage m) {
    switch (m.type) {
      case "image":
        return m.text.isEmpty ? "Фото" : m.text;
      case "voice":
        return "Голосовое ${m.text} с";
      case "file":
        return m.text.isEmpty ? "Файл" : m.text;
      case "system":
        return m.text.isEmpty ? "Системное" : m.text;
      default:
        return m.text.length > 48 ? "${m.text.substring(0, 48)}…" : m.text;
    }
  }
}
