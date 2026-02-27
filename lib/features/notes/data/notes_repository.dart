import "dart:convert";

import "../../../core/database/schedule_database.dart";
import "../domain/note_models.dart";

class NotesRepository {
  NotesRepository({ScheduleDatabase? database})
      : _database = database ?? ScheduleDatabase.instance;

  final ScheduleDatabase _database;

  Future<List<NoteItem>> listNotes({
    bool includeArchived = false,
    bool includeDeleted = false,
    NoteSortMode sortMode = NoteSortMode.updatedDesc,
  }) async {
    final rows = await _database.listNotesRaw(
      includeArchived: includeArchived,
      includeDeleted: includeDeleted,
    );
    final tagsByNote = await _database.listNoteTagsMap();
    final notes = rows
        .map(
          (row) => NoteItem.fromDbMap(
            row,
            tags: tagsByNote[row["id"]] ?? const [],
          ),
        )
        .toList();
    notes.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      final byPrimary = _compareByMode(a, b, sortMode);
      if (byPrimary != 0) return byPrimary;

      final byManualOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byManualOrder != 0) return byManualOrder;

      final byUpdatedDesc = b.updatedAt.compareTo(a.updatedAt);
      if (byUpdatedDesc != 0) return byUpdatedDesc;

      final byCreatedDesc = b.createdAt.compareTo(a.createdAt);
      if (byCreatedDesc != 0) return byCreatedDesc;

      final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      if (byTitle != 0) return byTitle;

      return a.id.compareTo(b.id);
    });
    return notes;
  }

  int _compareByMode(NoteItem a, NoteItem b, NoteSortMode sortMode) {
    switch (sortMode) {
      case NoteSortMode.updatedDesc:
        return b.updatedAt.compareTo(a.updatedAt);
      case NoteSortMode.updatedAsc:
        return a.updatedAt.compareTo(b.updatedAt);
      case NoteSortMode.createdDesc:
        return b.createdAt.compareTo(a.createdAt);
      case NoteSortMode.createdAsc:
        return a.createdAt.compareTo(b.createdAt);
      }
  }

  Future<void> save(NoteItem item) async {
    await _database.upsertNoteRaw(item.toDbMap(), item.tags);
  }

  Future<void> setPinned(String id, bool value) async {
    await _database.setNoteFlagsRaw(id, pinned: value);
  }

  Future<void> setArchived(String id, bool value) async {
    await _database.setNoteFlagsRaw(id, archived: value);
  }

  Future<void> softDelete(String id) async {
    await _database.setNoteFlagsRaw(id, deleted: true);
  }

  Future<void> restore(String id) async {
    await _database.setNoteFlagsRaw(id, deleted: false, archived: false);
  }

  Future<void> hardDelete(String id) async {
    await _database.deleteNotePermanently(id);
  }

  Future<void> restoreMany(Iterable<String> ids) async {
    for (final id in ids) {
      await _database.setNoteFlagsRaw(id, deleted: false, archived: false);
    }
  }

  Future<void> hardDeleteMany(Iterable<String> ids) async {
    for (final id in ids) {
      await _database.deleteNotePermanently(id);
    }
  }

  Future<void> saveOrder(List<NoteItem> notes) async {
    await _database.saveNotesOrderRaw(
      notes.map((n) => (id: n.id, order: n.sortOrder)).toList(),
    );
  }

  Future<String> exportJson() async {
    final payload = await _database.exportNotesPayload();
    return jsonEncode(payload);
  }

  Future<void> importJson(String rawJson, {required bool replace}) async {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException("Некорректный формат файла заметок");
    }
    await _database.importNotesPayload(decoded, replace: replace);
  }

  Future<void> saveSortMode(NoteSortMode mode) async {
    await _database.saveDatabaseSetting("notes_sort_mode", mode.name);
  }

  Future<NoteSortMode> loadSortMode() async {
    final raw = await _database.getDatabaseSetting("notes_sort_mode");
    return NoteSortMode.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => NoteSortMode.updatedDesc,
    );
  }

  Future<void> saveViewMode({required bool grid}) async {
    await _database.saveDatabaseSetting("notes_view_mode", grid ? "grid" : "list");
  }

  Future<bool> loadViewMode() async {
    final raw = await _database.getDatabaseSetting("notes_view_mode");
    return raw != "list";
  }
}
