import "package:flutter/material.dart";

import "../data/holidays.dart";

/// Праздничная карточка внутри карточки дня: 1 сентября, 8 марта и т.д.
/// Общая для основного расписания и истории.
/// Цвет берём у самого праздника, а не у темы — так он и узнаётся.
class HolidayCard extends StatelessWidget {
  const HolidayCard(this.holiday, {super.key});

  final Holiday holiday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = Color(holiday.color);
    // Подмешиваем к цвету поверхности: чистый акцент в светлой теме
    // читается плохо, а в тёмной светит из карточки.
    final textColor = Color.alphaBlend(
      accent.withAlpha(cs.brightness == Brightness.dark ? 255 : 220),
      cs.onSurface,
    );

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withAlpha(26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withAlpha(70)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withAlpha(40),
            ),
            child: Text(holiday.emoji, style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  holiday.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                if (holiday.subtitle != null)
                  Text(
                    holiday.subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
