import "package:flutter/material.dart";

/// Общий виджет пустого состояния: иконка в круге, заголовок и опциональный подзаголовок.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.icon,
    required this.message,
    this.subtitle,
    this.isError = false,
    this.semanticsLabel,
  });

  final IconData icon;
  final String message;
  final String? subtitle;
  final bool isError;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = isError ? cs.error : cs.primary;
    final label = semanticsLabel ?? message;

    return Semantics(
      label: label,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withAlpha(18),
                  border: Border.all(
                    color: color.withAlpha(isError ? 50 : 35),
                    width: 1,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 40,
                  color: isError ? color : color.withAlpha(180),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: isError ? color : null,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
