import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter_quill/flutter_quill.dart";

import "../domain/note_models.dart";

class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({
    super.key,
    this.initial,
    this.initialType,
    this.defaultGroupFile,
    this.defaultCollege,
    this.defaultGroupName,
    this.scheduleIndex = const {},
  });

  final NoteItem? initial;
  final NoteType? initialType;
  final String? defaultGroupFile;
  final String? defaultCollege;
  final String? defaultGroupName;
  final Map<String, List<int>> scheduleIndex;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  static const _colors = <String, Color>{
    "default": Color(0xFFFFFFFF),
    "yellow": Color(0xFFFFF9C4),
    "green": Color(0xFFCCFF90),
    "blue": Color(0xFFAECBFA),
    "red": Color(0xFFF28B82),
    "purple": Color(0xFFD7AEFB),
    "teal": Color(0xFFA8F0E6),
  };

  final _titleController = TextEditingController();
  final _tagsController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  late final QuillController _quillController;

  final List<NoteChecklistItem> _checklist = [];

  late bool _isPinned;
  late bool _isChecklist;
  late String _color;
  String? _linkedDate;
  int? _linkedLesson;
  bool _saving = false;
  bool _toolbarExpanded = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _titleController.text = initial?.title ?? "";
    _tagsController.text = (initial?.tags ?? const []).join(", ");
    _isPinned = initial?.isPinned ?? false;
    _isChecklist =
        (initial?.type ?? widget.initialType ?? NoteType.text) == NoteType.checklist;
    _color = initial?.color ?? "default";
    _linkedDate = initial?.scheduleDate;
    _linkedLesson = initial?.lessonNumber;
    _checklist.addAll(initial?.checklist ?? const []);
    _quillController = _initQuillController(initial?.content ?? "");
  }

  @override
  void dispose() {
    _titleController.dispose();
    _tagsController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _quillController.dispose();
    super.dispose();
  }

  QuillController _initQuillController(String content) {
    if (content.isEmpty) return QuillController.basic();
    try {
      final decoded = jsonDecode(content);
      if (decoded is List) {
        return QuillController(
          document: Document.fromJson(decoded),
          selection: const TextSelection.collapsed(offset: 0),
        );
      }
    } catch (_) {}
    final doc = Document()..insert(0, content);
    return QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final textTheme = theme.textTheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _saveAndPop();
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          titleSpacing: 0,
          leadingWidth: 60,
          leading: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: IconButton(
              tooltip: "Назад",
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              onPressed: _saveAndPop,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          title: Align(
            alignment: Alignment.centerLeft,
            child: Text(widget.initial == null ? "Новая заметка" : "Изменение"),
          ),
          actions: [
            IconButton(
              tooltip: _isPinned ? "Открепить" : "Закрепить",
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              style: IconButton.styleFrom(
                backgroundColor: _isPinned
                    ? cs.primary.withAlpha(26)
                    : cs.surfaceContainerHighest,
                shape: const CircleBorder(),
              ),
              onPressed: () => setState(() => _isPinned = !_isPinned),
              icon: Icon(
                _isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: _isPinned ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                children: [
                  TextField(
                    controller: _titleController,
                    onChanged: (_) => setState(() {}),
                    maxLines: 1,
                    style: textTheme.titleLarge?.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: "Введите заголовок",
                      hintStyle: textTheme.titleMedium?.copyWith(
                        color: cs.onSurfaceVariant.withAlpha(170),
                        fontWeight: FontWeight.w600,
                      ),
                      filled: false,
                      isDense: true,
                      suffixIcon: _titleController.text.trim().isEmpty
                          ? null
                          : IconButton(
                              tooltip: "Очистить",
                              onPressed: () {
                                _titleController.clear();
                                setState(() {});
                              },
                              icon: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_isChecklist)
                    _buildChecklistCard(textTheme, cs)
                  else
                    _buildEditorCard(textTheme, cs),
                  const SizedBox(height: 12),
                  _buildScheduleLinkCard(textTheme),
                  const SizedBox(height: 12),
                  _buildTagsBlock(textTheme),
                  const SizedBox(height: 12),
                  Text(
                    "ЦВЕТ КАРТОЧКИ",
                    style: textTheme.labelSmall?.copyWith(
                      fontSize: 12,
                      letterSpacing: 1.6,
                      color: const Color.fromRGBO(255, 255, 255, 0.45),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: _colors.entries.map((entry) {
                      final selected = entry.key == _color;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: GestureDetector(
                          onTap: () => setState(() => _color = entry.key),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: entry.value,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected
                                    ? Colors.white
                                    : const Color.fromRGBO(255, 255, 255, 0.2),
                                width: selected ? 2 : 1,
                              ),
                              boxShadow: selected
                                  ? const [
                                      BoxShadow(
                                        color: Color.fromRGBO(255, 255, 255, 0.45),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : const [],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            if (!_isChecklist) _buildToolbar(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorCard(TextTheme textTheme, ColorScheme cs) {
    return Container(
      constraints: BoxConstraints(
        minHeight: MediaQuery.of(context).size.height * 0.34,
      ),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color.fromRGBO(255, 255, 255, 0.07),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: QuillEditor.basic(
        controller: _quillController,
        focusNode: _focusNode,
        config: QuillEditorConfig(
          autoFocus: widget.initial == null,
          placeholder: "Текст заметки...",
          customStyles: const DefaultStyles(
            placeHolder: DefaultTextBlockStyle(
              TextStyle(color: Color.fromRGBO(255, 255, 255, 0.25)),
              HorizontalSpacing(0, 0),
              VerticalSpacing(0, 0),
              VerticalSpacing(0, 0),
              null,
            ),
          ),
          expands: false,
          scrollable: true,
          padding: const EdgeInsets.all(4),
        ),
      ),
    );
  }

  Widget _buildToolbar(ThemeData theme) {
    final cs = theme.colorScheme;
    return SafeArea(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          border: Border(
            top: BorderSide(color: theme.colorScheme.outline.withAlpha(40)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  _headingChip(1),
                  const SizedBox(width: 4),
                  _headingChip(2),
                  const SizedBox(width: 4),
                  _headingChip(3),
                  const SizedBox(width: 8),
                  _tbIcon(Icons.undo_rounded, "Отменить", _quillController.undo),
                  _tbIcon(Icons.redo_rounded, "Повторить", _quillController.redo),
                  _tbIcon(
                    Icons.format_bold,
                    "Жирный",
                    () => _quillController.formatSelection(Attribute.bold),
                    active: _isAttributeActive(Attribute.bold),
                  ),
                  _tbIcon(
                    Icons.format_italic,
                    "Курсив",
                    () => _quillController.formatSelection(Attribute.italic),
                    active: _isAttributeActive(Attribute.italic),
                  ),
                  _tbIcon(
                    Icons.format_underlined,
                    "Подчеркнутый",
                    () => _quillController.formatSelection(Attribute.underline),
                    active: _isAttributeActive(Attribute.underline),
                  ),
                  _tbIcon(Icons.strikethrough_s, "Зачеркнутый", () {
                    _quillController.formatSelection(Attribute.strikeThrough);
                  }, active: _isAttributeActive(Attribute.strikeThrough)),
                  _tbIcon(Icons.format_list_bulleted_rounded, "Список", () {
                    _quillController.formatSelection(Attribute.ul);
                  }, active: _isAttributeActive(Attribute.ul)),
                  _tbIcon(Icons.format_list_numbered_rounded, "Нумерация", () {
                    _quillController.formatSelection(Attribute.ol);
                  }, active: _isAttributeActive(Attribute.ol)),
                  _tbIcon(Icons.horizontal_rule_rounded, "Разделитель", () {
                    _quillController.replaceText(
                      _quillController.selection.baseOffset,
                      0,
                      "\n---\n",
                      const TextSelection.collapsed(offset: 0),
                    );
                  }),
                ],
              ),
            ),
            if (_toolbarExpanded)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
                child: Row(
                  children: [
                    _tbIcon(Icons.format_quote_rounded, "Цитата", () {
                      _quillController.formatSelection(Attribute.blockQuote);
                    }, active: _isAttributeActive(Attribute.blockQuote)),
                    _tbIcon(Icons.check_box_outlined, "Чекбокс", () {
                      _quillController.formatSelection(Attribute.unchecked);
                    }, active: _isAttributeActive(Attribute.unchecked)),
                    _tbIcon(Icons.clear_rounded, "Сброс стиля", () {
                      _quillController.formatSelection(Attribute.clone(Attribute.bold, null));
                      _quillController.formatSelection(Attribute.clone(Attribute.italic, null));
                      _quillController.formatSelection(
                        Attribute.clone(Attribute.underline, null),
                      );
                      _quillController.formatSelection(
                        Attribute.clone(Attribute.strikeThrough, null),
                      );
                      _quillController.formatSelection(Attribute.clone(Attribute.h1, null));
                      _quillController.formatSelection(Attribute.clone(Attribute.h2, null));
                      _quillController.formatSelection(Attribute.clone(Attribute.h3, null));
                    }),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: _toolbarExpanded ? "Свернуть" : "Развернуть",
                onPressed: () => setState(() => _toolbarExpanded = !_toolbarExpanded),
                color: cs.onSurfaceVariant,
                icon: AnimatedRotation(
                  duration: const Duration(milliseconds: 180),
                  turns: _toolbarExpanded ? 0.5 : 0,
                  child: const Icon(Icons.expand_more_rounded),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _tbIcon(
    IconData icon,
    String tooltip,
    VoidCallback onTap, {
    bool active = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      visualDensity: VisualDensity.comfortable,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: active ? cs.primary.withAlpha(28) : Colors.transparent,
      ),
      onPressed: onTap,
      color: active ? cs.primary : const Color.fromRGBO(255, 255, 255, 0.72),
      icon: Icon(icon, size: 20),
    );
  }

  Widget _headingChip(int level) {
    final selected = _activeHeadingLevelFromSelection() == level;
    return ChoiceChip(
      label: Text("H$level"),
      selected: selected,
      onSelected: (_) {
        if (selected) {
          _quillController.formatSelection(Attribute.clone(Attribute.h1, null));
          _quillController.formatSelection(Attribute.clone(Attribute.h2, null));
          _quillController.formatSelection(Attribute.clone(Attribute.h3, null));
          return;
        }
        if (level == 1) {
          _quillController.formatSelection(Attribute.h1);
        } else if (level == 2) {
          _quillController.formatSelection(Attribute.h2);
        } else {
          _quillController.formatSelection(Attribute.h3);
        }
      },
    );
  }

  bool _isAttributeActive(Attribute<dynamic> attribute) {
    final active =
        _quillController.getSelectionStyle().attributes[attribute.key];
    if (active == null) return false;
    if (attribute.value == null) return true;
    return active.value == attribute.value;
  }

  int? _activeHeadingLevelFromSelection() {
    final attr = _quillController.getSelectionStyle().attributes[Attribute.header.key];
    final value = attr?.value;
    if (value is int) return value;
    return null;
  }

  Widget _buildChecklistCard(TextTheme textTheme, ColorScheme cs) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            ..._checklist.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Checkbox(
                      value: item.done,
                      onChanged: (value) {
                        setState(() {
                          _checklist[index] = NoteChecklistItem(
                            id: item.id,
                            text: item.text,
                            done: value ?? false,
                          );
                        });
                      },
                    ),
                    Expanded(
                      child: TextFormField(
                        initialValue: item.text,
                        onChanged: (value) {
                          _checklist[index] = NoteChecklistItem(
                            id: item.id,
                            text: value,
                            done: item.done,
                          );
                        },
                        decoration: const InputDecoration(
                          hintText: "Пункт",
                        ),
                        style: textTheme.bodyMedium?.copyWith(
                          decoration: item.done ? TextDecoration.lineThrough : null,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: "Удалить",
                      onPressed: () => setState(() => _checklist.removeAt(index)),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              );
            }),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () {
                  final id = DateTime.now().microsecondsSinceEpoch.toString();
                  setState(() {
                    _checklist.add(
                      NoteChecklistItem(id: id, text: "", done: false),
                    );
                  });
                },
                icon: const Icon(Icons.add),
                label: const Text("Добавить пункт"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleLinkCard(TextTheme textTheme) {
    final cs = Theme.of(context).colorScheme;
    final hasLink = _linkedDate != null;
    final dates = widget.scheduleIndex.keys.toList()..sort();
    if (_linkedDate != null && !dates.contains(_linkedDate)) {
      dates.add(_linkedDate!);
      dates.sort();
    }
    final lessons = _linkedDate == null
        ? const <int>[]
        : (widget.scheduleIndex[_linkedDate!] ?? const <int>[]);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withAlpha(100),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withAlpha(140)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event_note_outlined, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Привязка к расписанию",
                    style: textTheme.titleSmall?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Switch(
                  value: hasLink,
                  onChanged: (value) {
                    setState(() {
                      if (value) {
                        _linkedDate =
                            dates.isNotEmpty ? dates.first : _todayKey();
                      } else {
                        _linkedDate = null;
                        _linkedLesson = null;
                      }
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              hasLink
                  ? "Заметка привязана и будет видна в расписании."
                  : "Добавь привязку, чтобы быстро открывать заметку из дня/пары.",
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (hasLink) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: const Icon(Icons.calendar_today_rounded, size: 14),
                    label: Text(_linkedDate ?? "Без даты"),
                    visualDensity: VisualDensity.compact,
                  ),
                  Chip(
                    avatar: const Icon(Icons.schedule_rounded, size: 14),
                    label: Text(
                      _linkedLesson == null
                          ? "Весь день"
                          : "$_linkedLesson пара",
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
            if (hasLink) ...[
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _linkedDate,
                decoration: InputDecoration(
                  labelText: "День",
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                  ),
                  filled: true,
                  fillColor: cs.surface.withAlpha(210),
                ),
                items: dates
                    .map((date) => DropdownMenuItem(value: date, child: Text(date)))
                    .toList(),
                onChanged: (value) => setState(() {
                  _linkedDate = value;
                  _linkedLesson = null;
                }),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      initialValue: _linkedLesson,
                      decoration: InputDecoration(
                        labelText: "Пара (опционально)",
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(16)),
                        ),
                        filled: true,
                        fillColor: cs.surface.withAlpha(210),
                      ),
                      items: <DropdownMenuItem<int?>>[
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text("Весь день"),
                        ),
                        ...lessons.map(
                          (lesson) => DropdownMenuItem<int?>(
                            value: lesson,
                            child: Text("$lesson пара"),
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(() => _linkedLesson = value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => setState(() {
                      _linkedDate = null;
                      _linkedLesson = null;
                    }),
                    child: const Text("Отвязать"),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _linkedDate = dates.isNotEmpty ? dates.first : _todayKey();
                  _linkedLesson = null;
                }),
                icon: const Icon(Icons.link_rounded),
                label: const Text("Привязать к ближайшему дню"),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTagsBlock(TextTheme textTheme) {
    final cs = Theme.of(context).colorScheme;
    final selectedTags = _tagsController.text
        .split(",")
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    const suggestedTags = <String>[
      "Учеба",
      "Домашка",
      "Экзамен",
      "Важно",
      "Идея",
      "Личное",
      "Проект",
    ];
    final options = <String>{...suggestedTags, ...selectedTags}.toList()..sort();

    void toggleTag(String tag, bool next) {
      setState(() {
        if (next) {
          selectedTags.add(tag);
        } else {
          selectedTags.remove(tag);
        }
        final ordered = selectedTags.toList()..sort();
        _tagsController.text = ordered.join(", ");
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Теги",
          style: textTheme.titleSmall?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withAlpha(140),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: cs.outlineVariant.withAlpha(170)),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options
                .map(
                  (tag) => FilterChip(
                    label: Text(tag),
                    selected: selectedTags.contains(tag),
                    onSelected: (value) => toggleTag(tag, value),
                    showCheckmark: true,
                    selectedColor: cs.primary.withAlpha(24),
                    checkmarkColor: cs.primary,
                    side: BorderSide(color: cs.outlineVariant),
                    labelStyle: textTheme.bodySmall?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  Future<void> _saveAndPop() async {
    if (_saving || !mounted) return;
    try {
      setState(() => _saving = true);
      final note = _buildNote();
      if (!mounted) return;
      Navigator.of(context).pop<NoteItem?>(note);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Не удалось сохранить заметку")),
      );
    }
  }

  NoteItem? _buildNote() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final initial = widget.initial;
    final title = _titleController.text.trim();
    final tags = _tagsController.text
        .split(",")
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    final checklist = _checklist.where((e) => e.text.trim().isNotEmpty).toList();
    final plainText = _quillController.document.toPlainText().trim();
    final content = _isChecklist
        ? ""
        : jsonEncode(_quillController.document.toDelta().toJson());

    final emptyTextNote = !_isChecklist && title.isEmpty && plainText.isEmpty;
    final emptyChecklist = _isChecklist && title.isEmpty && checklist.isEmpty;
    if (emptyTextNote || emptyChecklist) return null;

    return NoteItem(
      id: initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      content: content,
      type: _isChecklist ? NoteType.checklist : NoteType.text,
      color: _color,
      tags: tags,
      checklist: _isChecklist ? checklist : const [],
      isPinned: _isPinned,
      isArchived: initial?.isArchived ?? false,
      isDeleted: initial?.isDeleted ?? false,
      createdAt: initial?.createdAt ?? now,
      updatedAt: now,
      reminderAt: initial?.reminderAt,
      sortOrder: initial?.sortOrder ?? now.toDouble(),
      scheduleDate: _linkedDate,
      lessonNumber: _linkedLesson,
      groupFile: widget.defaultGroupFile ?? initial?.groupFile,
      college: widget.defaultCollege ?? initial?.college,
    );
  }

  String _todayKey() {
    final now = DateTime.now();
    final day = now.day.toString().padLeft(2, "0");
    final month = now.month.toString().padLeft(2, "0");
    return "$day.$month.${now.year}";
  }
}
