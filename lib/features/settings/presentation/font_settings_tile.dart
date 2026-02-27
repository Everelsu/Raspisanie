import "package:flutter/material.dart";

import "../../../core/services/font_service.dart";

class FontSettingsTile extends StatelessWidget {
  const FontSettingsTile({
    super.key,
    required this.fontService,
  });

  final FontService fontService;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListenableBuilder(
      listenable: fontService,
      builder: (context, _) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Шрифт приложения", style: theme.textTheme.bodyLarge),
                const SizedBox(height: 6),
                Text(
                  "Применяется сразу ко всему интерфейсу",
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.7,
                  children: AppFont.values.map((font) {
                    final selected = fontService.current == font;
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => fontService.setFont(font),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: selected
                              ? cs.primary.withAlpha(24)
                              : cs.surfaceContainerHighest.withAlpha(90),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected ? cs.primary : cs.outlineVariant,
                            width: selected ? 1.6 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Аа",
                              style: fontService.previewStyle(
                                font,
                                color: selected ? cs.primary : cs.onSurface,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              fontService.displayName(font),
                              style: fontService.previewStyle(
                                font,
                                color: cs.onSurfaceVariant,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
