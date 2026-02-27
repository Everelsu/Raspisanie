import "dart:io";

import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:path_provider/path_provider.dart";
import "package:share_plus/share_plus.dart";
import "package:url_launcher/url_launcher.dart";

import "../../../app/theme.dart";
import "../../../core/database/schedule_database.dart";
import "../../../core/services/font_service.dart";
import "../../notes/data/backup_import_export_service.dart";
import "../../schedule/data/preferences_manager.dart";
import "../../schedule/domain/models.dart";
import "../../schedule/presentation/schedule_controller.dart";
import "font_settings_tile.dart";

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    required this.onThemeChanged,
    required this.fontService,
  });
  final ScheduleController controller;
  final VoidCallback onThemeChanged;
  final FontService fontService;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  ScheduleController get ctrl => widget.controller;
  PreferencesManager get prefs => ctrl.prefs;
  bool _loadingGroups = false;
  int _dbRetentionDays = 90;
  int _dbRecords = 0;
  bool _dbBusy = false;
  bool _dbTransferBusy = false;
  int? _lastDbBackupAt;
  bool _notesBackupBusy = false;
  int? _lastNotesBackupAt;
  final _backupService = BackupImportExportService();

  @override
  void initState() {
    super.initState();
    _loadDbSettings();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          children: [
            _section(theme, "ОСНОВНОЕ"),
            _modeCard(theme),
            const SizedBox(height: 12),
            _collegeCard(theme),
            const SizedBox(height: 12),
            _groupCard(theme),
            const SizedBox(height: 20),
            _section(theme, "РАСПИСАНИЕ"),
            _displayCard(theme),
            const SizedBox(height: 12),
            _fontSizeCard(theme),
            const SizedBox(height: 12),
            FontSettingsTile(fontService: widget.fontService),
            const SizedBox(height: 20),
            _section(theme, "ДАННЫЕ"),
            _notesBackupCard(theme),
            const SizedBox(height: 12),
            _dbSettingsCard(theme),
            const SizedBox(height: 20),
            _section(theme, "ВИДЖЕТ"),
            _widgetCard(theme),
            const SizedBox(height: 20),
            _section(theme, "ОФОРМЛЕНИЕ"),
            _themeGrid(theme),
            const SizedBox(height: 12),
            _notesCardThemeCard(theme),
            const SizedBox(height: 20),
            _section(theme, "О ПРИЛОЖЕНИИ"),
            _appInfoCard(theme),
            const SizedBox(height: 40),
          ],
        );
      },
    );
  }

  Future<void> _loadDbSettings() async {
    final saved =
        await ScheduleDatabase.instance.getDatabaseSetting("retention_days");
    final lastBackup = await ScheduleDatabase.instance
        .getDatabaseSetting("notes_last_backup_at");
    final lastDbBackup = await ScheduleDatabase.instance
        .getDatabaseSetting("db_last_backup_at");
    final parsed = int.tryParse(saved ?? "");
    final parsedBackup = int.tryParse(lastBackup ?? "");
    final parsedDbBackup = int.tryParse(lastDbBackup ?? "");
    final count = await ScheduleDatabase.instance.getSnapshotCount();
    if (!mounted) return;
    setState(() {
      _dbRetentionDays = (parsed ?? 90).clamp(14, 365);
      _dbRecords = count;
      _lastNotesBackupAt = parsedBackup;
      _lastDbBackupAt = parsedDbBackup;
    });
  }

  Widget _section(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(text,
          style: theme.textTheme.titleSmall?.copyWith(letterSpacing: 1.0)),
    );
  }

  Widget _modeCard(ThemeData theme) {
    final isTeacher = prefs.isTeacherMode;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Я...", style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _modeButton(
                      theme, "Студент", Icons.school_outlined, !isTeacher, () {
                    ctrl.setUserMode("student");
                    _loadGroupsAsync();
                  }),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _modeButton(
                      theme, "Преподаватель", Icons.person_outline, isTeacher,
                      () {
                    ctrl.setUserMode("teacher");
                    _loadGroupsAsync();
                  }),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeButton(ThemeData theme, String label, IconData icon,
      bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: selected
          ? null
          : () {
              HapticFeedback.lightImpact();
              onTap();
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected
              ? theme.colorScheme.primary.withAlpha(25)
              : theme.scaffoldBackgroundColor,
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withAlpha(30),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withAlpha(120)),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _collegeCard(ThemeData theme) {
    const colleges = [
      ("ЧТОТиБ", "chtotib"),
      ("ЗабГК", "zabgc"),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Техникум", style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: ctrl.college,
              decoration: InputDecoration(
                filled: true,
                fillColor: theme.scaffoldBackgroundColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              dropdownColor: theme.cardTheme.color,
              items: colleges
                  .map((c) => DropdownMenuItem(
                        value: c.$2,
                        child: Text(c.$1, style: theme.textTheme.bodyLarge),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  ctrl.setCollege(v);
                  _loadGroupsAsync();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupCard(ThemeData theme) {
    final selected = ctrl.selectedGroup;
    final isTeacher = prefs.isTeacherMode;
    final label = isTeacher ? "Преподаватель" : "Группа";

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Выберите ${label.toLowerCase()}",
                    style: theme.textTheme.bodySmall),
                GestureDetector(
                  onTap: _loadingGroups ? null : _loadGroupsAsync,
                  child: _loadingGroups
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : Text(
                          "Обновить",
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: ctrl.groups.isEmpty
                  ? _loadGroupsAsync
                  : () => _showGroupBottomSheet(theme),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.onSurface.withAlpha(30),
                  ),
                ),
                child: Row(
                  children: [
                    if (selected != null &&
                        prefs.isFavoriteGroup(selected.name))
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(Icons.star,
                            color: theme.colorScheme.primary, size: 18),
                      ),
                    Expanded(
                      child: Text(
                        selected?.name.isNotEmpty == true
                            ? selected!.name
                            : (prefs.selectedGroupName.isNotEmpty
                                ? prefs.selectedGroupName
                                : "Нажмите для выбора"),
                        style: selected != null
                            ? theme.textTheme.bodyLarge
                            : theme.textTheme.bodyMedium?.copyWith(
                                color:
                                    theme.colorScheme.onSurface.withAlpha(120)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.expand_more,
                        color: theme.colorScheme.onSurface.withAlpha(100)),
                  ],
                ),
              ),
            ),
            if (selected != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final name = selected.name;
                        if (prefs.isFavoriteGroup(name)) {
                          prefs.removeFavoriteGroup(name);
                        } else {
                          prefs.addFavoriteGroup(name);
                        }
                        setState(() {});
                      },
                      icon: Icon(
                        prefs.isFavoriteGroup(selected.name)
                            ? Icons.star
                            : Icons.star_border,
                        size: 18,
                      ),
                      label: Text(
                        prefs.isFavoriteGroup(selected.name)
                            ? "В избранном"
                            : "В избранное",
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: theme.colorScheme.primary.withAlpha(80)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showGroupBottomSheet(ThemeData theme) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _GroupSelectorSheet(
        groups: ctrl.groups,
        favorites: prefs.favoriteGroups,
        selected: ctrl.selectedGroup,
        isTeacher: prefs.isTeacherMode,
        onSelect: (g) {
          Navigator.pop(ctx);
          ctrl.selectGroup(g);
          ctrl.loadSchedule();
        },
        onToggleFavorite: (name) {
          if (prefs.isFavoriteGroup(name)) {
            prefs.removeFavoriteGroup(name);
          } else {
            prefs.addFavoriteGroup(name);
          }
          setState(() {});
        },
      ),
    );
  }

  Future<void> _loadGroupsAsync() async {
    setState(() => _loadingGroups = true);
    await ctrl.loadGroups(force: true);
    if (mounted) setState(() => _loadingGroups = false);
  }

  Widget _displayCard(ThemeData theme) {
    return Card(
      child: Column(
        children: [
          _switchTile(theme, "Показывать перемены", "Перемены между парами",
              prefs.showBreaks, (v) {
            setState(() => prefs.showBreaks = v);
          }),
          _divider(theme),
          _switchTile(
              theme, "Показывать обеды", "Обеденные перерывы", prefs.showLunch,
              (v) {
            setState(() => prefs.showLunch = v);
          }),
          _divider(theme),
          _switchTile(theme, "Показывать время", "Время начала и окончания пар",
              prefs.showTime, (v) {
            setState(() => prefs.showTime = v);
          }),
          _divider(theme),
          _switchTile(theme, "Подсветка текущей пары",
              "Выделять текущую и следующую", prefs.showLessonStatus, (v) {
            setState(() => prefs.showLessonStatus = v);
          }),
          _divider(theme),
          _switchTile(theme, "Кэширование",
              "Сохранять данные для работы офлайн", prefs.cacheEnabled, (v) {
            setState(() => prefs.cacheEnabled = v);
          }),
          _divider(theme),
          _switchTile(
              theme,
              "Автообновление",
              "Обновлять расписание каждые ${prefs.autoRefreshInterval} мин",
              prefs.autoRefreshEnabled, (v) {
            setState(() {
              prefs.autoRefreshEnabled = v;
              if (v) {
                ctrl.startAutoRefresh();
              } else {
                ctrl.stopAutoRefresh();
              }
            });
          }),
        ],
      ),
    );
  }

  Widget _switchTile(ThemeData theme, String title, String subtitle, bool value,
      ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyLarge),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _divider(ThemeData theme) {
    return Divider(
      height: 1,
      indent: 16,
      endIndent: 16,
      color: theme.dividerTheme.color,
    );
  }

  Widget _fontSizeCard(ThemeData theme) {
    const sizes = [
      PreferencesManager.fontSizeSmall,
      PreferencesManager.fontSizeNormal,
      PreferencesManager.fontSizeLarge,
      PreferencesManager.fontSizeExtraLarge,
    ];
    const labels = ["Мелкий", "Обычный", "Крупный", "Очень крупный"];
    final idx = sizes.indexOf(prefs.fontSize).clamp(0, 3);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Размер шрифта", style: theme.textTheme.bodyLarge),
                Text(labels[idx],
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              "Изменение размера текста в расписании.",
              style: theme.textTheme.bodySmall,
            ),
            Slider(
              value: idx.toDouble(),
              min: 0,
              max: 3,
              divisions: 3,
              onChanged: (v) {
                setState(() => prefs.fontSize = sizes[v.round()]);
              },
              onChangeEnd: (_) => widget.onThemeChanged(),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: labels
                  .map((l) => Text(l,
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 10)))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _themeGrid(ThemeData theme) {
    final currentTheme = prefs.theme;
    final entries = AppThemes.allThemes.entries.toList();

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: entries.map((entry) {
        final isSelected = entry.key == currentTheme;
        final colors = AppThemes.colorsFor(entry.key);
        final name = entry.value.$1;
        final desc = entry.value.$2;

        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            prefs.theme = entry.key;
            widget.onThemeChanged();
            ctrl.refreshHomeWidgetTheme();
          },
          child: SizedBox(
            width: (MediaQuery.of(context).size.width - 42) / 2,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.cardTheme.color,
                borderRadius: BorderRadius.circular(14),
                border: isSelected
                    ? Border.all(color: colors.primary, width: 2)
                    : Border.all(
                        color: theme.colorScheme.onSurface.withAlpha(20)),
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
                              borderRadius: const BorderRadius.horizontal(
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
                              color: colors.primary,
                              borderRadius: const BorderRadius.horizontal(
                                  right: Radius.circular(10)),
                            ),
                            child: isSelected
                                ? const Icon(Icons.check,
                                    size: 16, color: Colors.white)
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
                  const SizedBox(height: 2),
                  Text(desc,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _notesCardThemeCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Темные карточки заметок",
                    style: theme.textTheme.bodyLarge,
                  ),
                  Text(
                    "Использовать более темные цвета карточек в заметках",
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Switch(
              value: prefs.notesDarkCards,
              onChanged: (v) => setState(() => prefs.notesDarkCards = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _widgetCard(ThemeData theme) {
    const themeOptions = [
      (PreferencesManager.themeDark, "Тёмная"),
      (PreferencesManager.themeLight, "Светлая"),
      (PreferencesManager.themeGreen, "Зелёная"),
      (PreferencesManager.themePink, "Розовая"),
      (PreferencesManager.themeBlue, "Синяя"),
      (PreferencesManager.themeGray, "Серая"),
      (PreferencesManager.themePurple, "Фиолетовая"),
      (PreferencesManager.themeOrange, "Оранжевая"),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "Синхронизировать тему виджета с приложением",
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                Switch(
                  value: prefs.widgetUseAppTheme,
                  onChanged: (v) {
                    setState(() {
                      prefs.widgetUseAppTheme = v;
                      // Keep manual widget theme aligned with the current app theme
                      // when user disables sync, so there is no sudden visual jump.
                      if (!v) {
                        prefs.widgetTheme = prefs.theme;
                      }
                    });
                    ctrl.refreshHomeWidgetTheme();
                  },
                ),
              ],
            ),
            if (!prefs.widgetUseAppTheme) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: prefs.widgetTheme,
                decoration: const InputDecoration(
                  labelText: "Тема виджета",
                ),
                items: themeOptions
                    .map(
                      (e) => DropdownMenuItem<String>(
                        value: e.$1,
                        child: Text(e.$2),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => prefs.widgetTheme = v);
                  ctrl.refreshHomeWidgetTheme();
                },
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Размер шрифта в виджете",
                    style: theme.textTheme.bodyLarge),
                Text(
                  "${(prefs.widgetFontScale * 100).round()}%",
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.primary),
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
          ],
        ),
      ),
    );
  }

  Widget _appInfoCard(ThemeData theme) {
    const link = "https://everelsu.github.io/RelsevLink/";
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Raspisanie", style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text("v2.0.0", style: theme.textTheme.bodySmall),
                  ],
                ),
                IconButton(
                  onPressed: () => _checkForUpdate(theme),
                  icon: Icon(Icons.system_update_outlined,
                      color: theme.colorScheme.primary),
                  tooltip: "Проверить обновления",
                ),
              ],
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primary.withAlpha(24),
                child: Text(
                  "@",
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              title: Text("@Relsev", style: theme.textTheme.bodyLarge),
              subtitle: Text(link, style: theme.textTheme.bodySmall),
              trailing: Icon(Icons.open_in_new_rounded, color: theme.colorScheme.primary),
              onTap: () async {
                final uri = Uri.parse(link);
                final opened = await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                );
                if (opened || !mounted) return;
                await Clipboard.setData(const ClipboardData(text: link));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Не удалось открыть, ссылка скопирована")),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _dbSettingsCard(ThemeData theme) {
    final lastDbBackupText = _lastDbBackupAt == null
        ? "не выполнялся"
        : DateTime.fromMillisecondsSinceEpoch(_lastDbBackupAt!).toString();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "История хранения: $_dbRetentionDays дней",
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withAlpha(10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "$_dbRecords записей",
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              "Сколько дневных записей сохранять для истории расписания.",
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              "Последний экспорт БД: $lastDbBackupText",
              style: theme.textTheme.bodySmall,
            ),
            Slider(
              value: _dbRetentionDays.toDouble(),
              min: 14,
              max: 365,
              divisions: 351,
              onChanged: (v) {
                setState(() => _dbRetentionDays = v.round());
              },
              onChangeEnd: (v) async {
                await ScheduleDatabase.instance.saveDatabaseSetting(
                    "retention_days", v.round().toString());
              },
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _dbTransferBusy
                        ? null
                        : _exportDatabase,
                    icon: const Icon(Icons.upload_file_outlined, size: 18),
                    label: const Text("Экспорт БД"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _dbTransferBusy
                        ? null
                        : _importDatabase,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text("Импорт БД"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _dbBusy
                        ? null
                        : () async {
                            setState(() => _dbBusy = true);
                            await ScheduleDatabase.instance.clearAll();
                            await _loadDbSettings();
                            if (mounted) {
                              setState(() => _dbBusy = false);
                            }
                          },
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text("Очистить БД"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notesBackupCard(ThemeData theme) {
    final lastBackupText = _lastNotesBackupAt == null
        ? "не выполнялся"
        : DateTime.fromMillisecondsSinceEpoch(_lastNotesBackupAt!).toString();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Локальный backup/import заметок",
                style: theme.textTheme.bodyLarge),
            const SizedBox(height: 6),
            Text(
              "Последний экспорт: $lastBackupText",
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _notesBackupBusy ? null : _exportNotes,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text("Экспорт"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _notesBackupBusy ? null : _importNotes,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text("Импорт"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportNotes() async {
    setState(() => _notesBackupBusy = true);
    try {
      await _backupService.exportNotes();
      final ts = DateTime.now().millisecondsSinceEpoch;
      await ScheduleDatabase.instance
          .saveDatabaseSetting("notes_last_backup_at", ts.toString());
      if (mounted) {
        setState(() => _lastNotesBackupAt = ts);
      }
    } finally {
      if (mounted) setState(() => _notesBackupBusy = false);
    }
  }

  Future<void> _importNotes() async {
    final replace = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Импорт заметок"),
            content: const Text(
              "Заменить существующие заметки полностью?\n\n"
              "Да — удалить текущие и импортировать файл.\n"
              "Нет — объединить с текущими.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Объединить"),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Заменить"),
              ),
            ],
          ),
        ) ??
        false;

    setState(() => _notesBackupBusy = true);
    try {
      await _backupService.importNotes(replace: replace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Импорт заметок завершен")),
        );
      }
    } finally {
      if (mounted) setState(() => _notesBackupBusy = false);
    }
  }

  Future<void> _exportDatabase() async {
    setState(() => _dbTransferBusy = true);
    try {
      final dbPath = await ScheduleDatabase.instance.databaseFilePath();
      final source = File(dbPath);
      if (!await source.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Файл базы данных не найден")),
        );
        return;
      }
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final outPath = "${dir.path}/raspiflutter_db_$ts.db";
      await source.copy(outPath);
      await Share.shareXFiles(
        [XFile(outPath)],
        subject: "Экспорт БД Raspiflutter",
        text: "Резервная копия базы данных",
      );
      await ScheduleDatabase.instance
          .saveDatabaseSetting("db_last_backup_at", ts.toString());
      if (mounted) setState(() => _lastDbBackupAt = ts);
    } finally {
      if (mounted) setState(() => _dbTransferBusy = false);
    }
  }

  Future<void> _importDatabase() async {
    final approved = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Импорт БД"),
            content: const Text(
              "Импорт заменит текущую базу данных целиком.\n\n"
              "Продолжить?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Отмена"),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Импорт"),
              ),
            ],
          ),
        ) ??
        false;
    if (!approved) return;

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ["db", "sqlite", "sqlite3"],
      withData: false,
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.single.path;
    if (path == null || path.isEmpty) return;

    setState(() => _dbTransferBusy = true);
    try {
      await ScheduleDatabase.instance.replaceDatabaseFromFile(path);
      await _loadDbSettings();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Импорт базы данных завершен")),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Не удалось импортировать базу данных")),
      );
    } finally {
      if (mounted) setState(() => _dbTransferBusy = false);
    }
  }

  void _checkForUpdate(ThemeData theme) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.cardTheme.color,
        title: const Text("Обновления"),
        content: const Text(
          "Для обновления приложения скачайте последнюю версию APK "
          "из репозитория на GitHub и установите вручную.\n\n"
          "Автообновление через GitHub Releases будет добавлено позже.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

}

class _GroupSelectorSheet extends StatefulWidget {
  const _GroupSelectorSheet({
    required this.groups,
    required this.favorites,
    required this.selected,
    required this.isTeacher,
    required this.onSelect,
    required this.onToggleFavorite,
  });

  final List<Group> groups;
  final Set<String> favorites;
  final Group? selected;
  final bool isTeacher;
  final ValueChanged<Group> onSelect;
  final ValueChanged<String> onToggleFavorite;

  @override
  State<_GroupSelectorSheet> createState() => _GroupSelectorSheetState();
}

class _GroupSelectorSheetState extends State<_GroupSelectorSheet> {
  String _query = "";

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = widget.groups.where((g) {
      if (_query.isEmpty) return true;
      return g.name.toLowerCase().contains(_query.toLowerCase());
    }).toList();

    final favGroups =
        filtered.where((g) => widget.favorites.contains(g.name)).toList();
    final otherGroups =
        filtered.where((g) => !widget.favorites.contains(g.name)).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withAlpha(40),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                autofocus: false,
                style: theme.textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: widget.isTeacher
                      ? "Поиск преподавателя..."
                      : "Поиск группы...",
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(100)),
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: theme.scaffoldBackgroundColor,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  if (favGroups.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child:
                          Text("ИЗБРАННЫЕ", style: theme.textTheme.titleSmall),
                    ),
                    ...favGroups.map((g) => _groupTile(theme, g, true)),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                      child: Text("ВСЕ", style: theme.textTheme.titleSmall),
                    ),
                  ],
                  ...otherGroups.map((g) => _groupTile(theme, g, false)),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _groupTile(ThemeData theme, Group g, bool isFav) {
    final isSelected = widget.selected?.id == g.id;
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      selected: isSelected,
      selectedTileColor: theme.colorScheme.primary.withAlpha(20),
      leading: isFav
          ? Icon(Icons.star, color: theme.colorScheme.primary, size: 20)
          : null,
      title: Text(g.name, style: theme.textTheme.bodyLarge),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
          : null,
      onTap: () => widget.onSelect(g),
      onLongPress: () {
        widget.onToggleFavorite(g.name);
        setState(() {});
      },
    );
  }
}
