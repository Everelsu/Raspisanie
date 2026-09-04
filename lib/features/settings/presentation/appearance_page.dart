import "dart:io";

import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../../../app/theme.dart" show AppThemeColors, AppThemes;
import "../../../core/widgets/app_action_button.dart";
import "../../../core/services/analytics_service.dart";
import "../../../core/services/app_icon_service.dart";
import "../../../core/services/font_service.dart";
import "../../../core/widgets/refresh_logo_mark.dart";
import "../../schedule/data/preferences_manager.dart";
import "../../schedule/presentation/schedule_controller.dart";
import "widgets/settings_ui.dart";

/// Содержимое карточки «Оформление»: тема, иконка приложения, шрифт,
/// эффекты и виджет — сворачиваемые подразделы внутри общей карточки
/// настроек. Логика вынесена в свой State, чтобы не раздувать SettingsPage.
class AppearanceSections extends StatefulWidget {
  const AppearanceSections({
    super.key,
    required this.controller,
    required this.onThemeChanged,
    required this.fontService,
  });

  final ScheduleController controller;
  final VoidCallback onThemeChanged;
  final FontService fontService;

  @override
  State<AppearanceSections> createState() => _AppearanceSectionsState();
}

class _AppearanceSectionsState extends State<AppearanceSections> {
  PreferencesManager get prefs => widget.controller.prefs;
  ScheduleController get ctrl => widget.controller;

  Widget _divider(ThemeData theme) => settingsDivider(theme);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeName = AppThemes.allThemes[prefs.theme] ?? prefs.theme;

    return ListenableBuilder(
      listenable: widget.fontService,
      builder: (context, _) {
        final fontName =
            widget.fontService.displayName(widget.fontService.current);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsSubsectionExpander(
              icon: Icons.color_lens_rounded,
              title: "Тема",
              subtitle: themeName,
              initiallyExpanded: true,
              builder: (context) => _themeSection(theme),
            ),
            _divider(theme),
            if (Platform.isAndroid) ...[
              SettingsSubsectionExpander(
                icon: Icons.apps_rounded,
                title: "Иконка приложения",
                subtitle: prefs.appIcon == "auto"
                    ? "Как тема"
                    : AppThemes.allThemes[prefs.appIcon] ?? prefs.appIcon,
                builder: (context) => _appIconSection(theme),
              ),
              _divider(theme),
            ],
            SettingsSubsectionExpander(
              icon: Icons.text_fields_rounded,
              title: "Шрифт",
              subtitle: fontName,
              builder: (context) => _fontSection(theme),
            ),
            _divider(theme),
            SettingsSubsectionExpander(
              icon: Icons.auto_awesome_rounded,
              title: "Эффекты",
              builder: (context) => _effectsSection(theme),
            ),
            _divider(theme),
            SettingsSubsectionExpander(
              icon: Icons.widgets_rounded,
              title: "Виджет на главном экране",
              builder: (context) => _widgetSection(theme),
            ),
          ],
        );
      },
    );
  }

  Widget _fontSection(ThemeData theme) {
    final cs = theme.colorScheme;
    const fontSizeKeys = [
      PreferencesManager.fontSizeSmall,
      PreferencesManager.fontSizeNormal,
      PreferencesManager.fontSizeLarge,
      PreferencesManager.fontSizeExtraLarge,
    ];
    const fontSizeLabels = ["Мелкий", "Обычный", "Крупный", "Очень крупный"];
    final sizeIdx = fontSizeKeys.indexOf(prefs.fontSize).clamp(0, 3);

    return ListenableBuilder(
      listenable: widget.fontService,
      builder: (context, _) {
        final selectedFont = widget.fontService.current;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GridView.builder(
                    primary: false,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemCount: AppFont.values.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      mainAxisExtent: 60,
                    ),
                    itemBuilder: (context, index) {
                      final font = AppFont.values[index];
                      final selected = selectedFont == font;

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () async {
                            HapticFeedback.lightImpact();
                            await widget.fontService.setFont(font);
                            // Виджет тоже перерисовываем выбранным шрифтом.
                            widget.controller.refreshHomeWidgetTheme();
                            await AnalyticsService.instance.logFontChanged(
                                widget.fontService.displayName(font));
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: selected
                                  ? cs.primary.withAlpha(25)
                                  : theme.scaffoldBackgroundColor,
                              border: Border.all(
                                color: selected
                                    ? cs.primary
                                    : cs.onSurface.withAlpha(30),
                                width: selected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  "Аа",
                                  style: widget.fontService.previewStyle(
                                    font,
                                    color: selected ? cs.primary : cs.onSurface,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    widget.fontService.displayName(font),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: widget.fontService.previewStyle(
                                      font,
                                      color: selected
                                          ? cs.primary
                                          : cs.onSurface.withAlpha(200),
                                      fontSize: 12,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (selected)
                                  Icon(
                                    Icons.check_circle_rounded,
                                    size: 16,
                                    color: cs.primary,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            _divider(theme),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SettingsSubsectionLabel("Размер шрифта"),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Размер текста",
                              style: theme.textTheme.bodyLarge,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              "Масштаб в расписании и настройках",
                              style: theme.textTheme.bodySmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        fontSizeLabels[sizeIdx],
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: sizeIdx.toDouble(),
                    min: 0,
                    max: 3,
                    divisions: 3,
                    onChanged: (v) {
                      setState(
                        () => prefs.fontSize = fontSizeKeys[v.round()],
                      );
                    },
                    onChangeEnd: (_) => widget.onThemeChanged(),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: fontSizeLabels
                        .map(
                          (l) => Text(
                            l,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Color _effectivePrimaryForTheme(String themeKey, AppThemeColors colors) {
    final v = prefs.accentColorForTheme(themeKey);
    return v != null ? Color(v) : colors.primary;
  }

  void _syncAppIcon() {
    AppIconService.setIcon(prefs.effectiveAppIcon);
  }

  Widget _appIconSection(ThemeData theme) {
    final selected = prefs.appIcon;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _themeSwatchRow(
            theme,
            selected: selected,
            onSelect: (key) {
              setState(() => prefs.appIcon = key);
              _syncAppIcon();
            },
          ),
          const SizedBox(height: 8),
          Text(
            selected == "auto"
                ? "Иконка следует выбранной теме"
                : "Иконка: ${AppThemes.allThemes[selected] ?? selected}",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 15, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  "После смены иконки система на секунду перезапустит приложение",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _themeSection(ThemeData theme) {
    final currentTheme = prefs.theme;
    final entries = AppThemes.allThemes.entries.toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsSubsectionLabel("Удержи тему для выбора акцента"),
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: entries.map((entry) {
                  final isSelected = entry.key == currentTheme;
                  final colors = AppThemes.colorsFor(entry.key);
                  final primary = _effectivePrimaryForTheme(entry.key, colors);
                  final name = entry.value;

                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      prefs.theme = entry.key;
                      widget.onThemeChanged();
                      ctrl.refreshHomeWidgetTheme();
                      _syncAppIcon();
                      AnalyticsService.instance.logThemeChanged(entry.key);
                    },
                    onLongPress: () {
                      HapticFeedback.mediumImpact();
                      _showThemeOptionsSheet(theme, entry.key, name, colors);
                    },
                    child: SizedBox(
                      width: tileWidth,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.cardTheme.color,
                          borderRadius: BorderRadius.circular(14),
                          border: isSelected
                              ? Border.all(color: primary, width: 2)
                              : Border.all(
                                  color: theme.colorScheme.onSurface
                                      .withAlpha(20)),
                        ),
                        child: Column(
                          children: [
                            Container(
                              height: 48,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: colors.surface,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: colors.surface,
                                        borderRadius:
                                            const BorderRadius.horizontal(
                                                left: Radius.circular(10)),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 4,
                                    child: Container(color: colors.card),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: primary,
                                        borderRadius:
                                            const BorderRadius.horizontal(
                                                right: Radius.circular(10)),
                                      ),
                                      child: isSelected
                                          ? Icon(Icons.check,
                                              size: 16,
                                              color:
                                                  primary.computeLuminance() >
                                                          0.5
                                                      ? Colors.black87
                                                      : Colors.white)
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(name,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showThemeOptionsSheet(
    ThemeData theme,
    String themeKey,
    String themeName,
    AppThemeColors colors,
  ) {
    final primary = _effectivePrimaryForTheme(themeKey, colors);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.15),
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        themeName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                AppActionButton(
                  icon: Icons.check_circle_outline,
                  label: "Применить тему",
                  primary: true,
                  onTap: () {
                    prefs.theme = themeKey;
                    widget.onThemeChanged();
                    ctrl.refreshHomeWidgetTheme();
                    _syncAppIcon();
                    AnalyticsService.instance.logThemeChanged(themeKey);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                ),
                const SizedBox(height: 10),
                AppActionButton(
                  icon: Icons.palette_outlined,
                  label: "Акцентный цвет",
                  onTap: () {
                    Navigator.of(ctx).pop();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _showAccentColorPicker(theme, themeKey: themeKey);
                      }
                    });
                  },
                ),
                if (prefs.accentColorForTheme(themeKey) != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () {
                      prefs.setAccentColorForTheme(themeKey, null);
                      widget.onThemeChanged();
                      ctrl.refreshHomeWidgetTheme();
                      AnalyticsService.instance.logAccentChanged(
                        themeKey: themeKey,
                        accentValue: null,
                        source: "reset",
                      );
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    },
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text("Сбросить акцент"),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAccentColorPicker(ThemeData theme, {String? themeKey}) {
    final targetThemeKey = themeKey ?? prefs.theme;
    final accentValue = prefs.accentColorForTheme(targetThemeKey);
    double customHue = 0.5;
    double customSaturation = 0.85;
    double customLightness = 0.55;
    if (accentValue != null) {
      final hsl = HSLColor.fromColor(Color(accentValue));
      customHue = (hsl.hue / 360.0).clamp(0.0, 1.0);
      customSaturation = hsl.saturation.clamp(0.0, 1.0);
      customLightness = hsl.lightness.clamp(0.0, 1.0);
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.cardTheme.color,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final cs = theme.colorScheme;
            // Flutter HSLColor.fromAHSL: hue 0–360°, saturation & lightness 0–1
            final hueDeg = (customHue.clamp(0.0, 1.0) * 360.0);
            final sat = customSaturation.clamp(0.0, 1.0);
            final light = customLightness.clamp(0.0, 1.0);
            final customColor =
                HSLColor.fromAHSL(1, hueDeg, sat, light).toColor();

            void apply(Color? color, String source) {
              HapticFeedback.lightImpact();
              prefs.setAccentColorForTheme(targetThemeKey, color?.toARGB32());
              widget.onThemeChanged();
              ctrl.refreshHomeWidgetTheme();
              AnalyticsService.instance.logAccentChanged(
                themeKey: targetThemeKey,
                accentValue: color?.toARGB32(),
                source: source,
              );
              if (ctx.mounted) Navigator.of(ctx).pop();
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    20, 10, 20, 20 + MediaQuery.of(ctx).viewPadding.bottom),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: cs.onSurface.withAlpha(60),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: customColor,
                              border: Border.all(
                                color: cs.onSurface.withAlpha(35),
                              ),
                            ),
                            child: accentValue == null
                                ? Icon(Icons.palette_rounded,
                                    size: 18,
                                    color: customColor.computeLuminance() > 0.5
                                        ? Colors.black87
                                        : Colors.white)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Акцентный цвет",
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "Тема «${AppThemes.allThemes[targetThemeKey] ?? targetThemeKey}»",
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          if (accentValue != null)
                            IconButton(
                              tooltip: "Сбросить акцент",
                              onPressed: () => apply(null, "reset"),
                              icon: Icon(Icons.restore_rounded,
                                  color: cs.onSurfaceVariant),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final color in AppThemes.accentPalette)
                            _AccentSwatch(
                              color: color,
                              selected: accentValue == color.toARGB32(),
                              onTap: () => apply(color, "palette"),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        "Свой цвет",
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      _AccentSlider(
                        label: "Оттенок",
                        value: customHue,
                        trackGradient: LinearGradient(colors: [
                          for (var i = 0; i <= 6; i++)
                            HSLColor.fromAHSL(1, i * 60.0, sat, light)
                                .toColor(),
                        ]),
                        onChanged: (v) => setSheetState(() => customHue = v),
                      ),
                      _AccentSlider(
                        label: "Насыщенность",
                        value: customSaturation,
                        trackGradient: LinearGradient(colors: [
                          HSLColor.fromAHSL(1, hueDeg, 0, light).toColor(),
                          HSLColor.fromAHSL(1, hueDeg, 1, light).toColor(),
                        ]),
                        onChanged: (v) =>
                            setSheetState(() => customSaturation = v),
                      ),
                      _AccentSlider(
                        label: "Яркость",
                        value: customLightness,
                        trackGradient: LinearGradient(colors: [
                          const Color(0xFF000000),
                          HSLColor.fromAHSL(1, hueDeg, sat, 0.5).toColor(),
                          const Color(0xFFFFFFFF),
                        ]),
                        onChanged: (v) =>
                            setSheetState(() => customLightness = v),
                      ),
                      const SizedBox(height: 4),
                      AppActionButton(
                        icon: Icons.check_rounded,
                        label: "Применить свой цвет",
                        primary: true,
                        onTap: () => apply(customColor, "custom"),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _themeSwatchRow(
    ThemeData theme, {
    required String selected,
    required ValueChanged<String> onSelect,
  }) {
    Widget tile(String key) {
      final colors = AppThemes.colorsFor(key == "auto" ? prefs.theme : key);
      final isSelected = selected == key;
      return Tooltip(
        message: key == "auto" ? "Как тема" : (AppThemes.allThemes[key] ?? key),
        child: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            onSelect(key);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: colors.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withAlpha(30),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Center(
              child: key == "auto"
                  ? Icon(Icons.autorenew_rounded,
                      size: 20, color: colors.primary)
                  : RefreshLogoMark(size: 20, color: colors.primary),
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        tile("auto"),
        for (final key in AppIconService.themedIcons) tile(key),
      ],
    );
  }

  Widget _effectsSection(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _widgetToggleRow(
            theme,
            "Растворение контента у нижнего края",
            prefs.contentEdgeFade,
            (v) {
              setState(() => prefs.contentEdgeFade = v);
              // HomePage читает флаг в build — форсим пересборку дерева.
              widget.onThemeChanged();
            },
          ),
        ],
      ),
    );
  }

  Widget _widgetToggleRow(
    ThemeData theme,
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _widgetSection(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsSubsectionLabel("Тема виджета"),
          _themeSwatchRow(
            theme,
            selected: prefs.widgetUseAppTheme ? "auto" : prefs.widgetTheme,
            onSelect: (key) {
              setState(() {
                if (key == "auto") {
                  prefs.widgetUseAppTheme = true;
                } else {
                  prefs.widgetUseAppTheme = false;
                  prefs.widgetTheme = key;
                }
              });
              ctrl.refreshHomeWidgetTheme();
            },
          ),
          const SizedBox(height: 8),
          Text(
            prefs.widgetUseAppTheme
                ? "Виджет следует выбранной теме"
                : "Тема виджета: ${AppThemes.allThemes[prefs.widgetTheme] ?? prefs.widgetTheme}",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          const SettingsSubsectionLabel("Что показывать"),
          _widgetToggleRow(
            theme,
            "Время пар",
            prefs.widgetShowTime,
            (v) {
              setState(() => prefs.widgetShowTime = v);
              ctrl.refreshHomeWidgetTheme();
            },
          ),
          _widgetToggleRow(
            theme,
            "Аудитория и преподаватель",
            prefs.widgetShowDetails,
            (v) {
              setState(() => prefs.widgetShowDetails = v);
              ctrl.refreshHomeWidgetTheme();
            },
          ),
          _widgetToggleRow(
            theme,
            "Строка «Обновлено»",
            prefs.widgetShowFooter,
            (v) {
              setState(() => prefs.widgetShowFooter = v);
              ctrl.refreshHomeWidgetTheme();
            },
          ),
          const SizedBox(height: 16),
          const SettingsSubsectionLabel("Размер текста"),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Размер шрифта в виджете",
                        style: theme.textTheme.bodyLarge),
                    Text(
                      "Масштаб текста на экране телефона",
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "${(prefs.widgetFontScale * 100).round()}%",
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Slider(
            value: prefs.widgetFontScale.clamp(0.9, 1.35).toDouble(),
            min: 0.9,
            max: 1.35,
            divisions: 9,
            onChanged: (v) => setState(() => prefs.widgetFontScale = v),
            onChangeEnd: (_) => ctrl.refreshHomeWidgetTheme(),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("90%",
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              Text("135%",
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        width: selected ? 48 : 44,
        height: selected ? 48 : 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurface.withAlpha(38),
            width: selected ? 3 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withAlpha(selected ? 130 : 60),
              blurRadius: selected ? 12 : 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: selected
            ? Icon(
                Icons.check_rounded,
                size: 22,
                color: color.computeLuminance() > 0.5
                    ? Colors.black87
                    : Colors.white,
              )
            : null,
      ),
    );
  }
}

class _AccentSlider extends StatelessWidget {
  const _AccentSlider({
    required this.label,
    required this.value,
    required this.trackGradient,
    required this.onChanged,
  });

  final String label;
  final double value;
  final Gradient trackGradient;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          SizedBox(
            height: 30,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 10,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    gradient: trackGradient,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 10,
                    activeTrackColor: Colors.transparent,
                    inactiveTrackColor: Colors.transparent,
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 16),
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 9),
                  ),
                  child: Slider(
                    value: value.clamp(0.0, 1.0),
                    onChanged: onChanged,
                    min: 0,
                    max: 1,
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
