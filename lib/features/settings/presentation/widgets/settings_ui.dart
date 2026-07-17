import "package:flutter/material.dart";
import "package:flutter/services.dart";

/// Заголовок секции настроек: иконка в цветном кружке + подпись капсом.
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader(this.icon, this.text, {super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primary.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 13, color: cs.primary),
          ),
          const SizedBox(width: 8),
          Text(text,
              style: theme.textTheme.titleSmall?.copyWith(letterSpacing: 1.0)),
        ],
      ),
    );
  }
}

/// Подпись группы настроек внутри карточки — используется, когда одна
/// карточка объединяет несколько логически разных настроек (как уже было
/// в _dbSettingsCard) и их нужно визуально разделить.
class SettingsSubsectionLabel extends StatelessWidget {
  const SettingsSubsectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Строка настройки с переключателем (заголовок + подпись + Switch).
Widget settingsSwitchTile(
  ThemeData theme,
  String title,
  String subtitle,
  bool value,
  ValueChanged<bool> onChanged,
) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: theme.textTheme.bodyLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              Text(subtitle,
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: (v) {
            HapticFeedback.selectionClick();
            onChanged(v);
          },
        ),
      ],
    ),
  );
}

/// Тонкий разделитель между строками настроек внутри одной карточки.
Widget settingsDivider(ThemeData theme) {
  return Divider(
    height: 1,
    indent: 16,
    endIndent: 16,
    color: theme.dividerTheme.color,
  );
}

/// Сворачиваемый подраздел внутри карточки настроек — без own Card, тоньше
/// [SettingsCollapsibleCard]. Используется, когда одна карточка объединяет
/// несколько логически разных групп настроек (например «Оформление»:
/// тема, иконка, шрифт, эффекты, виджет) и каждую хочется свернуть отдельно.
class SettingsSubsectionExpander extends StatefulWidget {
  const SettingsSubsectionExpander({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.initiallyExpanded = false,
    required this.builder,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool initiallyExpanded;
  final WidgetBuilder builder;

  @override
  State<SettingsSubsectionExpander> createState() =>
      _SettingsSubsectionExpanderState();
}

class _SettingsSubsectionExpanderState
    extends State<SettingsSubsectionExpander> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _expanded = !_expanded);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.primary.withAlpha(_expanded ? 28 : 16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(widget.icon, size: 15, color: cs.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.subtitle != null)
                        Text(
                          widget.subtitle!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more_rounded,
                      size: 20, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _expanded
              ? widget.builder(context)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Сворачиваемая карточка настроек: заголовок всегда виден, тело
/// раскрывается по тапу (по образцу карточки «Время пар»).
/// Тело (builder) само отвечает за свои внутренние отступы/разделители.
class SettingsCollapsibleCard extends StatefulWidget {
  const SettingsCollapsibleCard({
    super.key,
    required this.title,
    this.subtitle,
    this.badge,
    this.icon,
    this.initiallyExpanded = false,
    required this.builder,
  });

  final String title;
  final String? subtitle;
  final String? badge;
  final IconData? icon;
  final bool initiallyExpanded;
  final WidgetBuilder builder;

  @override
  State<SettingsCollapsibleCard> createState() =>
      _SettingsCollapsibleCardState();
}

class _SettingsCollapsibleCardState extends State<SettingsCollapsibleCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _expanded = !_expanded);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: cs.primary.withAlpha(_expanded ? 32 : 18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(widget.icon, size: 19, color: cs.primary),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.title,
                                style: theme.textTheme.bodyLarge
                                    ?.copyWith(fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (widget.badge != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: cs.primary.withAlpha(20),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  widget.badge!,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                      color: cs.primary,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle!,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _expanded
                          ? cs.onSurface.withAlpha(18)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.expand_more_rounded,
                          size: 20, color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Divider(height: 1, color: theme.dividerTheme.color),
                      widget.builder(context),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
