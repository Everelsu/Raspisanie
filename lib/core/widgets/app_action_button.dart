import "package:flutter/material.dart";
import "package:flutter/services.dart";

/// Кнопка-действие внутри карточки или шторки: акцентная для основного
/// действия, приглушённая для второстепенного.
///
/// Один стиль на всё приложение — иначе кнопки разъезжаются от экрана к
/// экрану (было: FilledButton, FilledButton.tonalIcon и OutlinedButton
/// вперемешку). Диалоговые кнопки (Отмена/ОК) сюда не относятся — у них своя
/// роль и материаловские стили уместны.
class AppActionButton extends StatelessWidget {
  const AppActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;

  /// null — кнопка выключена.
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tap = onTap;
    final enabled = tap != null;
    final fg = !enabled
        ? cs.onSurface.withAlpha(90)
        : (primary ? cs.primary : cs.onSurfaceVariant);
    final borderColor = !enabled
        ? cs.onSurface.withAlpha(20)
        : (primary ? cs.primary.withAlpha(64) : cs.onSurface.withAlpha(30));
    final radius = BorderRadius.circular(14);

    return Material(
      color: primary && enabled ? cs.primary.withAlpha(22) : Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: !enabled
            ? null
            : () {
                HapticFeedback.selectionClick();
                tap();
              },
        borderRadius: radius,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Крупная строка-действие для нижних шторок: круглая иконка, название,
/// подпись. Тот же язык форм, что у [AppActionButton] — рамка и радиус 14.
class AppActionTile extends StatelessWidget {
  const AppActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.caption,
  });

  final IconData icon;
  final String label;
  final String? caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final radius = BorderRadius.circular(14);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: radius,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: cs.onSurface.withAlpha(30)),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.primary.withAlpha(22),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 19, color: cs.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (caption != null)
                        Text(
                          caption!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: cs.onSurfaceVariant.withAlpha(120)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
