import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart";

import "../../schedule/presentation/schedule_controller.dart";
import "../data/notes_repository.dart";
import "../domain/note_models.dart";
import "note_editor_page.dart";

class NotesPage extends StatefulWidget {
  const NotesPage({
    super.key,
    required this.controller,
  });

  final ScheduleController controller;

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage>
    with SingleTickerProviderStateMixin {
  static const _cardColorsLight = <String, Color>{
    "yellow": Color(0xFFFFF9C4),
    "green": Color(0xFFCCFF90),
    "blue": Color(0xFFAECBFA),
    "red": Color(0xFFF28B82),
    "purple": Color(0xFFD7AEFB),
    "teal": Color(0xFFA8F0E6),
    "default": Color(0xFFFFFFFF),
  };
  static const _cardColorsDark = <String, Color>{
    "yellow": Color(0xFF5A4A00),
    "green": Color(0xFF1F4D2E),
    "blue": Color(0xFF1F3F68),
    "red": Color(0xFF7A2A2A),
    "purple": Color(0xFF4A2F68),
    "teal": Color(0xFF1F5A55),
    "default": Color(0xFF1E1E1E),
  };

  final _repository = NotesRepository();
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _scrollController = ScrollController();

  late final AnimationController _fabController;
  late final Animation<double> _fabExpandAnim;

  List<NoteItem> _notes = const [];
  bool _loading = true;
  bool _grid = true;
  bool _fabExpanded = false;
  String _filterTag = "";
  String _filterColor = "";
  NoteType? _filterType;
  NoteSortMode _sortMode = NoteSortMode.updatedDesc;
  String? _pressedNoteId;
  String? _swipingNoteId;
  int _viewSwitchDirection = 1;

  bool get _useDarkNoteCards => widget.controller.prefs.notesDarkCards;
  Map<String, Color> get _cardColors =>
      _useDarkNoteCards ? _cardColorsDark : _cardColorsLight;

  @override
  void initState() {
    super.initState();
    _init();
    _searchController.addListener(() => setState(() {}));
    _searchFocusNode.addListener(() => setState(() {}));
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fabExpandAnim = CurvedAnimation(
      parent: _fabController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _fabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final textTheme = theme.textTheme;
    final visible = _filtered(_notes);
    final tags = _collectTags(_notes);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final slide = Tween<Offset>(
                begin: Offset(0.05 * _viewSwitchDirection, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
              return FadeTransition(
                opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
                child: SlideTransition(
                  position: slide,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.982, end: 1).animate(
                      CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                    ),
                    child: child,
                  ),
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey("notes-view-${_grid ? "grid" : "list"}"),
              child: CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      MediaQuery.of(context).padding.top + 8,
                      16,
                      6,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Заметки",
                            style: textTheme.titleLarge?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _buildSearchRow(textTheme, cs),
                          const SizedBox(height: 8),
                          _buildTypeAndColorFilters(textTheme, cs),
                          if (tags.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            _buildTagRow(tags, textTheme, cs),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (visible.isEmpty)
                    SliverFillRemaining(
                      child: _buildEmptyState(textTheme, cs),
                    )
                  else
                    _grid
                        ? _buildMasonrySliver(visible, textTheme, cs)
                        : _buildListSliver(visible, textTheme, cs),
                ],
              ),
            ),
          ),
          _buildFabLayer(textTheme, cs),
        ],
      ),
    );
  }

  Widget _buildSearchRow(TextTheme textTheme, ColorScheme cs) {
    final focused = _searchFocusNode.hasFocus;
    return Row(
      children: [
        Expanded(
          child: AnimatedScale(
            duration: const Duration(milliseconds: 180),
            scale: focused ? 1.015 : 1.0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(26),
                boxShadow: focused
                    ? [
                        BoxShadow(
                          color: Colors.black.withAlpha(35),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : const [],
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                decoration: InputDecoration(
                  hintText: "Поиск заметок",
                  hintStyle:
                      textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  prefixIcon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: _showSortMenu,
          icon: Icon(Icons.sort_rounded, color: cs.onSurfaceVariant),
          tooltip: "Сортировка",
        ),
        IconButton(
          onPressed: _openTrash,
          icon: Icon(Icons.delete_outline_rounded, color: cs.onSurfaceVariant),
          tooltip: "Корзина",
        ),
        IconButton(
          onPressed: _toggleViewMode,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) => RotationTransition(
              turns: Tween<double>(begin: 0.9, end: 1).animate(animation),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: Icon(
              _grid ? Icons.view_agenda_outlined : Icons.grid_view_rounded,
              key: ValueKey("view-icon-${_grid ? "list" : "grid"}"),
              color: cs.onSurfaceVariant,
            ),
          ),
          tooltip: _grid ? "Показать списком" : "Показать сеткой",
        ),
      ],
    );
  }

  Widget _buildTypeAndColorFilters(TextTheme textTheme, ColorScheme cs) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _typeChip("Все", _filterType == null, () {
                  setState(() => _filterType = null);
                }, textTheme, cs),
                const SizedBox(width: 6),
                _typeChip("Текст", _filterType == NoteType.text, () {
                  setState(() {
                    _filterType =
                        _filterType == NoteType.text ? null : NoteType.text;
                  });
                }, textTheme, cs),
                const SizedBox(width: 6),
                _typeChip("Чеклист", _filterType == NoteType.checklist, () {
                  setState(() {
                    _filterType = _filterType == NoteType.checklist
                        ? null
                        : NoteType.checklist;
                  });
                }, textTheme, cs),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        _colorDot("", cs),
        const SizedBox(width: 4),
        ...["yellow", "green", "blue", "red", "purple", "teal"].map(
          (colorKey) => Padding(
            padding: const EdgeInsets.only(left: 4),
            child: _colorDot(colorKey, cs),
          ),
        ),
      ],
    );
  }

  Widget _typeChip(
    String label,
    bool selected,
    VoidCallback onTap,
    TextTheme textTheme,
    ColorScheme cs,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
          ),
          color: selected ? cs.primary.withAlpha(22) : Colors.transparent,
        ),
        child: Text(
          label,
          style: textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _colorDot(String key, ColorScheme cs) {
    final selected = _filterColor == key;
    final color = key.isEmpty
        ? cs.surfaceContainerHighest
        : (_cardColors[key] ?? cs.surfaceContainerHighest);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => setState(() => _filterColor = selected ? "" : key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected ? cs.primary : cs.outline,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }

  Widget _buildTagRow(List<String> tags, TextTheme textTheme, ColorScheme cs) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (_, i) {
          if (i == 0) {
            return ChoiceChip(
              selected: _filterTag.isEmpty,
              label: const Text("Все"),
              onSelected: (_) => setState(() => _filterTag = ""),
            );
          }
          final tag = tags[i - 1];
          final selected = _filterTag == tag;
          return ChoiceChip(
            selected: selected,
            label: Text("#$tag"),
            labelStyle: textTheme.bodySmall?.copyWith(color: cs.onSurface),
            onSelected: (_) => setState(() => _filterTag = selected ? "" : tag),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: tags.length + 1,
      ),
    );
  }

  Widget _buildMasonrySliver(
    List<NoteItem> notes,
    TextTheme textTheme,
    ColorScheme cs,
  ) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 124),
      sliver: SliverMasonryGrid.count(
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        return _dismissibleNoteCard(
          note,
          _buildNoteCard(note, textTheme, cs),
        );
      },
    ),
  );
  }

  Widget _buildListSliver(
    List<NoteItem> notes,
    TextTheme textTheme,
    ColorScheme cs,
  ) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 124),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final note = notes[index];
            return Padding(
              padding: EdgeInsets.only(bottom: index == notes.length - 1 ? 0 : 10),
              child: _dismissibleNoteCard(
                note,
                _buildNoteCard(note, textTheme, cs),
              ),
            );
          },
          childCount: notes.length,
        ),
      ),
    );
  }

  Widget _dismissibleNoteCard(NoteItem note, Widget child) {
    const radius = 14.0;
    return _SwipeToDeleteCard(
      key: ValueKey("note-swipe-${note.id}"),
      borderRadius: radius,
      backgroundColor: Theme.of(context).colorScheme.error,
      onSwipingChanged: (swiping) {
        if (!mounted) return;
        if (swiping && _swipingNoteId != note.id) {
          setState(() => _swipingNoteId = note.id);
        } else if (!swiping && _swipingNoteId == note.id) {
          setState(() => _swipingNoteId = null);
        }
      },
      onDismissed: () async {
        if (_swipingNoteId == note.id && mounted) {
          setState(() => _swipingNoteId = null);
        }
        await _runSafe(() async {
          await _repository.softDelete(note.id);
          if (!mounted) return;
          setState(() {
            _notes = _notes.where((n) => n.id != note.id).toList();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("Заметка перемещена в корзину"),
              action: SnackBarAction(
                label: "Отменить",
                onPressed: () async {
                  await _runSafe(() async {
                    await _repository.restore(note.id);
                    await _load();
                  }, "Не удалось восстановить заметку");
                },
              ),
            ),
          );
        }, "Не удалось переместить заметку в корзину");
      },
      child: child,
    );
  }

  Widget _buildNoteCard(NoteItem note, TextTheme textTheme, ColorScheme cs) {
    final pressed = _pressedNoteId == note.id;
    final swiping = _swipingNoteId == note.id;
    final cardColor = _mapCardColor(note.color);
    final noteTextColor = _noteTextColor(note.color, cs);
    return AnimatedScale(
      duration: const Duration(milliseconds: 90),
      scale: pressed ? 0.98 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: swiping
              ? const []
              : [
                  BoxShadow(
                    color: Colors.black.withAlpha(28),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTapDown: (_) => setState(() => _pressedNoteId = note.id),
            onTapCancel: () => setState(() => _pressedNoteId = null),
            onTap: () async {
              HapticFeedback.selectionClick();
              setState(() => _pressedNoteId = null);
              await _edit(note);
            },
            onLongPress: () => _openActions(note),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          note.title.isEmpty ? "Без названия" : note.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleMedium?.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: noteTextColor,
                          ),
                        ),
                      ),
                      if (note.isPinned)
                        Icon(Icons.push_pin, size: 16, color: cs.primary),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildNotePreview(note, textTheme, cs, noteTextColor),
                  if (note.tags.isNotEmpty || note.scheduleDate != null) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (note.scheduleDate != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: cs.primary.withAlpha(26),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              note.lessonNumber == null
                                  ? note.scheduleDate!
                                  : "${note.scheduleDate} • ${note.lessonNumber} пара",
                              style: textTheme.bodySmall?.copyWith(color: cs.primary),
                            ),
                          ),
                        ...note.tags.take(2).map(
                              (tag) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.surface.withAlpha(150),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text("#$tag", style: textTheme.bodySmall),
                              ),
                            ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotePreview(
    NoteItem note,
    TextTheme textTheme,
    ColorScheme cs,
    Color noteTextColor,
  ) {
    if (note.type == NoteType.checklist) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: note.checklist
            .take(4)
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      item.done
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 14,
                      color: item.done ? cs.primary : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          fontSize: 13,
                          color: noteTextColor,
                          decoration:
                              item.done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      );
    }
    return Text(
      note.plainContent,
      maxLines: 10,
      overflow: TextOverflow.ellipsis,
      style: textTheme.bodySmall?.copyWith(
        fontSize: 13,
        color: noteTextColor,
      ),
    );
  }

  Widget _buildEmptyState(TextTheme textTheme, ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lightbulb_outline_rounded,
              size: 76,
              color: cs.onSurfaceVariant.withAlpha(160),
            ),
            const SizedBox(height: 18),
            Text(
              "Заметок пока нет",
              style: textTheme.titleLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFabLayer(TextTheme textTheme, ColorScheme cs) {
    return Positioned(
      right: 18,
      bottom: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizeTransition(
            sizeFactor: _fabExpandAnim,
            axisAlignment: -1,
            child: FadeTransition(
              opacity: _fabExpandAnim,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _fabAction(
                    icon: Icons.edit_note_rounded,
                    label: "Текст",
                    onTap: () => _create(type: NoteType.text),
                    textTheme: textTheme,
                    cs: cs,
                  ),
                  const SizedBox(height: 8),
                  _fabAction(
                    icon: Icons.check_box_outlined,
                    label: "Чеклист",
                    onTap: () => _create(type: NoteType.checklist),
                    textTheme: textTheme,
                    cs: cs,
                  ),
                  const SizedBox(height: 8),
                  _fabAction(
                    icon: Icons.image_outlined,
                    label: "Изображение",
                    onTap: () {
                      _toggleFab(false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Добавление изображений скоро появится"),
                        ),
                      );
                    },
                    textTheme: textTheme,
                    cs: cs,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          AnimatedScale(
            duration: const Duration(milliseconds: 220),
            curve: Curves.elasticOut,
            scale: 1,
            child: FloatingActionButton.extended(
              heroTag: "notes-main-fab",
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              onPressed: () => _toggleFab(!_fabExpanded),
              icon: Icon(_fabExpanded ? Icons.close_rounded : Icons.add),
              label: const Text("Новая"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fabAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required TextTheme textTheme,
    required ColorScheme cs,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(28),
                blurRadius: 6,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        FloatingActionButton.small(
          heroTag: "notes-fab-$label",
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurfaceVariant,
          onPressed: onTap,
          child: Icon(icon),
        ),
      ],
    );
  }

  void _toggleFab(bool expanded) {
    setState(() => _fabExpanded = expanded);
    if (expanded) {
      _fabController.forward();
    } else {
      _fabController.reverse();
    }
  }

  Future<void> _create({required NoteType type}) async {
    _toggleFab(false);
    final result = await Navigator.of(context).push<NoteItem>(
      MaterialPageRoute(
        builder: (_) => NoteEditorPage(
          initialType: type,
          defaultGroupFile: widget.controller.selectedGroup?.fileName,
          defaultCollege: widget.controller.college,
          defaultGroupName: widget.controller.selectedGroup?.name,
          scheduleIndex: _scheduleIndex(),
        ),
      ),
    );
    if (result == null) return;
    await _runSafe(() async {
      await _repository.save(result);
      await _load();
    }, "Не удалось создать заметку");
  }

  Future<void> _edit(NoteItem note) async {
    final result = await Navigator.of(context).push<NoteItem>(
      MaterialPageRoute(
        builder: (_) => NoteEditorPage(
          initial: note,
          defaultGroupFile: widget.controller.selectedGroup?.fileName,
          defaultCollege: widget.controller.college,
          defaultGroupName: widget.controller.selectedGroup?.name,
          scheduleIndex: _scheduleIndex(),
        ),
      ),
    );
    if (result == null) return;
    await _runSafe(() async {
      await _repository.save(result);
      await _load();
    }, "Не удалось сохранить изменения");
  }

  Future<void> _openActions(NoteItem note) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            const ListTile(
              title: Text("Действия с заметкой"),
            ),
            ListTile(
              leading:
                  Icon(note.isPinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(note.isPinned ? "Открепить" : "Закрепить"),
              onTap: () => Navigator.pop(ctx, "pin"),
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text("Сменить цвет"),
              onTap: () => Navigator.pop(ctx, "color"),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text("В корзину"),
              onTap: () => Navigator.pop(ctx, "delete"),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;
    if (action == "pin") await _togglePin(note);
    if (action == "color") await _pickColor(note);
    if (action == "delete") await _softDelete(note);
  }

  Future<void> _togglePin(NoteItem note) async {
    await _runSafe(() async {
      await _repository.setPinned(note.id, !note.isPinned);
      await _load();
    }, "Не удалось изменить закрепление");
  }

  Future<void> _softDelete(NoteItem note) async {
    await _runSafe(() async {
      await _repository.softDelete(note.id);
      await _load();
    }, "Не удалось удалить заметку");
  }

  Future<void> _pickColor(NoteItem note) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _cardColors.entries
                .where((e) => e.key != "default")
                .map(
                  (entry) => InkWell(
                    onTap: () => Navigator.pop(ctx, entry.key),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: entry.value,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF9AA0A6)),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
    if (selected == null) return;
    await _runSafe(() async {
      await _repository.save(note.copyWith(color: selected));
      await _load();
    }, "Не удалось изменить цвет");
  }

  Future<void> _openTrash() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotesTrashPage()),
    );
    if (mounted) {
      await _load();
    }
  }

  Future<void> _showSortMenu() async {
    final selected = await showModalBottomSheet<NoteSortMode>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: NoteSortMode.values
              .map(
                (mode) => ListTile(
                  leading: Icon(
                    mode == _sortMode
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                  ),
                  title: Text(_sortModeLabel(mode)),
                  onTap: () => Navigator.pop(ctx, mode),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (selected == null || selected == _sortMode) return;
    await _runSafe(() async {
      _sortMode = selected;
      await _repository.saveSortMode(selected);
      await _load();
    }, "Не удалось изменить сортировку");
  }

  String _sortModeLabel(NoteSortMode mode) {
    switch (mode) {
      case NoteSortMode.updatedDesc:
        return "Сначала новые";
      case NoteSortMode.updatedAsc:
        return "Сначала старые";
      case NoteSortMode.createdDesc:
        return "По дате создания (новые)";
      case NoteSortMode.createdAsc:
        return "По дате создания (старые)";
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final rows = await _repository.listNotes(
        includeArchived: false,
        includeDeleted: false,
        sortMode: _sortMode,
      );
      if (!mounted) return;
      setState(() {
        _notes = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ошибка загрузки заметок")),
      );
    }
  }

  Future<void> _init() async {
    try {
      _sortMode = await _repository.loadSortMode();
    } catch (_) {
      _sortMode = NoteSortMode.updatedDesc;
    }
    try {
      _grid = await _repository.loadViewMode();
    } catch (_) {
      _grid = true;
    }
    await _load();
  }

  List<String> _collectTags(List<NoteItem> notes) {
    final tags = <String>{};
    for (final note in notes) {
      tags.addAll(note.tags);
    }
    final list = tags.toList()..sort();
    return list;
  }

  List<NoteItem> _filtered(List<NoteItem> source) {
    final query = _normalizeSearch(_searchController.text);
    final tokens = query.split(" ").where((e) => e.isNotEmpty).toList();
    final base = source.where((note) {
      if (_filterTag.isNotEmpty && !note.tags.contains(_filterTag)) {
        return false;
      }
      if (_filterColor.isNotEmpty && note.color != _filterColor) {
        return false;
      }
      if (_filterType != null && note.type != _filterType) {
        return false;
      }
      return true;
    }).toList();

    if (query.isEmpty) return base;

    final scored = <({NoteItem note, int score})>[];
    for (final note in base) {
      final score = _searchScore(note, query, tokens);
      if (score > 0) {
        scored.add((note: note, score: score));
      }
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byPinned = (b.note.isPinned ? 1 : 0).compareTo(a.note.isPinned ? 1 : 0);
      if (byPinned != 0) return byPinned;
      return b.note.updatedAt.compareTo(a.note.updatedAt);
    });
    return scored.map((e) => e.note).toList();
  }

  Map<String, List<int>> _scheduleIndex() {
    final out = <String, List<int>>{};
    for (final day in widget.controller.schedule) {
      final nums = day.items.map((e) => e.lessonNumber).toSet().toList()
        ..sort((a, b) => a.compareTo(b));
      out[day.date] = nums;
    }
    return out;
  }

  Color _mapCardColor(String key) {
    return _cardColors[key] ?? _cardColors["default"]!;
  }

  Color _noteTextColor(String colorKey, ColorScheme cs) {
    if (_useDarkNoteCards) {
      switch (colorKey) {
        case "yellow":
          return const Color(0xFFF6E7A6);
        default:
          return Colors.white;
      }
    }
    switch (colorKey) {
      case "green":
      case "default":
      case "blue":
      case "teal":
      case "yellow":
        return const Color(0xFF202124);
      case "red":
        return Colors.white;
      default:
        return cs.onSurface;
    }
  }

  void _toggleViewMode() {
    HapticFeedback.selectionClick();
    final next = !_grid;
    setState(() {
      _viewSwitchDirection = next ? 1 : -1;
      _grid = next;
    });
    _runSafe(
      () => _repository.saveViewMode(grid: next),
      "Не удалось сохранить режим отображения",
    );
  }

  String _normalizeSearch(String input) {
    return input
        .toLowerCase()
        .replaceAll("ё", "е")
        .replaceAll(RegExp(r"[^a-zа-я0-9\s]"), " ")
        .replaceAll(RegExp(r"\s+"), " ")
        .trim();
  }

  int _searchScore(NoteItem note, String query, List<String> tokens) {
    final title = _normalizeSearch(note.title);
    final content = _normalizeSearch(note.plainContent);
    final tags = note.tags.map(_normalizeSearch).join(" ");
    final combined = "$title $content $tags".trim();
    if (combined.isEmpty) return 0;

    var score = 0;
    if (title.startsWith(query)) score += 120;
    if (title.contains(query)) score += 80;
    if (content.contains(query)) score += 45;
    if (tags.contains(query)) score += 35;

    final words = combined.split(" ").where((w) => w.isNotEmpty).toList();
    for (final token in tokens) {
      var tokenMatched = false;
      for (final word in words) {
        if (word == token) {
          score += 26;
          tokenMatched = true;
          break;
        }
        if (word.startsWith(token)) {
          score += 16;
          tokenMatched = true;
          break;
        }
        if (_isSubsequence(token, word)) {
          score += 10;
          tokenMatched = true;
          break;
        }
        if (token.length >= 4 && _levenshteinDistance(token, word) <= 1) {
          score += 8;
          tokenMatched = true;
          break;
        }
      }
      if (!tokenMatched) return 0;
    }
    return score;
  }

  bool _isSubsequence(String needle, String haystack) {
    if (needle.isEmpty) return true;
    var i = 0;
    for (var j = 0; j < haystack.length && i < needle.length; j++) {
      if (haystack.codeUnitAt(j) == needle.codeUnitAt(i)) i++;
    }
    return i == needle.length;
  }

  int _levenshteinDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    if ((a.length - b.length).abs() > 1) return 2;

    final dp = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      var prev = dp[0];
      dp[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final temp = dp[j];
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        dp[j] = [
          dp[j] + 1,
          dp[j - 1] + 1,
          prev + cost,
        ].reduce((x, y) => x < y ? x : y);
        prev = temp;
      }
    }
    return dp[b.length];
  }

  Future<void> _runSafe(Future<void> Function() action, String errorText) async {
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorText)),
      );
    }
  }
}

class NotesTrashPage extends StatefulWidget {
  const NotesTrashPage({super.key});

  @override
  State<NotesTrashPage> createState() => _NotesTrashPageState();
}

class _NotesTrashPageState extends State<NotesTrashPage> {
  static const _cardColors = <String, Color>{
    "yellow": Color(0xFFFFF9C4),
    "green": Color(0xFFCCFF90),
    "blue": Color(0xFFAECBFA),
    "red": Color(0xFFF28B82),
    "purple": Color(0xFFD7AEFB),
    "teal": Color(0xFFA8F0E6),
    "default": Color(0xFFFFFFFF),
  };

  final _repository = NotesRepository();
  List<NoteItem> _trash = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final deleted = await _repository.listNotes(
        includeArchived: true,
        includeDeleted: true,
      );
      if (!mounted) return;
      setState(() {
        _trash = deleted.where((n) => n.isDeleted).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Не удалось загрузить корзину")),
      );
    }
  }

  Future<void> _runSafe(Future<void> Function() action, String errorText) async {
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorText)),
      );
    }
  }

  Color _mapCardColor(String key) {
    return _cardColors[key] ?? _cardColors["default"]!;
  }

  Color _noteTextColor(String colorKey, ColorScheme cs) {
    switch (colorKey) {
      case "green":
      case "default":
      case "blue":
      case "teal":
      case "yellow":
        return const Color(0xFF202124);
      case "red":
        return Colors.white;
      default:
        return cs.onSurface;
    }
  }

  Widget _buildTrashCard(NoteItem note, TextTheme textTheme, ColorScheme cs) {
    final cardColor = _mapCardColor(note.color);
    final textColor = _noteTextColor(note.color, cs);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              note.title.isEmpty ? "Без названия" : note.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleMedium?.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              note.plainContent.isEmpty ? "Чеклист" : note.plainContent,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(color: textColor),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.swipe_right_alt_rounded, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  "Восстановить",
                  style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text("Корзина (${_trash.length})"),
        actions: [
          TextButton.icon(
            onPressed: _busy || _trash.isEmpty
                ? null
                : () async {
                    setState(() => _busy = true);
                    await _runSafe(() async {
                      await _repository.restoreMany(_trash.map((n) => n.id));
                      if (!mounted) return;
                      setState(() => _trash = const []);
                    }, "Не удалось восстановить заметки");
                    if (mounted) setState(() => _busy = false);
                  },
            icon: const Icon(Icons.restore_from_trash_outlined, size: 18),
            label: const Text("Все"),
          ),
          TextButton.icon(
            onPressed: _busy || _trash.isEmpty
                ? null
                : () async {
                    setState(() => _busy = true);
                    await _runSafe(() async {
                      await _repository.hardDeleteMany(_trash.map((n) => n.id));
                      if (!mounted) return;
                      setState(() => _trash = const []);
                    }, "Не удалось очистить корзину");
                    if (mounted) setState(() => _busy = false);
                  },
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: const Text("Очистить"),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _trash.isEmpty
              ? Center(
                  child: Text(
                    "Корзина пуста",
                    style: textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  itemCount: _trash.length,
                  itemBuilder: (_, index) {
                    final note = _trash[index];
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == _trash.length - 1 ? 0 : 10,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: _SwipeActionCard(
                          key: ValueKey("trash-note-${note.id}"),
                          borderRadius: 14,
                          startBackgroundColor: const Color(0xFF2E7D32),
                          endBackgroundColor: cs.error,
                          startIcon: Icons.restore_from_trash_outlined,
                          endIcon: Icons.delete_forever_outlined,
                          onDismissToEnd: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            var ok = false;
                            await _runSafe(() async {
                              await _repository.restore(note.id);
                              ok = true;
                            }, "Не удалось восстановить заметку");
                            if (!ok || !mounted) return;
                            setState(() {
                              _trash = _trash.where((n) => n.id != note.id).toList();
                            });
                            messenger.showSnackBar(
                              const SnackBar(content: Text("Заметка восстановлена")),
                            );
                          },
                          onDismissToStart: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            var ok = false;
                            await _runSafe(() async {
                              await _repository.hardDelete(note.id);
                              ok = true;
                            }, "Не удалось удалить заметку");
                            if (!ok || !mounted) return;
                            setState(() {
                              _trash = _trash.where((n) => n.id != note.id).toList();
                            });
                            messenger.showSnackBar(
                              const SnackBar(content: Text("Заметка удалена навсегда")),
                            );
                          },
                          child: _buildTrashCard(note, textTheme, cs),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _SwipeToDeleteCard extends StatefulWidget {
  const _SwipeToDeleteCard({
    super.key,
    required this.child,
    required this.onDismissed,
    required this.onSwipingChanged,
    required this.backgroundColor,
    required this.borderRadius,
  });

  final Widget child;
  final Future<void> Function() onDismissed;
  final ValueChanged<bool> onSwipingChanged;
  final Color backgroundColor;
  final double borderRadius;

  @override
  State<_SwipeToDeleteCard> createState() => _SwipeToDeleteCardState();
}

class _SwipeToDeleteCardState extends State<_SwipeToDeleteCard>
    with SingleTickerProviderStateMixin {
  static const double _dismissThreshold = 0.42;
  static const double _minVelocityToDismiss = 980;

  late final AnimationController _controller;
  Animation<double>? _offsetAnimation;

  double _offsetX = 0;
  bool _isAnimatingOut = false;
  bool _isSwiping = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )
      ..addListener(() {
        if (!mounted || _offsetAnimation == null) return;
        setState(() => _offsetX = _offsetAnimation!.value);
      })
      ..addStatusListener((status) async {
        if (status != AnimationStatus.completed || !_isAnimatingOut) return;
        _isAnimatingOut = false;
        await widget.onDismissed();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setSwiping(bool value) {
    if (_isSwiping == value) return;
    _isSwiping = value;
    widget.onSwipingChanged(value);
  }

  void _animateTo(double target, {required Duration duration, bool dismiss = false}) {
    _controller.stop();
    _controller.duration = duration;
    _offsetAnimation = Tween<double>(begin: _offsetX, end: target).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _isAnimatingOut = dismiss;
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final progress = width <= 0 ? 0.0 : (-_offsetX / width).clamp(0.0, 1.0);
        final iconOpacity = (progress * 1.7).clamp(0.0, 1.0);
        final iconOffset = (1 - iconOpacity) * 12;

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (_) {
            _controller.stop();
          },
          onHorizontalDragUpdate: (details) {
            if (_isAnimatingOut) return;
            final next = (_offsetX + details.delta.dx).clamp(-width, 0.0);
            if (!mounted) return;
            setState(() => _offsetX = next);
            _setSwiping(next.abs() > 0.5);
          },
          onHorizontalDragEnd: (details) {
            if (_isAnimatingOut) return;
            final shouldDismiss =
                details.primaryVelocity != null &&
                    details.primaryVelocity! < -_minVelocityToDismiss ||
                progress >= _dismissThreshold;

            if (shouldDismiss) {
              _setSwiping(false);
              _animateTo(-width, duration: const Duration(milliseconds: 160), dismiss: true);
            } else {
              _animateTo(0, duration: const Duration(milliseconds: 200));
              _setSwiping(false);
            }
          },
          onHorizontalDragCancel: () {
            if (_isAnimatingOut) return;
            _animateTo(0, duration: const Duration(milliseconds: 200));
            _setSwiping(false);
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: widget.backgroundColor),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Opacity(
                          opacity: iconOpacity,
                          child: Transform.translate(
                            offset: Offset(iconOffset, 0),
                            child: const Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(_offsetX, 0),
                  child: widget.child,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SwipeActionCard extends StatefulWidget {
  const _SwipeActionCard({
    super.key,
    required this.child,
    required this.borderRadius,
    required this.startBackgroundColor,
    required this.endBackgroundColor,
    required this.startIcon,
    required this.endIcon,
    required this.onDismissToStart,
    required this.onDismissToEnd,
  });

  final Widget child;
  final double borderRadius;
  final Color startBackgroundColor;
  final Color endBackgroundColor;
  final IconData startIcon;
  final IconData endIcon;
  final Future<void> Function() onDismissToStart;
  final Future<void> Function() onDismissToEnd;

  @override
  State<_SwipeActionCard> createState() => _SwipeActionCardState();
}

class _SwipeActionCardState extends State<_SwipeActionCard>
    with SingleTickerProviderStateMixin {
  static const double _dismissThreshold = 0.42;
  static const double _minVelocityToDismiss = 980;

  late final AnimationController _controller;
  Animation<double>? _offsetAnimation;
  double _offsetX = 0;
  bool _isAnimatingOut = false;
  bool _dismissToStart = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )
      ..addListener(() {
        if (!mounted || _offsetAnimation == null) return;
        setState(() => _offsetX = _offsetAnimation!.value);
      })
      ..addStatusListener((status) async {
        if (status != AnimationStatus.completed || !_isAnimatingOut) return;
        _isAnimatingOut = false;
        if (_dismissToStart) {
          await widget.onDismissToStart();
        } else {
          await widget.onDismissToEnd();
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(double target, {required Duration duration, bool dismiss = false}) {
    _controller.stop();
    _controller.duration = duration;
    _offsetAnimation = Tween<double>(begin: _offsetX, end: target).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _isAnimatingOut = dismiss;
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final startProgress = width <= 0 ? 0.0 : (_offsetX / width).clamp(0.0, 1.0);
        final endProgress = width <= 0 ? 0.0 : (-_offsetX / width).clamp(0.0, 1.0);
        final startOpacity = (startProgress * 1.7).clamp(0.0, 1.0);
        final endOpacity = (endProgress * 1.7).clamp(0.0, 1.0);
        final startIconOffset = (1 - startOpacity) * -12;
        final endIconOffset = (1 - endOpacity) * 12;

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (_) => _controller.stop(),
          onHorizontalDragUpdate: (details) {
            if (_isAnimatingOut) return;
            final next = (_offsetX + details.delta.dx).clamp(-width, width);
            if (!mounted) return;
            setState(() => _offsetX = next);
          },
          onHorizontalDragEnd: (details) {
            if (_isAnimatingOut) return;
            final velocity = details.primaryVelocity ?? 0;
            final dismissEndByVelocity = velocity < -_minVelocityToDismiss;
            final dismissStartByVelocity = velocity > _minVelocityToDismiss;
            final dismissByProgress =
                endProgress >= _dismissThreshold || startProgress >= _dismissThreshold;
            final shouldDismiss =
                dismissEndByVelocity || dismissStartByVelocity || dismissByProgress;

            if (shouldDismiss) {
              final dismissToStart = dismissEndByVelocity ||
                  (!dismissStartByVelocity && endProgress >= startProgress);
              _dismissToStart = dismissToStart;
              _animateTo(
                dismissToStart ? -width : width,
                duration: const Duration(milliseconds: 160),
                dismiss: true,
              );
            } else {
              _animateTo(0, duration: const Duration(milliseconds: 200));
            }
          },
          onHorizontalDragCancel: () {
            if (_isAnimatingOut) return;
            _animateTo(0, duration: const Duration(milliseconds: 200));
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                widget.startBackgroundColor,
                                Color.lerp(
                                      widget.startBackgroundColor,
                                      widget.endBackgroundColor,
                                      0.5,
                                    ) ??
                                    widget.startBackgroundColor,
                                widget.endBackgroundColor,
                              ],
                              stops: const [0, 0.5, 1],
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Opacity(
                            opacity: startOpacity,
                            child: Transform.translate(
                              offset: Offset(startIconOffset, 0),
                              child: Icon(widget.startIcon, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Opacity(
                            opacity: endOpacity,
                            child: Transform.translate(
                              offset: Offset(endIconOffset, 0),
                              child: Icon(widget.endIcon, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Transform.translate(
                  offset: Offset(_offsetX, 0),
                  child: widget.child,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
