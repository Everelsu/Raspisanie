import "dart:convert";
import "dart:io";

import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:http/http.dart" as http;
import "package:intl/intl.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:path_provider/path_provider.dart";
import "package:share_plus/share_plus.dart";
import "package:url_launcher/url_launcher.dart";


import "../../../app/theme.dart"
    show AppThemeColors, AppThemes, contentTopUnderAppBar;
import "../../../core/database/schedule_database.dart";
import "../../../core/services/analytics_service.dart";
import "../../../core/update/app_update_service.dart";
import "../../../core/update/github_http_client.dart";
import "../../../core/update/github_urls.dart";
import "../../../core/update/update_dialog.dart";
import "../../../core/storage/storage_cleanup.dart";
import "../../../core/background/app_update_background_worker.dart";
import "../../../core/background/schedule_background_worker.dart";
import "../../../core/services/font_service.dart";
import "../../schedule/data/lesson_times.dart";
import "../../schedule/data/preferences_manager.dart";
import "../../schedule/domain/models.dart";
import "../../schedule/presentation/schedule_controller.dart";

class _UrlProbeResult {
  const _UrlProbeResult({
    required this.ok,
    required this.message,
    required this.checkedAt,
  });

  final bool ok;
  final String message;
  final DateTime checkedAt;
}

class _CollegeSourcesSyncResult {
  const _CollegeSourcesSyncResult({
    required this.savedCount,
    required this.message,
    required this.checkedAt,
  });

  final int savedCount;
  final String message;
  final DateTime checkedAt;
}

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
  Map<int, LessonTime> _editingLessonTimes = {};
  bool _lessonTimesDirty = false;
  String _appVersion = "…";

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void initState() {
    super.initState();
    _loadDbSettings();
    _loadLessonTimesForSelectedCollege();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _appVersion = info.version);
    });
  }

  @override
  void dispose() {
    _dismissKeyboard();
    super.dispose();
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
          padding: EdgeInsets.fromLTRB(
            16,
            contentTopUnderAppBar(context),
            16,
            116,
          ),
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
            _lessonTimesCard(theme),
            const SizedBox(height: 20),
            _section(theme, "ДАННЫЕ"),
            _dbSettingsCard(theme),
            const SizedBox(height: 20),
            _section(theme, "ВИДЖЕТ"),
            _widgetCard(theme),
            const SizedBox(height: 20),
            _section(theme, "ОФОРМЛЕНИЕ"),
            _fontSettingsCard(theme),
            const SizedBox(height: 10),
            _fontSizeCard(theme),
            const SizedBox(height: 12),
            _themeGrid(theme),
            const SizedBox(height: 12),
            _section(theme, "О ПРИЛОЖЕНИИ"),
            _privacyCard(theme),
            const SizedBox(height: 20),
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
    final lastDbBackup = await ScheduleDatabase.instance
        .getDatabaseSetting("db_last_backup_at");
    final parsed = int.tryParse(saved ?? "");
    final parsedDbBackup = int.tryParse(lastDbBackup ?? "");
    final count = await ScheduleDatabase.instance.getSnapshotCount();
    if (!mounted) return;
    setState(() {
      _dbRetentionDays = (parsed ?? 90).clamp(14, 365);
      _dbRecords = count;
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

  Widget _fontSettingsCard(ThemeData theme) {
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return ListenableBuilder(
      listenable: widget.fontService,
      builder: (context, _) {
        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: cs.primary.withAlpha(isDark ? 30 : 20),
              width: 0.8,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            cs.primary.withAlpha(40),
                            cs.primary.withAlpha(20),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: cs.primary.withAlpha(50),
                          width: 0.8,
                        ),
                      ),
                      child: Icon(
                        Icons.text_fields_rounded,
                        size: 16,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Шрифт приложения",
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            "Интерфейс и «Поделиться днём»",
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 2.65,
                  children: AppFont.values.map((font) {
                    final selected = widget.fontService.current == font;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () async {
                          await widget.fontService.setFont(font);
                          await AnalyticsService.instance
                              .logFontChanged(widget.fontService.displayName(font));
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            gradient: selected
                                ? LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      cs.primary.withAlpha(isDark ? 50 : 36),
                                      cs.primary.withAlpha(isDark ? 28 : 18),
                                    ],
                                  )
                                : LinearGradient(
                                    colors: [
                                      cs.surfaceContainerHighest
                                          .withAlpha(isDark ? 100 : 80),
                                      cs.surfaceContainerHighest
                                          .withAlpha(isDark ? 70 : 55),
                                    ],
                                  ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected
                                  ? cs.primary.withAlpha(120)
                                  : cs.outlineVariant
                                      .withAlpha(isDark ? 80 : 100),
                              width: selected ? 1.4 : 0.8,
                            ),
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color: cs.primary.withAlpha(20),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                height: 22,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      "Аа",
                                      style: widget.fontService.previewStyle(
                                        font,
                                        color: selected
                                            ? cs.primary
                                            : cs.onSurface,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.fontService.displayName(font),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: widget.fontService.previewStyle(
                                  font,
                                  color: selected
                                      ? cs.primary.withAlpha(200)
                                      : cs.onSurfaceVariant,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
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
                    AnalyticsService.instance.logUserModeChanged("student");
                    ScheduleBackgroundWorker.ensureRegisteredIfNeeded(prefs: prefs);
                    _loadGroupsAsync();
                  }),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _modeButton(
                      theme, "Преподаватель", Icons.person_outline, isTeacher,
                      () {
                    ctrl.setUserMode("teacher");
                    AnalyticsService.instance.logUserModeChanged("teacher");
                    ScheduleBackgroundWorker.ensureRegisteredIfNeeded(prefs: prefs);
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
    final sources = prefs.allCollegeSources;
    final selectedCollege = ctrl.college;
    final hasSelected = sources.any((s) => s.id == selectedCollege);
    final initialValue = hasSelected
        ? selectedCollege
        : (sources.isNotEmpty ? sources.first.id : PreferencesManager.collegeDefault);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Источник расписания", style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: initialValue,
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
              items: sources
                  .map((source) => DropdownMenuItem(
                        value: source.id,
                        child: Text(source.name, style: theme.textTheme.bodyLarge),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  ctrl.setCollege(v);
                  AnalyticsService.instance.logCollegeChanged(v);
                  ScheduleBackgroundWorker.ensureRegisteredIfNeeded(prefs: prefs);
                  _loadGroupsAsync();
                  _loadLessonTimesForSelectedCollege();
                }
              },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _showCollegeSourcesSheet(theme),
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text("Управлять ссылками"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCollegeSourcesSheet(ThemeData theme) async {
    _dismissKeyboard();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final pingById = <String, _UrlProbeResult>{};
        final runningIds = <String>{};
        var syncRunning = false;
        _CollegeSourcesSyncResult? lastSync;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final sources = prefs.allCollegeSources;
            final syncedAt = prefs.syncedCollegeSourcesCheckedAt;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Ссылки", style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      "Можно добавить свой источник и выбрать его в списке техникумов.",
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: syncRunning
                            ? null
                            : () async {
                                setSheetState(() {
                                  syncRunning = true;
                                });
                                final result =
                                    await _syncCollegeSourcesFromRemote();
                                if (!mounted || !ctx.mounted) return;
                                setSheetState(() {
                                  syncRunning = false;
                                  lastSync = result;
                                });
                                setState(() {});
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text(result.message)),
                                  );
                                }
                              },
                        icon: syncRunning
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync_rounded),
                        label: Text(
                          syncRunning
                              ? "Синхронизация..."
                              : "Синхронизировать ссылки",
                        ),
                      ),
                    ),
                    if (lastSync != null || syncedAt != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        lastSync != null
                            ? "Последняя синхронизация: ${DateFormat('HH:mm').format(lastSync!.checkedAt)} • ${lastSync!.message}"
                            : "Последняя синхронизация: ${DateFormat('HH:mm').format(syncedAt!)}",
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.45,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: sources.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (_, i) {
                          final s = sources[i];
                          final selected = ctrl.college == s.id;
                          final isRunning = runningIds.contains(s.id);
                          final probe = pingById[s.id];
                          final probeColor = probe == null
                              ? theme.colorScheme.onSurfaceVariant
                              : (probe.ok
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.error);
                          return ListTile(
                            dense: true,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: selected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outlineVariant,
                              ),
                            ),
                            title: Text(s.name),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  s.baseUrl,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (isRunning)
                                  Text(
                                    'Проверяю...',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  )
                                else if (probe != null)
                                  Text(
                                    '${probe.message} • ${DateFormat('HH:mm').format(probe.checkedAt)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: probeColor,
                                    ),
                                  ),
                              ],
                            ),
                            leading: Icon(
                              s.builtIn
                                  ? Icons.lock_outline_rounded
                                  : Icons.link_rounded,
                              size: 18,
                              color: s.builtIn
                                  ? theme.colorScheme.onSurfaceVariant
                                  : theme.colorScheme.primary,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: "Копировать URL",
                                  onPressed: () async {
                                    await Clipboard.setData(
                                        ClipboardData(text: s.baseUrl));
                                    if (ctx.mounted) {
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        const SnackBar(
                                          content: Text("Ссылка скопирована"),
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.content_copy_rounded,
                                      size: 20),
                                ),
                                if (isRunning)
                                  const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: Padding(
                                      padding: EdgeInsets.all(2),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                else
                                  IconButton(
                                    tooltip: "Пинг (проверить доступность)",
                                    onPressed: () async {
                                      setSheetState(() {
                                        runningIds.add(s.id);
                                      });
                                      final result =
                                          await _probeCollegeSourceUrl(
                                        s.baseUrl,
                                      );
                                      if (!ctx.mounted || !mounted) return;
                                      setSheetState(() {
                                        runningIds.remove(s.id);
                                        pingById[s.id] = result;
                                      });
                                    },
                                    icon: const Icon(Icons.wifi_tethering_rounded,
                                        size: 20),
                                  ),
                                if (!s.builtIn) ...[
                                  IconButton(
                                    tooltip: "Изменить",
                                    onPressed: () async {
                                      _dismissKeyboard();
                                      final ok =
                                          await _showEditCollegeSourceDialog(s);
                                      if (!ok || !mounted || !ctx.mounted) {
                                        return;
                                      }
                                      ctrl.refreshCollegeSources();
                                      setSheetState(() {});
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.edit_outlined, size: 20),
                                  ),
                                  IconButton(
                                    tooltip: "Удалить",
                                    onPressed: () {
                                      final updated = prefs.customCollegeSources
                                          .where((e) => e.id != s.id)
                                          .toList();
                                      prefs.saveCustomCollegeSources(updated);
                                      ctrl.refreshCollegeSources();
                                      if (ctrl.college == s.id) {
                                        ctrl.setCollege(
                                            PreferencesManager.collegeDefault);
                                        _loadGroupsAsync();
                                      }
                                      setSheetState(() {});
                                      setState(() {});
                                    },
                                    icon: const Icon(
                                        Icons.delete_outline_rounded, size: 20),
                                  ),
                                ],
                              ],
                            ),
                            onTap: () {
                              ctrl.setCollege(s.id);
                              _loadGroupsAsync();
                              _loadLessonTimesForSelectedCollege();
                              setSheetState(() {});
                              setState(() {});
                            },
                            onLongPress: () async {
                              final u = Uri.tryParse(s.baseUrl);
                              if (u != null && await canLaunchUrl(u)) {
                                await launchUrl(u,
                                    mode: LaunchMode.externalApplication);
                              }
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: () async {
                          _dismissKeyboard();
                          final added = await _showAddCollegeSourceDialog();
                          if (!added || !mounted || !ctx.mounted) return;
                          ctrl.refreshCollegeSources();
                          setSheetState(() {});
                          setState(() {});
                        },
                        icon: const Icon(Icons.add_link_rounded),
                        label: const Text("Добавить ссылку"),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _showAddCollegeSourceDialog() async {
    _dismissKeyboard();
    var name = "";
    var rawUrl = "";
    String? validationError;
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                16 + MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Новый источник", style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      "Добавь только название и ссылку. Остальное создастся автоматически.",
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      autofocus: true,
                      textInputAction: TextInputAction.next,
                      onChanged: (value) {
                        setDialogState(() {
                          name = value;
                          validationError = null;
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: "Название",
                        hintText: "Мой колледж",
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                      onChanged: (value) {
                        setDialogState(() {
                          rawUrl = value;
                          validationError = null;
                        });
                      },
                      onSubmitted: (_) {
                        FocusManager.instance.primaryFocus?.unfocus();
                      },
                      decoration: const InputDecoration(
                        labelText: "Ссылка",
                        hintText: "https://example.ru/schedule/",
                      ),
                    ),
                    if (validationError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        validationError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              _dismissKeyboard();
                              Navigator.pop(ctx, false);
                            },
                            child: const Text("Отмена"),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              _dismissKeyboard();
                              final safeName = name.trim();
                              final safeId = _buildUniqueCollegeId(safeName);
                              final safeUrl = _normalizeBaseUrl(rawUrl);
                              if (safeName.isEmpty) {
                                setDialogState(() {
                                  validationError = "Введи название источника";
                                });
                                return;
                              }
                              if (safeId.isEmpty) {
                                setDialogState(() {
                                  validationError =
                                      "Не удалось создать ID источника";
                                });
                                return;
                              }
                              if (!_isValidHttpUrl(safeUrl)) {
                                setDialogState(() {
                                  validationError =
                                      "Проверь ссылку: нужен http/https и корректный домен";
                                });
                                return;
                              }
                              final updated = [
                                ...prefs.customCollegeSources,
                                CollegeSource(
                                  id: safeId,
                                  name: safeName,
                                  baseUrl: safeUrl,
                                ),
                              ];
                              prefs.saveCustomCollegeSources(updated);
                              Navigator.pop(ctx, true);
                            },
                            child: const Text("Добавить"),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    return added == true;
  }

  Future<_CollegeSourcesSyncResult> _syncCollegeSourcesFromRemote() async {
    final checkedAt = DateTime.now();
    try {
      final url = GitHubProjectUrls.scheduleTimesRaw.trim();
      final response = await GitHubHttpClient.get(
        url,
        headers: const {"Accept": "application/json, text/plain, */*"},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _CollegeSourcesSyncResult(
          savedCount: 0,
          message: "HTTP ${response.statusCode}",
          checkedAt: checkedAt,
        );
      }

      final raw = utf8.decode(response.bodyBytes);
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return _CollegeSourcesSyncResult(
          savedCount: 0,
          message: "Некорректный JSON",
          checkedAt: checkedAt,
        );
      }

      final sources = decoded["sources"];
      final colleges = (sources is Map<String, dynamic>) ? sources["colleges"] : null;
      if (colleges is! Map<String, dynamic>) {
        return _CollegeSourcesSyncResult(
          savedCount: 0,
          message: "В файле нет sources.colleges",
          checkedAt: checkedAt,
        );
      }

      final out = <String, CollegeSource>{};
      for (final e in colleges.entries) {
        final id = e.key.toString().trim().toLowerCase();
        final v = e.value;
        if (id.isEmpty || v is! Map<String, dynamic>) continue;
        final name = (v["name"] ?? "").toString().trim();
        final baseUrl = (v["baseUrl"] ?? "").toString().trim();
        if (name.isEmpty || baseUrl.isEmpty) continue;
        out[id] = CollegeSource(
          id: id,
          name: name,
          baseUrl: baseUrl,
          builtIn: true,
        );
      }

      prefs.saveSyncedCollegeSources(out);
      ctrl.refreshCollegeSources();
      return _CollegeSourcesSyncResult(
        savedCount: out.length,
        message: out.isEmpty ? "Нечего обновлять" : "Обновлено: ${out.length}",
        checkedAt: checkedAt,
      );
    } catch (e) {
      return _CollegeSourcesSyncResult(
        savedCount: 0,
        message: "Ошибка синхронизации",
        checkedAt: checkedAt,
      );
    }
  }

  Future<_UrlProbeResult> _probeCollegeSourceUrl(String rawUrl) async {
    final url = _normalizeBaseUrl(rawUrl);
    final checkedAt = DateTime.now();
    if (!_isValidHttpUrl(url)) {
      return _UrlProbeResult(
        ok: false,
        message: "Некорректный URL",
        checkedAt: checkedAt,
      );
    }

    try {
      final client = http.Client();
      try {
        late http.BaseResponse res;
        try {
          res = await client
              .head(Uri.parse(url))
              .timeout(const Duration(seconds: 12));
        } catch (_) {
          // Некоторые серверы запрещают HEAD — пробуем GET.
          res = await client
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 18));
        }

        final ok = res.statusCode >= 200 && res.statusCode < 400;
        final message =
            ok ? "Доступно (код ${res.statusCode})" : "HTTP ${res.statusCode}";
        return _UrlProbeResult(ok: ok, message: message, checkedAt: checkedAt);
      } finally {
        client.close();
      }
    } catch (e) {
      return _UrlProbeResult(
        ok: false,
        message: "Нет ответа",
        checkedAt: checkedAt,
      );
    }
  }

  Future<bool> _showEditCollegeSourceDialog(CollegeSource source) async {
    _dismissKeyboard();
    final nameCtrl = TextEditingController(text: source.name);
    final urlCtrl = TextEditingController(text: source.baseUrl);
    String? validationError;
    try {
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          final theme = Theme.of(ctx);
          return StatefulBuilder(
            builder: (ctx, setDialogState) {
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  16 + MediaQuery.viewInsetsOf(ctx).bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Изменить источник",
                          style: theme.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(
                        "ID: ${source.id} (не меняется)",
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameCtrl,
                        onChanged: (_) => setDialogState(() {
                          validationError = null;
                        }),
                        decoration: const InputDecoration(
                          labelText: "Название",
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: urlCtrl,
                        keyboardType: TextInputType.url,
                        onChanged: (_) => setDialogState(() {
                          validationError = null;
                        }),
                        decoration: const InputDecoration(
                          labelText: "Ссылка",
                        ),
                      ),
                      if (validationError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          validationError!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                _dismissKeyboard();
                                Navigator.pop(ctx, false);
                              },
                              child: const Text("Отмена"),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                _dismissKeyboard();
                                final safeName = nameCtrl.text.trim();
                                final safeUrl = _normalizeBaseUrl(urlCtrl.text);
                                if (safeName.isEmpty) {
                                  setDialogState(() {
                                    validationError = "Введи название";
                                  });
                                  return;
                                }
                                if (!_isValidHttpUrl(safeUrl)) {
                                  setDialogState(() {
                                    validationError =
                                        "Проверь ссылку: http/https и домен";
                                  });
                                  return;
                                }
                                final updated = prefs.customCollegeSources
                                    .map((e) {
                                      if (e.id != source.id) return e;
                                      return CollegeSource(
                                        id: source.id,
                                        name: safeName,
                                        baseUrl: safeUrl,
                                      );
                                    })
                                    .toList();
                                prefs.saveCustomCollegeSources(updated);
                                Navigator.pop(ctx, true);
                              },
                              child: const Text("Сохранить"),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
      return saved == true;
    } finally {
      nameCtrl.dispose();
      urlCtrl.dispose();
    }
  }

  String _normalizeBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return "";
    return trimmed.endsWith("/") ? trimmed : "$trimmed/";
  }

  bool _isValidHttpUrl(String value) {
    if (value.isEmpty) return false;
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    return uri.hasScheme &&
        (uri.scheme == "http" || uri.scheme == "https") &&
        uri.hasAuthority;
  }

  String _buildUniqueCollegeId(String name) {
    var base = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9]+"), "_")
        .replaceAll(RegExp(r"_+"), "_")
        .replaceAll(RegExp(r"^_+|_+$"), "");
    if (base.isEmpty) base = "college";
    final taken = prefs.allCollegeSources.map((s) => s.id).toSet();
    if (!taken.contains(base)) return base;
    var i = 2;
    while (taken.contains("${base}_$i")) {
      i++;
    }
    return "${base}_$i";
  }

  Widget _groupCard(ThemeData theme) {
    final selected = ctrl.selectedGroup;
    final isTeacher = prefs.isTeacherMode;
    final label = isTeacher ? "..." : "группу";

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
    _dismissKeyboard();
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
          _dismissKeyboard();
          Navigator.pop(ctx);
          ctrl.selectGroup(g);
          AnalyticsService.instance.logGroupSelected(
            groupName: g.name,
            isTeacherMode: prefs.isTeacherMode,
          );
          ScheduleBackgroundWorker.ensureRegisteredIfNeeded(prefs: prefs);
          ctrl.loadSchedule();
        },
        onToggleFavorite: (name) {
          if (prefs.isFavoriteGroup(name)) {
            prefs.removeFavoriteGroup(name);
          } else {
            prefs.addFavoriteGroup(name);
          }
          AnalyticsService.instance.logEvent("group_favorite_toggled", {
            "group": name,
            "is_favorite": prefs.isFavoriteGroup(name),
          });
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
              "Автообновление расписания",
              "Обновлять данные каждые ${prefs.autoRefreshInterval} мин и при открытии приложения",
              prefs.autoRefreshEnabled, (v) {
            setState(() {
              prefs.autoRefreshEnabled = v;
              if (v) {
                ctrl.startAutoRefresh();
              } else {
                ctrl.stopAutoRefresh();
              }
            });
            ScheduleBackgroundWorker.ensureRegisteredIfNeeded(prefs: prefs);
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
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(subtitle, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
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

  Widget _privacyCard(ThemeData theme) {
    return Card(
      child: Column(
        children: [
          _switchTile(
            theme,
            "Отправлять аналитику Firebase",
            "Отправка обезличенной аналитики (экраны и действия) — помогает улучшать приложение",
            prefs.analyticsEnabled,
            (v) async {
              setState(() => prefs.analyticsEnabled = v);
              await AnalyticsService.instance.setEnabled(v);
              AnalyticsService.instance.logEvent("analytics_toggled", {"enabled": v});
            },
          ),
        ],
      ),
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

  void _loadLessonTimesForSelectedCollege() {
    final college = ctrl.college;
    final custom = prefs.getCustomLessonTimes(college);
    final remote = prefs.getRemoteLessonTimes(college);
    final builtIn = LessonTimes.getBuiltInTimes(college);
    final source = custom ?? remote ?? builtIn;
    final sortedKeys = source.keys.toList()..sort();
    final normalized = <int, LessonTime>{};
    for (final key in sortedKeys) {
      final t = source[key];
      if (t == null) continue;
      normalized[key] = LessonTime(key, t.startTime, t.endTime);
    }
    if (!mounted) return;
    setState(() {
      _editingLessonTimes = normalized;
      _lessonTimesDirty = false;
    });
  }

  Future<void> _pickLessonTime({
    required int lessonNumber,
    required bool start,
  }) async {
    final current = _editingLessonTimes[lessonNumber];
    if (current == null) return;
    final initial = _parseTimeOfDay(start ? current.startTime : current.endTime) ??
        const TimeOfDay(hour: 8, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        final theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            colorScheme: theme.colorScheme,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked == null) return;
    final newTime = _formatTimeOfDay(picked);
    setState(() {
      _editingLessonTimes[lessonNumber] = LessonTime(
        lessonNumber,
        start ? newTime : current.startTime,
        start ? current.endTime : newTime,
      );
      _lessonTimesDirty = true;
    });
  }

  TimeOfDay? _parseTimeOfDay(String value) {
    final parts = value.split(":");
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _formatTimeOfDay(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, "0");
    final m = t.minute.toString().padLeft(2, "0");
    return "$h:$m";
  }

  Future<void> _saveLessonTimes() async {
    final college = ctrl.college;
    prefs.setCustomLessonTimes(college, _editingLessonTimes);
    LessonTimes.setCustomTimes(college: college, times: _editingLessonTimes);
    setState(() => _lessonTimesDirty = false);
    await ctrl.loadSchedule(useCache: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Время пар сохранено")),
    );
  }

  Future<void> _resetLessonTimes() async {
    final college = ctrl.college;
    final ok = await ctrl.refreshLessonTimesFromRemote(silent: true);
    if (!mounted) return;
    prefs.clearCustomLessonTimes(college);
    final remote = prefs.getRemoteLessonTimes(college);
    if (remote != null && remote.isNotEmpty) {
      LessonTimes.setCustomTimes(college: college, times: remote);
    } else {
      LessonTimes.clearCustomTimes(college);
    }
    _loadLessonTimesForSelectedCollege();
    await ctrl.loadSchedule(useCache: true);
    if (!mounted) return;
    if (ok && remote != null && remote.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Время пар загружено и применено")),
      );
    } else if (remote != null && remote.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Восстановлено сохранённое время пар")),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Возвращено стандартное время пар")),
      );
    }
  }

  Widget _lessonTimesCard(ThemeData theme) {
    final entries = _editingLessonTimes.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final collegeName = ctrl.college == PreferencesManager.collegeZabgc
        ? "ЗабГК"
        : "ЧТОТиБ";
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Время пар", style: theme.textTheme.bodyLarge),
            const SizedBox(height: 4),
            Text(
              "Для: $collegeName. Нажми на время, чтобы изменить.",
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              prefs.lessonTimesRemoteSyncedAt != null
                  ? "С GitHub: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(prefs.lessonTimesRemoteSyncedAt!))} · авто-проверка каждые ${prefs.lessonTimesMinIntervalHours} ч"
                  : "Время пар с репозитория подтянется при запуске / по кнопке «Сбросить».",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            const SizedBox(height: 10),
            ...entries.map((entry) {
              final lesson = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 58,
                      child: Text(
                        "${entry.key} пара",
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickLessonTime(
                          lessonNumber: entry.key,
                          start: true,
                        ),
                        child: Text(lesson.startTime),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text("—", style: theme.textTheme.bodyMedium),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickLessonTime(
                          lessonNumber: entry.key,
                          start: false,
                        ),
                        child: Text(lesson.endTime),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _lessonTimesDirty ? _saveLessonTimes : null,
                    child: const Text("Сохранить"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _resetLessonTimes,
                    child: const Text("Сбросить"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _effectivePrimaryForTheme(String themeKey, AppThemeColors colors) {
    final v = prefs.accentColorForTheme(themeKey);
    return v != null ? Color(v) : colors.primary;
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
        final primary = _effectivePrimaryForTheme(entry.key, colors);
        final name = entry.value;

        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            prefs.theme = entry.key;
            widget.onThemeChanged();
            ctrl.refreshHomeWidgetTheme();
            AnalyticsService.instance.logThemeChanged(entry.key);
          },
          onLongPress: () {
            HapticFeedback.mediumImpact();
            _showThemeOptionsSheet(theme, entry.key, name, colors);
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
                    ? Border.all(color: primary, width: 2)
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
                              color: primary,
                              borderRadius: const BorderRadius.horizontal(
                                  right: Radius.circular(10)),
                            ),
                            child: isSelected
                                ? Icon(Icons.check,
                                    size: 16,
                                    color: primary.computeLuminance() > 0.5
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
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
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
                FilledButton.icon(
                  onPressed: () {
                    prefs.theme = themeKey;
                    widget.onThemeChanged();
                    ctrl.refreshHomeWidgetTheme();
                    AnalyticsService.instance.logThemeChanged(themeKey);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                  icon: const Icon(Icons.check_circle_outline, size: 20),
                  label: const Text("Применить тему"),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _showAccentColorPicker(theme, themeKey: themeKey);
                    });
                  },
                  icon: const Icon(Icons.palette_outlined, size: 20),
                  label: const Text("Акцентный цвет"),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            // Flutter HSLColor.fromAHSL: hue 0–360°, saturation & lightness 0–1
            final hueDeg = (customHue.clamp(0.0, 1.0) * 360.0);
            final sat = customSaturation.clamp(0.0, 1.0);
            final light = customLightness.clamp(0.0, 1.0);
            final customColor = HSLColor.fromAHSL(1, hueDeg, sat, light).toColor();
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + MediaQuery.of(ctx).viewPadding.bottom),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        "Акцентный цвет",
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Для темы «${AppThemes.allThemes[targetThemeKey] ?? targetThemeKey}». По умолчанию — цвет темы.",
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          GestureDetector(
                            onTap: () {
                              prefs.setAccentColorForTheme(targetThemeKey, null);
                              widget.onThemeChanged();
                              ctrl.refreshHomeWidgetTheme();
                              AnalyticsService.instance.logAccentChanged(
                                themeKey: targetThemeKey,
                                accentValue: null,
                                source: "default",
                              );
                              if (ctx.mounted) Navigator.of(ctx).pop();
                            },
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: theme.scaffoldBackgroundColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: accentValue == null
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurface.withValues(alpha: 0.2),
                                  width: accentValue == null ? 2 : 1,
                                ),
                              ),
                              child: Icon(
                                Icons.palette_outlined,
                                color: theme.colorScheme.onSurfaceVariant,
                                size: 22,
                              ),
                            ),
                          ),
                          ...AppThemes.accentPalette.map((color) {
                            final isSelected = accentValue == color.toARGB32();
                            return GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                prefs.setAccentColorForTheme(targetThemeKey, color.toARGB32());
                                widget.onThemeChanged();
                                ctrl.refreshHomeWidgetTheme();
                                AnalyticsService.instance.logAccentChanged(
                                  themeKey: targetThemeKey,
                                  accentValue: color.toARGB32(),
                                  source: "palette",
                                );
                                if (ctx.mounted) Navigator.of(ctx).pop();
                              },
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? theme.colorScheme.onSurface
                                        : theme.colorScheme.onSurface.withValues(alpha: 0.25),
                                    width: isSelected ? 2.5 : 1,
                                  ),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: color.withValues(alpha: 0.4),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: isSelected
                                    ? Icon(
                                        Icons.check,
                                        size: 22,
                                        color: color.computeLuminance() > 0.5
                                            ? Colors.black87
                                            : Colors.white,
                                      )
                                    : null,
                              ),
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        "Свой цвет",
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: customColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text("Оттенок", style: theme.textTheme.labelSmall),
                                Slider(
                                  value: customHue,
                                  onChanged: (v) => setSheetState(() => customHue = v),
                                  min: 0,
                                  max: 1,
                                  activeColor: customColor,
                                ),
                                Text("Насыщенность", style: theme.textTheme.labelSmall),
                                Slider(
                                  value: customSaturation,
                                  onChanged: (v) => setSheetState(() => customSaturation = v),
                                  min: 0,
                                  max: 1,
                                  activeColor: customColor,
                                ),
                                Text("Яркость", style: theme.textTheme.labelSmall),
                                Slider(
                                  value: customLightness,
                                  onChanged: (v) => setSheetState(() => customLightness = v),
                                  min: 0,
                                  max: 1,
                                  activeColor: customColor,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          prefs.setAccentColorForTheme(targetThemeKey, customColor.toARGB32());
                          widget.onThemeChanged();
                          ctrl.refreshHomeWidgetTheme();
                          AnalyticsService.instance.logAccentChanged(
                            themeKey: targetThemeKey,
                            accentValue: customColor.toARGB32(),
                            source: "custom",
                          );
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        },
                        icon: const Icon(Icons.check, size: 20),
                        label: const Text("Применить свой цвет"),
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
      (PreferencesManager.themeRed, "Красная"),
      (PreferencesManager.themeTeal, "Жёлтая"),
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
    const authorLink = "https://everelsu.github.io/RelsevLink/";
    const releasesLink = "https://github.com/Everelsu/Raspisanie/releases";
    const authorAvatarUrl ="https://raw.githubusercontent.com/Everelsu/RelsevLink/main/avatar.png";
    const betaTesterLink = "https://t.me/skromniyvadya";
    const betaTesterAvatarUrl = "https://raw.githubusercontent.com/Everelsu/RelsevLink/6b2647524fe3ade73d931079e77f8225ccffd2f5/scromny.jpg";
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withAlpha(80),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.calendar_month_rounded,
                    size: 32,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Raspisanie",
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Версия $_appVersion",
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              "Обновления приложения",
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  _switchTile(
                    theme,
                    "Проверять при запуске",
                    "Показывать диалог обновления, если вышла новая версия",
                    prefs.autoCheckAppUpdate,
                    (v) async {
                      setState(() => prefs.autoCheckAppUpdate = v);
                      await AppUpdateBackgroundWorker.ensureRegistered(
                          prefs: prefs);
                    },
                  ),
                  _divider(theme),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Text(
                      "Обновления устанавливаются из GitHub.",
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _checkForUpdate(theme),
                        icon: const Icon(Icons.system_update_rounded, size: 20),
                        label: const Text("Проверить обновления"),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "Автор",
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Material(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(40),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () async {
                  final uri = Uri.parse(authorLink);
                  final opened = await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  );
                  if (opened || !mounted) return;
                  await Clipboard.setData(const ClipboardData(text: authorLink));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Ссылка скопирована"),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      _AuthorAvatar(avatarUrl: authorAvatarUrl, theme: theme),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Relsev",
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Material(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(40),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () async {
                  final uri = Uri.parse(betaTesterLink);
                  final opened = await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  );
                  if (opened || !mounted) return;
                  await Clipboard.setData(const ClipboardData(text: betaTesterLink));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Ссылка скопирована"),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      _AuthorAvatar(avatarUrl: betaTesterAvatarUrl, theme: theme),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Скромный Вадя",
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              "Бета‑тестер",
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final uri = Uri.parse(releasesLink);
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.code_rounded, size: 18),
              label: const Text("Релизы на GitHub"),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
              ),
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
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _dbBusy ? null : () async {
                      setState(() => _dbBusy = true);
                      await ScheduleDatabase.instance.clearAll();
                      await _loadDbSettings();
                      if (mounted) setState(() => _dbBusy = false);
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text("Очистить БД"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      StorageCleanup.clearAllPrefsCache(prefs.sharedPreferences);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Кэш расписания очищен")),
                        );
                      }
                    },
                    icon: const Icon(Icons.cached_outlined, size: 18),
                    label: const Text("Кэш"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await StorageCleanup.clearTempDirectory();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Временные файлы удалены")),
                    );
                  }
                },
                icon: const Icon(Icons.folder_off_outlined, size: 18),
                label: const Text("Очистить временные файлы"),
              ),
            ),
          ],
        ),
      ),
    );
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
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(outPath)],
          subject: "Экспорт БД Raspisanie",
          text: "Резервная копия базы данных",
        ),
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

  Future<void> _checkForUpdate(ThemeData theme) async {
    final release = await checkForUpdate();
    if (!mounted) return;
    if (release != null) {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      AnalyticsService.instance
          .logEvent("update_dialog_shown", {"version": release.version});
      showDialog(
        context: context,
        builder: (ctx) => UpdateDialog(
          release: release,
          currentVersion: info.version,
          theme: theme,
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: theme.cardTheme.color,
          title: const Text("Обновления"),
          content: const Text("У вас установлена последняя версия."),
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
}

class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar({required this.avatarUrl, required this.theme});
  final String avatarUrl;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 24,
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      child: ClipOval(
        child: Image.network(
          avatarUrl,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Center(
            child: Text(
              "@",
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
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
