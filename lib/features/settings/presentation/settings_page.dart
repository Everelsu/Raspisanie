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
    show AppThemes, contentBottomPadding, contentTopUnderAppBar;
import "../../../core/database/schedule_database.dart";
import "../../../core/widgets/app_icon_image.dart";
import "../../../core/services/analytics_service.dart";
import "../../../core/update/app_update_controller.dart";
import "../../../core/update/changelog_page.dart";
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
import "appearance_page.dart";
import "widgets/settings_ui.dart";

class _UrlProbeResult {
  const _UrlProbeResult({
    required this.ok,
    required this.message,
    this.latencyMs,
    required this.checkedAt,
  });

  final bool ok;
  final String message;
  final int? latencyMs;
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
  String _appVersion = "…";

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  String _formatFriendlySyncTime(DateTime value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(value.year, value.month, value.day);
    final dayDiff = today.difference(date).inDays;
    final time = DateFormat("HH:mm").format(value);
    if (dayDiff == 0) return "Сегодня в $time";
    if (dayDiff == 1) return "Вчера в $time";
    return DateFormat("dd.MM.yyyy HH:mm").format(value);
  }

  String _formatProbeCaption(_UrlProbeResult probe) {
    if (!probe.ok) return probe.message;
    final latency = probe.latencyMs;
    if (latency == null || latency <= 0) {
      return "Доступно";
    }
    return "Отклик: $latency мс";
  }

  @override
  void initState() {
    super.initState();
    _loadDbSettings();
    _loadLessonTimesForSelectedCollege();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _appVersion = info.version);
    });
    _maybeShowAccentHint();
  }

  void _maybeShowAccentHint() {
    final shown =
        prefs.sharedPreferences.getBool("hint_accent_longpress") ?? false;
    if (shown) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      prefs.sharedPreferences.setBool("hint_accent_longpress", true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.touch_app_outlined, size: 16, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                    "Удержи карточку темы — откроется выбор акцентного цвета"),
              ),
            ],
          ),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        ),
      );
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
            contentBottomPadding(context),
          ),
          children: [
            _modeCard(theme),
            const SizedBox(height: 12),
            _collegeCard(theme),
            const SizedBox(height: 12),
            _groupCard(theme),
            const SizedBox(height: 20),
            _displayCard(theme),
            const SizedBox(height: 10),
            _lessonTimesCard(theme),
            const SizedBox(height: 10),
            _dbSettingsCard(theme),
            const SizedBox(height: 10),
            _appearanceCard(theme),
            const SizedBox(height: 10),
            _updatesCard(theme),
            const SizedBox(height: 20),
            _creditsCard(theme),
            const SizedBox(height: 12),
            _appIdentityCard(theme),
            const SizedBox(height: 40),
          ],
        );
      },
    );
  }

  Future<void> _loadDbSettings() async {
    final saved =
        await ScheduleDatabase.instance.getDatabaseSetting("retention_days");
    final lastDbBackup =
        await ScheduleDatabase.instance.getDatabaseSetting("db_last_backup_at");
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


  Widget _appearanceCard(ThemeData theme) {
    final themeName = AppThemes.allThemes[prefs.theme] ?? prefs.theme;
    return ListenableBuilder(
      listenable: widget.fontService,
      builder: (context, _) {
        final fontName =
            widget.fontService.displayName(widget.fontService.current);
        return SettingsCollapsibleCard(
          icon: Icons.palette_rounded,
          title: "Оформление",
          subtitle: "$themeName • $fontName",
          builder: (context) => AppearanceSections(
            controller: widget.controller,
            onThemeChanged: widget.onThemeChanged,
            fontService: widget.fontService,
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
                    ScheduleBackgroundWorker.ensureRegisteredIfNeeded(
                        prefs: prefs);
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
                    ScheduleBackgroundWorker.ensureRegisteredIfNeeded(
                        prefs: prefs);
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
    final selectedSource =
        sources.where((s) => s.id == selectedCollege).isNotEmpty
            ? sources.firstWhere((s) => s.id == selectedCollege)
            : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Выберите техникум", style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => _showCollegeSourcesSheet(theme),
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
                    Expanded(
                      child: Text(
                        selectedSource?.name ?? "Нажмите для выбора",
                        style: selectedSource != null
                            ? theme.textTheme.bodyLarge
                            : theme.textTheme.bodyMedium?.copyWith(
                                color:
                                    theme.colorScheme.onSurface.withAlpha(120),
                              ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.expand_more,
                      color: theme.colorScheme.onSurface.withAlpha(100),
                    ),
                  ],
                ),
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
            final cs = theme.colorScheme;
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.62,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
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
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Техникум",
                                  style: theme.textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  lastSync != null
                                      ? "${lastSync!.message} • ${_formatFriendlySyncTime(lastSync!.checkedAt)}"
                                      : (syncedAt != null
                                          ? "Синхронизировано: ${_formatFriendlySyncTime(syncedAt)}"
                                          : "Выбери источник расписания"),
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: cs.onSurfaceVariant),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: "Синхронизировать список",
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
                                  },
                            icon: syncRunning
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.sync_rounded),
                          ),
                          IconButton.filledTonal(
                            tooltip: "Добавить источник",
                            onPressed: () async {
                              _dismissKeyboard();
                              final added =
                                  await _showAddCollegeSourceDialog();
                              if (!added || !mounted || !ctx.mounted) return;
                              ctrl.refreshCollegeSources();
                              setSheetState(() {});
                              setState(() {});
                            },
                            icon: const Icon(Icons.add_link_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.only(top: 2, bottom: 10),
                          itemCount: sources.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final s = sources[i];
                            final selected = ctrl.college == s.id;
                            final isRunning = runningIds.contains(s.id);
                            final probe = pingById[s.id];
                            final probeColor = probe == null
                                ? cs.onSurfaceVariant
                                : (probe.ok ? cs.primary : cs.error);
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () {
                                  HapticFeedback.lightImpact();
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
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 10, 4, 10),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    color: selected
                                        ? cs.primary.withAlpha(18)
                                        : theme.scaffoldBackgroundColor,
                                    border: Border.all(
                                      color: selected
                                          ? cs.primary
                                          : cs.onSurface.withAlpha(25),
                                      width: selected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: cs.primary
                                              .withAlpha(selected ? 35 : 14),
                                        ),
                                        child: Icon(
                                          s.builtIn
                                              ? Icons.school_rounded
                                              : Icons.link_rounded,
                                          size: 18,
                                          color: selected
                                              ? cs.primary
                                              : cs.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              s.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodyLarge
                                                  ?.copyWith(
                                                fontWeight: selected
                                                    ? FontWeight.w700
                                                    : FontWeight.w500,
                                              ),
                                            ),
                                            Text(
                                              s.baseUrl,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                      color:
                                                          cs.onSurfaceVariant),
                                            ),
                                            if (isRunning)
                                              Text(
                                                "Проверяю...",
                                                style: theme
                                                    .textTheme.labelSmall
                                                    ?.copyWith(
                                                        color: cs
                                                            .onSurfaceVariant),
                                              )
                                            else if (probe != null)
                                              Text(
                                                _formatProbeCaption(probe),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme
                                                    .textTheme.labelSmall
                                                    ?.copyWith(
                                                  color: probeColor,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (selected)
                                        Icon(Icons.check_circle_rounded,
                                            size: 20, color: cs.primary),
                                      if (isRunning)
                                        const Padding(
                                          padding: EdgeInsets.all(10),
                                          child: SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          ),
                                        )
                                      else
                                        PopupMenuButton<String>(
                                          tooltip: "Действия",
                                          iconSize: 20,
                                          splashRadius: 18,
                                          icon: Icon(Icons.more_vert_rounded,
                                              size: 20,
                                              color: cs.onSurfaceVariant),
                                          itemBuilder: (_) => [
                                            const PopupMenuItem<String>(
                                              value: "ping",
                                              child: Row(
                                                children: [
                                                  Icon(
                                                      Icons
                                                          .wifi_tethering_rounded,
                                                      size: 18),
                                                  SizedBox(width: 8),
                                                  Text("Проверить доступность"),
                                                ],
                                              ),
                                            ),
                                            const PopupMenuItem<String>(
                                              value: "copy",
                                              child: Row(
                                                children: [
                                                  Icon(
                                                      Icons
                                                          .content_copy_rounded,
                                                      size: 18),
                                                  SizedBox(width: 8),
                                                  Text("Копировать ссылку"),
                                                ],
                                              ),
                                            ),
                                            const PopupMenuItem<String>(
                                              value: "open",
                                              child: Row(
                                                children: [
                                                  Icon(
                                                      Icons.open_in_new_rounded,
                                                      size: 18),
                                                  SizedBox(width: 8),
                                                  Text("Открыть в браузере"),
                                                ],
                                              ),
                                            ),
                                            if (!s.builtIn) ...[
                                              const PopupMenuItem<String>(
                                                value: "edit",
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.edit_outlined,
                                                        size: 18),
                                                    SizedBox(width: 8),
                                                    Text("Изменить"),
                                                  ],
                                                ),
                                              ),
                                              const PopupMenuItem<String>(
                                                value: "delete",
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                        Icons
                                                            .delete_outline_rounded,
                                                        size: 18),
                                                    SizedBox(width: 8),
                                                    Text("Удалить"),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ],
                                          onSelected: (value) async {
                                            switch (value) {
                                              case "ping":
                                                setSheetState(() {
                                                  runningIds.add(s.id);
                                                });
                                                final result =
                                                    await _probeCollegeSourceUrl(
                                                        s.baseUrl);
                                                if (!ctx.mounted || !mounted) {
                                                  return;
                                                }
                                                setSheetState(() {
                                                  runningIds.remove(s.id);
                                                  pingById[s.id] = result;
                                                });
                                              case "copy":
                                                await Clipboard.setData(
                                                    ClipboardData(
                                                        text: s.baseUrl));
                                                if (ctx.mounted) {
                                                  ScaffoldMessenger.of(ctx)
                                                      .showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                          "Ссылка скопирована"),
                                                    ),
                                                  );
                                                }
                                              case "open":
                                                final u =
                                                    Uri.tryParse(s.baseUrl);
                                                if (u != null &&
                                                    await canLaunchUrl(u)) {
                                                  await launchUrl(u,
                                                      mode: LaunchMode
                                                          .externalApplication);
                                                }
                                              case "edit":
                                                _dismissKeyboard();
                                                final ok =
                                                    await _showEditCollegeSourceDialog(
                                                        s);
                                                if (!ok ||
                                                    !mounted ||
                                                    !ctx.mounted) {
                                                  return;
                                                }
                                                ctrl.refreshCollegeSources();
                                                setSheetState(() {});
                                                setState(() {});
                                              case "delete":
                                                final updated = prefs
                                                    .customCollegeSources
                                                    .where((e) => e.id != s.id)
                                                    .toList();
                                                prefs.saveCustomCollegeSources(
                                                    updated);
                                                ctrl.refreshCollegeSources();
                                                if (ctrl.college == s.id) {
                                                  ctrl.setCollege(
                                                      PreferencesManager
                                                          .collegeDefault);
                                                  _loadGroupsAsync();
                                                }
                                                setSheetState(() {});
                                                setState(() {});
                                            }
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
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
      // Основной источник — ветка data; фолбэк — master (как у обновлялки).
      var response = await GitHubHttpClient.get(
        GitHubProjectUrls.scheduleTimesRaw.trim(),
        headers: const {"Accept": "application/json, text/plain, */*"},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        response = await GitHubHttpClient.get(
          GitHubProjectUrls.scheduleTimesMasterFallbackRaw.trim(),
          headers: const {"Accept": "application/json, text/plain, */*"},
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final code = response.statusCode;
        return _CollegeSourcesSyncResult(
          savedCount: 0,
          message: switch (code) {
            403 => "GitHub ограничил доступ (HTTP 403)",
            429 => "Слишком часто (HTTP 429)",
            _ => "HTTP $code",
          },
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
      final colleges =
          (sources is Map<String, dynamic>) ? sources["colleges"] : null;
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

      final before = prefs.syncedCollegeSources;
      var changed = 0;
      for (final e in out.entries) {
        final prev = before[e.key];
        if (prev == null ||
            prev.name != e.value.name ||
            prev.baseUrl != e.value.baseUrl) {
          changed++;
        }
      }
      // Если в синке стало меньше источников — тоже считаем как изменение.
      if (before.length != out.length) {
        changed = (changed == 0) ? 1 : changed;
      }

      prefs.saveSyncedCollegeSources(out);
      ctrl.refreshCollegeSources();
      return _CollegeSourcesSyncResult(
        savedCount: out.length,
        message: out.isEmpty
            ? "В синхронизации пусто"
            : (changed == 0
                ? "Уже актуально (${out.length})"
                : "Обновлено: $changed • всего: ${out.length}"),
        checkedAt: checkedAt,
      );
    } catch (e) {
      final msg = e.toString().replaceAll("Exception: ", "");
      return _CollegeSourcesSyncResult(
        savedCount: 0,
        message: msg.isEmpty ? "Ошибка синхронизации" : msg,
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
        latencyMs: null,
        checkedAt: checkedAt,
      );
    }

    try {
      final client = http.Client();
      try {
        late http.BaseResponse res;
        final sw = Stopwatch()..start();
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
        sw.stop();

        final ok = res.statusCode >= 200 && res.statusCode < 400;
        final message = ok ? "Доступно" : "Сайт недоступен";
        return _UrlProbeResult(
          ok: ok,
          message: message,
          latencyMs: sw.elapsedMilliseconds,
          checkedAt: checkedAt,
        );
      } finally {
        client.close();
      }
    } catch (e) {
      return _UrlProbeResult(
        ok: false,
        message: "Нет ответа",
        latencyMs: null,
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
                                final updated =
                                    prefs.customCollegeSources.map((e) {
                                  if (e.id != source.id) return e;
                                  return CollegeSource(
                                    id: source.id,
                                    name: safeName,
                                    baseUrl: safeUrl,
                                  );
                                }).toList();
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
    var trimmed = raw.trim();
    if (trimmed.isEmpty) return "";
    // Умные поправки частых ошибок ввода: пробелы внутри, отсутствие схемы
    // («chtotib.ru» → «https://chtotib.ru»), опечатки вида «https:/».
    trimmed = trimmed.replaceAll(RegExp(r"\s+"), "");
    trimmed = trimmed.replaceFirstMapped(
      RegExp(r"^(https?):/(?!/)", caseSensitive: false),
      (m) => "${m[1]}://",
    );
    if (!trimmed.contains("://")) {
      trimmed = "https://$trimmed";
    }
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
    final label = isTeacher ? "преподавателя" : "группу";

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
                    "Выберите ${label.toLowerCase()}",
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  onPressed: _loadingGroups ? null : _loadGroupsAsync,
                  tooltip: "Обновить список",
                  style: IconButton.styleFrom(
                    foregroundColor: theme.colorScheme.primary,
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(40, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: _loadingGroups
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : Icon(
                          Icons.refresh_rounded,
                          size: 22,
                          color: theme.colorScheme.primary,
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
        favorites: () => prefs.favoriteGroups,
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
    return SettingsCollapsibleCard(
      icon: Icons.calendar_month_rounded,
      title: "Расписание",
      subtitle: "Перемены, обеды, автообновление",
      builder: (context) => Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SettingsSubsectionLabel("Элементы расписания"),
            ),
          ),
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
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SettingsSubsectionLabel("Синхронизация"),
            ),
          ),
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
          ValueChanged<bool> onChanged) =>
      settingsSwitchTile(theme, title, subtitle, value, onChanged);

  Widget _divider(ThemeData theme) => settingsDivider(theme);

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
    });
  }

  Future<void> _pickLessonTime({
    required int lessonNumber,
    required bool start,
  }) async {
    final current = _editingLessonTimes[lessonNumber];
    if (current == null) return;
    final initial =
        _parseTimeOfDay(start ? current.startTime : current.endTime) ??
            const TimeOfDay(hour: 8, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: start
          ? "Начало $lessonNumber-й пары"
          : "Конец $lessonNumber-й пары",
    );
    if (picked == null || !mounted) return;
    final newTime = _formatTimeOfDay(picked);
    final newStart = start ? newTime : current.startTime;
    final newEnd = start ? current.endTime : newTime;
    // Начало позже конца — не применяем, объясняем.
    final sm = _timeToMinutes(newStart);
    final em = _timeToMinutes(newEnd);
    if (sm != null && em != null && em <= sm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Конец пары должен быть позже начала"),
        ),
      );
      return;
    }
    setState(() {
      _editingLessonTimes[lessonNumber] =
          LessonTime(lessonNumber, newStart, newEnd);
    });
    // Автосохранение: отдельная кнопка «Сохранить» не нужна.
    final college = ctrl.college;
    prefs.setCustomLessonTimes(college, _editingLessonTimes);
    LessonTimes.setCustomTimes(college: college, times: _editingLessonTimes);
    await ctrl.loadSchedule(useCache: true);
  }

  int? _timeToMinutes(String value) {
    final t = _parseTimeOfDay(value);
    return t == null ? null : t.hour * 60 + t.minute;
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

  /// Чип времени: нажимаемое начало или конец пары.
  Widget _timeChip(ThemeData theme, String time, VoidCallback onTap) {
    final cs = theme.colorScheme;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: cs.primary.withAlpha(14),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.primary.withAlpha(50)),
        ),
        child: Text(
          time,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: cs.primary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  Widget _lessonTimesCard(ThemeData theme) {
    final entries = _editingLessonTimes.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final collegeName =
        ctrl.college == PreferencesManager.collegeZabgc ? "ЗабГК" : "ЧТОТиБ";
    final cs = theme.colorScheme;
    final syncedAt = prefs.lessonTimesRemoteSyncedAt;
    final syncText = syncedAt != null
        ? "Обновлено: ${_formatFriendlySyncTime(DateTime.fromMillisecondsSinceEpoch(syncedAt))}"
        : null;
    final hasCustom = prefs.getCustomLessonTimes(ctrl.college) != null;

    String durationLabel(LessonTime t) {
      final s = _timeToMinutes(t.startTime);
      final e = _timeToMinutes(t.endTime);
      if (s == null || e == null || e <= s) return "";
      final d = e - s;
      final h = d ~/ 60, m = d % 60;
      if (h == 0) return "$m мин";
      return m == 0 ? "$h ч" : "$h ч $m мин";
    }

    return SettingsCollapsibleCard(
      icon: Icons.schedule_rounded,
      title: "Время пар",
      badge: collegeName,
      subtitle: hasCustom
          ? "Своё время • сохраняется автоматически"
          : (syncText ?? "Начало и конец каждой пары"),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Нажми на время, чтобы изменить — сохранится само.",
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < entries.length; i++) ...[
              Builder(builder: (context) {
                final entry = entries[i];
                final lesson = entry.value;
                final dur = durationLabel(lesson);
                // Перемена до следующей пары.
                String breakLabel = "";
                if (i + 1 < entries.length) {
                  final e = _timeToMinutes(lesson.endTime);
                  final ns = _timeToMinutes(entries[i + 1].value.startTime);
                  if (e != null && ns != null && ns > e) {
                    breakLabel = "перемена ${ns - e} мин";
                  }
                }
                return Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: cs.onSurface.withAlpha(16),
                          ),
                          child: Text(
                            "${entry.key}",
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _timeChip(
                          theme,
                          lesson.startTime,
                          () => _pickLessonTime(
                              lessonNumber: entry.key, start: true),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.arrow_forward_rounded,
                              size: 14, color: cs.onSurfaceVariant),
                        ),
                        _timeChip(
                          theme,
                          lesson.endTime,
                          () => _pickLessonTime(
                              lessonNumber: entry.key, start: false),
                        ),
                        const Spacer(),
                        Text(
                          dur,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                    if (breakLabel.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const SizedBox(width: 44),
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Divider(
                                      color: cs.onSurface.withAlpha(20),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    child: Text(
                                      breakLabel,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                        fontSize: 11,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(
                                      color: cs.onSurface.withAlpha(20),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      const SizedBox(height: 8),
                  ],
                );
              }),
            ],
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: _resetLessonTimes,
              icon: const Icon(Icons.restore_rounded, size: 18),
              label: Text(hasCustom
                  ? "Сбросить к стандартному"
                  : "Обновить с сервера"),
            ),
          ],
        ),
      ),
    );
  }


  /// Ставит в лаунчере иконку, соответствующую настройке app_icon.





  /// Ряд кружков-свотчей тем: «Авто» + все темы. Общий для выбора
  /// иконки приложения и темы виджета.




  Widget _appIdentityCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withAlpha(100),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(28),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: AppIconImage(
                size: 52,
                colors: AppThemes.colorsFor(prefs.effectiveAppIcon),
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
      ),
    );
  }

  Widget _updatesCard(ThemeData theme) {
    return SettingsCollapsibleCard(
      icon: Icons.system_update_rounded,
      title: "Обновления",
      subtitle: "Автопроверка и журнал изменений",
      builder: (context) => Column(
        children: [
          const SizedBox(height: 4),
          _switchTile(
            theme,
            "Проверять при запуске",
            "Показывать диалог обновления, если вышла новая версия",
            prefs.autoCheckAppUpdate,
            (v) async {
              setState(() => prefs.autoCheckAppUpdate = v);
              await AppUpdateBackgroundWorker.ensureRegistered(prefs: prefs);
            },
          ),
          _divider(theme),
          _switchTile(
            theme,
            "Автозагрузка по Wi-Fi",
            "Скачивать обновление заранее, чтобы установить в один тап",
            prefs.autoDownloadAppUpdate,
            (v) => setState(() => prefs.autoDownloadAppUpdate = v),
          ),
          _divider(theme),
          ListTile(
            leading: Icon(
              Icons.history_edu_rounded,
              color: theme.colorScheme.primary,
            ),
            title: const Text("Что нового"),
            subtitle: const Text("Журнал изменений приложения"),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ChangelogPage(),
              ),
            ),
          ),
          _divider(theme),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _checkForUpdate(),
                icon: const Icon(Icons.system_update_rounded, size: 20),
                label: const Text("Проверить обновления"),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _creditsCard(ThemeData theme) {
    const authorLink = "https://everelsu.github.io/RelsevLink/";
    const releasesLink = "https://github.com/Everelsu/Raspisanie/releases";
    const authorAvatarUrl =
        "https://raw.githubusercontent.com/Everelsu/RelsevLink/main/avatar.png";
    const betaTesterLink = "https://www.youtube.com/watch?v=dQw4w9WgXcQ";
    const betaTesterTelegramDeepLink =
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ";
    const betaTesterAvatarUrl =
        "https://raw.githubusercontent.com/Everelsu/RelsevLink/6b2647524fe3ade73d931079e77f8225ccffd2f5/scromny.jpg";
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SettingsSubsectionLabel("Авторы"),
            _creditPersonTile(
              theme,
              name: "@Re1sev",
              role: "Автор",
              roleIcon: Icons.code_rounded,
              avatarUrl: authorAvatarUrl,
              onTap: () => _openCreditLink(authorLink),
            ),
            const SizedBox(height: 10),
            _creditPersonTile(
              theme,
              name: "@skromniyvadya",
              role: "Бета‑тестер",
              roleIcon: Icons.bug_report_rounded,
              avatarUrl: betaTesterAvatarUrl,
              onTap: () async {
                final openedInTelegram = await launchUrl(
                  Uri.parse(betaTesterTelegramDeepLink),
                  mode: LaunchMode.externalApplication,
                );
                if (!openedInTelegram) await _openCreditLink(betaTesterLink);
              },
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

  /// Открывает ссылку из карточки авторов; если не вышло — копирует в буфер.
  Future<void> _openCreditLink(String link) async {
    final opened = await launchUrl(
      Uri.parse(link),
      mode: LaunchMode.externalApplication,
    );
    if (opened || !mounted) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Ссылка скопирована"),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Widget _creditPersonTile(
    ThemeData theme, {
    required String name,
    required String role,
    required IconData roleIcon,
    required String avatarUrl,
    required VoidCallback onTap,
  }) {
    final cs = theme.colorScheme;
    return Material(
      color: cs.surfaceContainerHighest.withAlpha(40),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: cs.primary.withAlpha(120),
                    width: 1.5,
                  ),
                ),
                child: _AuthorAvatar(avatarUrl: avatarUrl, theme: theme),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primary.withAlpha(22),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(roleIcon, size: 12, color: cs.primary),
                          const SizedBox(width: 4),
                          Text(
                            role,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.open_in_new_rounded,
                size: 20,
                color: cs.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Отмена"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Удалить"),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  int _snapRetention(int value) {
    const presets = [14, 30, 90, 180, 365];

    for (final p in presets) {
      if ((value - p).abs() <= 5) return p; // магнит в радиусе 5 дней
    }
    return value;
  }

  Widget _dbSettingsCard(ThemeData theme) {
    final cs = theme.colorScheme;
    final lastDbBackupText = _lastDbBackupAt == null
        ? "Не выполнялся"
        : _formatFriendlySyncTime(
            DateTime.fromMillisecondsSinceEpoch(_lastDbBackupAt!));

    Widget sectionLabel(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        );

    return SettingsCollapsibleCard(
      icon: Icons.storage_rounded,
      title: "Данные и хранение",
      subtitle: "$_dbRecords записей • хранение $_dbRetentionDays дн.",
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Хранение ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                sectionLabel("ХРАНЕНИЕ"),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("История расписания",
                              style: theme.textTheme.bodyLarge),
                          Text(
                            "Глубина хранения записей в базе данных",
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () async {
                            final controller = TextEditingController(
                              text: _dbRetentionDays.toString(),
                            );

                            final result = await showDialog<int>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text("Введите количество дней"),
                                content: TextField(
                                  controller: controller,
                                  keyboardType: TextInputType.number,
                                  autofocus: true,
                                  decoration: const InputDecoration(
                                    suffixText: "дн.",
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text("Отмена"),
                                  ),
                                  FilledButton(
                                    onPressed: () {
                                      final value =
                                          int.tryParse(controller.text);
                                      if (value != null &&
                                          value >= 14 &&
                                          value <= 365) {
                                        Navigator.pop(ctx, value);
                                      }
                                    },
                                    child: const Text("OK"),
                                  ),
                                ],
                              ),
                            );

                            if (result != null) {
                              setState(() => _dbRetentionDays = result);
                              await ScheduleDatabase.instance
                                  .saveDatabaseSetting(
                                "retention_days",
                                result.toString(),
                              );
                            }
                          },
                          child: Text(
                            "$_dbRetentionDays дн.",
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Slider(
                  value: _dbRetentionDays.toDouble(),
                  min: 14,
                  max: 365,
                  divisions: 351,
                  onChanged: (v) {
                    setState(
                        () => _dbRetentionDays = _snapRetention(v.round()));
                  },
                  onChangeEnd: (v) async {
                    final snapped = _snapRetention(v.round());
                    if (snapped != _dbRetentionDays) {
                      setState(() => _dbRetentionDays = snapped);
                    }
                    await ScheduleDatabase.instance.saveDatabaseSetting(
                        "retention_days", snapped.toString());
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("2 нед.",
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                    Text("1 год",
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),

          _divider(theme),

          // ── Резервное копирование ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                sectionLabel("РЕЗЕРВНОЕ КОПИРОВАНИЕ"),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _dbTransferBusy ? null : _exportDatabase,
                        icon: const Icon(Icons.upload_file_outlined, size: 18),
                        label: const Text("Экспорт"),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _dbTransferBusy ? null : _importDatabase,
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: const Text("Импорт"),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.history,
                        size: 14, color: cs.onSurfaceVariant.withAlpha(160)),
                    const SizedBox(width: 4),
                    Text(
                      "Последний экспорт: $lastDbBackupText",
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),

          _divider(theme),

          // ── Очистка ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                sectionLabel("ОЧИСТКА"),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _dbBusy
                            ? null
                            : () async {
                                final confirmed = await _confirmDelete(
                                  "Удалить базу данных?",
                                  "Все данные будут безвозвратно удалены.",
                                );

                                if (!confirmed) return;

                                setState(() => _dbBusy = true);
                                await ScheduleDatabase.instance.clearAll();
                                await _loadDbSettings();
                                if (mounted) setState(() => _dbBusy = false);
                              },
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text("База данных"),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final confirmed = await _confirmDelete(
                            "Очистить кэш?",
                            "Кэш расписания будет удалён.",
                          );

                          if (!confirmed) return;

                          StorageCleanup.clearAllPrefsCache(
                              prefs.sharedPreferences);

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text("Кэш расписания очищен")),
                            );
                          }
                        },
                        icon: const Icon(Icons.cached_outlined, size: 18),
                        label: const Text("Кэш"),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final confirmed = await _confirmDelete(
                        "Удалить временные файлы?",
                        "Все временные файлы будут удалены.",
                      );

                      if (!confirmed) return;

                      await StorageCleanup.clearTempDirectory();

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text("Временные файлы удалены")),
                        );
                      }
                    },
                    icon: const Icon(Icons.folder_off_outlined, size: 18),
                    label: const Text("Временные файлы"),
                  ),
                ),
              ],
            ),
          ),

          _divider(theme),

          // ── Приватность ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: sectionLabel("ПРИВАТНОСТЬ"),
          ),
          _switchTile(
            theme,
            "Отправлять аналитику Firebase",
            "Анонимная статистика использования",
            prefs.analyticsEnabled,
            (v) async {
              setState(() => prefs.analyticsEnabled = v);
              await AnalyticsService.instance.setEnabled(v);
              AnalyticsService.instance
                  .logEvent("analytics_toggled", {"enabled": v});
            },
          ),
          const SizedBox(height: 4),
        ],
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
    // Спрашиваем режим: null = отмена, true = объединить, false = заменить
    final merge = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Импорт БД"),
        content: const Text(
          "Выберите режим импорта:\n\n"
          "• Объединить — добавит данные из файла к текущим (записи с одинаковым ключом будут заменены).\n\n"
          "• Заменить — полностью перезапишет текущую базу данных.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Отмена"),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(ctx, false),
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: const Text("Заменить"),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.merge_rounded, size: 18),
            label: const Text("Объединить"),
          ),
        ],
      ),
    );
    if (merge == null) return;

    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ["db", "sqlite", "sqlite3"],
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.single.path;
    if (path == null || path.isEmpty) return;

    setState(() => _dbTransferBusy = true);
    try {
      if (merge) {
        final count =
            await ScheduleDatabase.instance.mergeDatabaseFromFile(path);
        await _loadDbSettings();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Объединено: $count записей")),
        );
      } else {
        await ScheduleDatabase.instance.replaceDatabaseFromFile(path);
        await _loadDbSettings();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("База данных заменена")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Ошибка импорта: ${_dbErrorText(e)}")),
      );
    } finally {
      if (mounted) setState(() => _dbTransferBusy = false);
    }
  }

  static String _dbErrorText(Object e) {
    final s = e.toString();
    if (s.contains("не найден") || s.contains("not found")) {
      return "файл не найден";
    }
    if (s.contains("DatabaseException") || s.contains("SqliteException")) {
      return "повреждённый файл БД";
    }
    return "неизвестная ошибка";
  }

  Future<void> _checkForUpdate() async {
    final controller = AppUpdateController.instance;
    final update = await controller.check();
    if (!mounted) return;
    if (update != null) {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      AnalyticsService.instance
          .logEvent("update_dialog_shown", {"version": update.version});
      // Ручная проверка показывает диалог всегда, минуя отсрочку «Позже».
      await showAppUpdateDialog(context, currentVersion: info.version);
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
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

  /// Живой доступ к избранным: шторка — отдельный route, снимок множества
  /// не обновился бы после тапа по звёздочке (звёзды «не работали»).
  final Set<String> Function() favorites;

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

    final favorites = widget.favorites();
    final favGroups =
        filtered.where((g) => favorites.contains(g.name)).toList();
    final otherGroups =
        filtered.where((g) => !favorites.contains(g.name)).toList();

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
    final cs = theme.colorScheme;
    final isSelected = widget.selected?.id == g.id;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onSelect(g);
          },
          onLongPress: () {
            HapticFeedback.selectionClick();
            widget.onToggleFavorite(g.name);
            setState(() {});
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: isSelected ? cs.primary.withAlpha(18) : Colors.transparent,
              border: Border.all(
                color: isSelected ? cs.primary : cs.onSurface.withAlpha(18),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    g.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? cs.primary : cs.onSurface,
                    ),
                  ),
                ),
                if (isSelected)
                  Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Icon(Icons.check_circle_rounded,
                        size: 18, color: cs.primary),
                  ),
                IconButton(
                  tooltip: isFav ? "Убрать из избранного" : "В избранное",
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    widget.onToggleFavorite(g.name);
                    setState(() {});
                  },
                  icon: Icon(
                    isFav ? Icons.star_rounded : Icons.star_border_rounded,
                    size: 20,
                    color: isFav
                        ? cs.primary
                        : cs.onSurfaceVariant.withAlpha(140),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


