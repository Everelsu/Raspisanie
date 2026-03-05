import "dart:convert";
import "dart:io";

import "package:path/path.dart" as p;
import "package:sqflite/sqflite.dart";

import "../../features/schedule/domain/models.dart";

class ScheduleDatabase {
  ScheduleDatabase._();
  static final ScheduleDatabase instance = ScheduleDatabase._();

  Database? _database;
  DateTime? _lastCleanup;
  static const _cleanupInterval = Duration(hours: 6);

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    final path = await databaseFilePath();

    return openDatabase(path, version: 10, onCreate: (db, version) async {
      await _createTables(db);
    }, onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS schedule_days (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            group_file TEXT NOT NULL,
            college TEXT NOT NULL,
            schedule_date TEXT NOT NULL,
            day_name TEXT NOT NULL,
            week_number INTEGER NOT NULL,
            items_json TEXT NOT NULL,
            fetched_at INTEGER NOT NULL,
            source_hash TEXT,
            is_actual INTEGER NOT NULL DEFAULT 1,
            UNIQUE(group_file, college, schedule_date) ON CONFLICT REPLACE
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS db_settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS sync_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            group_file TEXT NOT NULL,
            college TEXT NOT NULL,
            synced_at INTEGER NOT NULL,
            status TEXT NOT NULL,
            records_upserted INTEGER NOT NULL DEFAULT 0,
            error_message TEXT
          )
        ''');
      }
      if (oldVersion < 3) {
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_snapshots_group_college
          ON schedule_snapshots(group_file, college, fetched_at)
        ''');
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_days_group_college_date
          ON schedule_days(group_file, college, schedule_date)
        ''');
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_days_fetched
          ON schedule_days(fetched_at)
        ''');
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_sync_log_group
          ON sync_log(group_file, college, synced_at)
        ''');
      }
      if (oldVersion < 4) {
        await _createNotesTables(db);
      }
      if (oldVersion < 5) {
        await _upgradeNotesV5(db);
      }
      if (oldVersion < 6) {
        await _upgradeNotesV6(db);
      }
      if (oldVersion < 7) {
        await _upgradeNotesV7(db);
      }
      if (oldVersion < 8) {
        await _upgradeNotesV8(db);
      }
      if (oldVersion < 9) {
        await _upgradeChatMessagesV9(db);
      }
      if (oldVersion < 10) {
        await _upgradeChatMessagesV10(db);
      }
    });
  }

  Future<void> _upgradeChatMessagesV9(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_messages (
        id TEXT PRIMARY KEY,
        author_id TEXT NOT NULL,
        text TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        is_pinned INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_chat_messages_created_at ON chat_messages(created_at)");
  }

  Future<void> _upgradeChatMessagesV10(Database db) async {
    await _tryAddColumn(db, "chat_messages", "message_type TEXT NOT NULL DEFAULT 'text'");
    await _tryAddColumn(db, "chat_messages", "payload TEXT");
  }

  Future<void> _upgradeNotesV8(Database db) async {
    await _tryAddColumn(db, "notes", "image_paths TEXT DEFAULT '[]'");
    await _tryAddColumn(db, "notes", "voice_paths TEXT DEFAULT '[]'");
  }

  Future<void> _upgradeNotesV6(Database db) async {
    await _tryAddColumn(db, "notes", "image_path TEXT");
  }

  Future<void> _upgradeNotesV7(Database db) async {
    await _tryAddColumn(db, "notes", "reply_to_id TEXT");
    await _tryAddColumn(db, "notes", "reply_preview TEXT");
  }

  Future<String> databaseFilePath() async {
    final dbPath = await getDatabasesPath();
    return p.join(dbPath, "raspiflutter.db");
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS schedule_snapshots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_file TEXT,
        college TEXT,
        fetched_at INTEGER,
        schedule_json TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS schedule_days (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_file TEXT NOT NULL,
        college TEXT NOT NULL,
        schedule_date TEXT NOT NULL,
        day_name TEXT NOT NULL,
        week_number INTEGER NOT NULL,
        items_json TEXT NOT NULL,
        fetched_at INTEGER NOT NULL,
        source_hash TEXT,
        is_actual INTEGER NOT NULL DEFAULT 1,
        UNIQUE(group_file, college, schedule_date) ON CONFLICT REPLACE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS groups_cache (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        college TEXT,
        groups_json TEXT,
        cached_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS current_schedule (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_file TEXT,
        college TEXT,
        schedule_json TEXT,
        cached_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS db_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_file TEXT NOT NULL,
        college TEXT NOT NULL,
        synced_at INTEGER NOT NULL,
        status TEXT NOT NULL,
        records_upserted INTEGER NOT NULL DEFAULT 0,
        error_message TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_snapshots_group_college
      ON schedule_snapshots(group_file, college, fetched_at)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_days_group_college_date
      ON schedule_days(group_file, college, schedule_date)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_days_fetched
      ON schedule_days(fetched_at)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_log_group
      ON sync_log(group_file, college, synced_at)
    ''');

    await _createNotesTables(db);
  }

  Future<void> _createNotesTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        type TEXT NOT NULL DEFAULT 'text',
        color TEXT NOT NULL DEFAULT 'default',
        checklist_json TEXT NOT NULL DEFAULT '[]',
        is_pinned INTEGER NOT NULL DEFAULT 0,
        is_archived INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        reminder_at INTEGER,
        sort_order REAL NOT NULL DEFAULT 0,
        schedule_date TEXT,
        lesson_number INTEGER,
        group_file TEXT,
        college TEXT,
        image_path TEXT,
        reply_to_id TEXT,
        reply_preview TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS note_tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS note_tag_links (
        note_id TEXT NOT NULL,
        tag_id INTEGER NOT NULL,
        PRIMARY KEY (note_id, tag_id),
        FOREIGN KEY (note_id) REFERENCES notes(id) ON DELETE CASCADE,
        FOREIGN KEY (tag_id) REFERENCES note_tags(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS note_revisions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        note_id TEXT NOT NULL,
        snapshot_json TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_notes_updated_at ON notes(updated_at)");
    await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_notes_is_pinned ON notes(is_pinned)");
    await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_notes_is_archived ON notes(is_archived)");
    await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_notes_is_deleted ON notes(is_deleted)");
    await db
        .execute("CREATE INDEX IF NOT EXISTS idx_notes_color ON notes(color)");
    await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_notes_reminder ON notes(reminder_at)");
    await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_note_links_note ON note_tag_links(note_id)");
    await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_note_links_tag ON note_tag_links(tag_id)");
    await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_note_revision_note ON note_revisions(note_id, created_at)");
    await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_notes_schedule_date ON notes(schedule_date)");
    await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_notes_group_college ON notes(group_file, college)");
  }

  Future<void> _upgradeNotesV5(Database db) async {
    await _tryAddColumn(db, "notes", "schedule_date TEXT");
    await _tryAddColumn(db, "notes", "lesson_number INTEGER");
    await _tryAddColumn(db, "notes", "group_file TEXT");
    await _tryAddColumn(db, "notes", "college TEXT");
    await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_notes_schedule_date ON notes(schedule_date)");
    await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_notes_group_college ON notes(group_file, college)");
  }

  Future<void> _tryAddColumn(Database db, String table, String def) async {
    try {
      await db.execute("ALTER TABLE $table ADD COLUMN $def");
    } catch (_) {
      // Column already exists on some devices.
    }
  }

  Future<void> saveScheduleSnapshot(
    String groupFile,
    String college,
    String scheduleJson, {
    List<DaySchedule>? parsedDays,
  }) async {
    var days = parsedDays ?? const <DaySchedule>[];
    if (days.isEmpty) {
      try {
        days = (jsonDecode(scheduleJson) as List)
            .map((e) => DaySchedule.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    if (days.isNotEmpty) {
      await saveScheduleDays(groupFile, college, days);
    }

    final db = await database;
    await db.insert('schedule_snapshots', {
      'group_file': groupFile,
      'college': college,
      'fetched_at': DateTime.now().millisecondsSinceEpoch,
      'schedule_json': scheduleJson,
    });

    final count = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM schedule_snapshots WHERE group_file = ? AND college = ?',
      [groupFile, college],
    );
    final total = (count.first['cnt'] as int?) ?? 0;

    if (total > 100) {
      await db.rawDelete('''
        DELETE FROM schedule_snapshots WHERE id IN (
          SELECT id FROM schedule_snapshots
          WHERE group_file = ? AND college = ?
          ORDER BY fetched_at ASC
          LIMIT ?
        )
      ''', [groupFile, college, total - 100]);
    }
  }

  Future<int> saveScheduleDays(
    String groupFile,
    String college,
    List<DaySchedule> days,
  ) async {
    if (days.isEmpty) return 0;
    final db = await database;
    final fetchedAt = DateTime.now().millisecondsSinceEpoch;
    var upserted = 0;
    await db.transaction((txn) async {
      for (final day in days) {
        final dayJson = jsonEncode(day.items.map((e) => e.toJson()).toList());
        await txn.insert(
          "schedule_days",
          {
            "group_file": groupFile,
            "college": college,
            "schedule_date": day.date,
            "day_name": day.day,
            "week_number": day.weekNumber,
            "items_json": dayJson,
            "fetched_at": fetchedAt,
            "source_hash": dayJson.hashCode.toString(),
            "is_actual": 1,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        upserted++;
      }
    });

    await addSyncLog(
      groupFile: groupFile,
      college: college,
      status: "ok",
      recordsUpserted: upserted,
    );
    await _maybeCleanup();
    return upserted;
  }

  Future<List<Map<String, dynamic>>> getSnapshotDates(
    String groupFile,
    String college,
  ) async {
    final db = await database;
    return db.query(
      'schedule_snapshots',
      columns: ['id', 'fetched_at'],
      where: 'group_file = ? AND college = ?',
      whereArgs: [groupFile, college],
      orderBy: 'fetched_at DESC',
    );
  }

  Future<String?> getSnapshotById(int id) async {
    final db = await database;
    final results = await db.query(
      'schedule_snapshots',
      columns: ['schedule_json'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return results.first['schedule_json'] as String?;
  }

  Future<List<DateTime>> getMarkedDays(
    String groupFile,
    String college,
  ) async {
    final db = await database;
    final results = await db.query(
      "schedule_days",
      columns: ["schedule_date"],
      distinct: true,
      where: 'group_file = ? AND college = ?',
      whereArgs: [groupFile, college],
    );

    final days = <DateTime>{};
    for (final row in results) {
      final raw = row["schedule_date"] as String?;
      final parsed = _parseDate(raw);
      if (parsed != null) {
        days.add(DateTime(parsed.year, parsed.month, parsed.day));
      }
    }
    return days.toList();
  }

  Future<DaySchedule?> getDayScheduleForDate(
    String groupFile,
    String college,
    DateTime date,
  ) async {
    final db = await database;
    final dateKey =
        "${date.day.toString().padLeft(2, "0")}.${date.month.toString().padLeft(2, "0")}.${date.year}";
    final rows = await db.query(
      "schedule_days",
      where: "group_file = ? AND college = ? AND schedule_date = ?",
      whereArgs: [groupFile, college, dateKey],
      orderBy: "fetched_at DESC",
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final items = (jsonDecode(row["items_json"] as String) as List)
        .map((e) => ScheduleItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return DaySchedule(
      day: row["day_name"] as String? ?? "",
      date: row["schedule_date"] as String? ?? dateKey,
      weekNumber: row["week_number"] as int? ?? 0,
      items: items,
    );
  }

  Future<String?> getSnapshotForDate(
    String groupFile,
    String college,
    DateTime date,
  ) async {
    final day = await getDayScheduleForDate(groupFile, college, date);
    if (day == null) return null;
    return jsonEncode([day.toJson()]);
  }

  Future<void> saveCurrentSchedule(
    String groupFile,
    String college,
    String scheduleJson,
  ) async {
    final db = await database;
    final existing = await db.query(
      'current_schedule',
      columns: ['id'],
      where: 'group_file = ? AND college = ?',
      whereArgs: [groupFile, college],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      await db.update(
        'current_schedule',
        {
          'schedule_json': scheduleJson,
          'cached_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    } else {
      await db.insert('current_schedule', {
        'group_file': groupFile,
        'college': college,
        'schedule_json': scheduleJson,
        'cached_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  Future<String?> loadCurrentSchedule(
    String groupFile,
    String college,
  ) async {
    final db = await database;
    final results = await db.query(
      'current_schedule',
      where: 'group_file = ? AND college = ?',
      whereArgs: [groupFile, college],
      limit: 1,
    );
    if (results.isEmpty) return null;

    final cachedAt = results.first['cached_at'] as int;
    final age = DateTime.now().millisecondsSinceEpoch - cachedAt;
    if (age > const Duration(days: 7).inMilliseconds) return null;

    return results.first['schedule_json'] as String?;
  }

  Future<void> saveGroupsCache(String college, String groupsJson) async {
    final db = await database;
    final existing = await db.query(
      'groups_cache',
      columns: ['id'],
      where: 'college = ?',
      whereArgs: [college],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      await db.update(
        'groups_cache',
        {
          'groups_json': groupsJson,
          'cached_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    } else {
      await db.insert('groups_cache', {
        'college': college,
        'groups_json': groupsJson,
        'cached_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  Future<String?> loadGroupsCache(String college) async {
    final db = await database;
    final results = await db.query(
      'groups_cache',
      where: 'college = ?',
      whereArgs: [college],
      limit: 1,
    );
    if (results.isEmpty) return null;

    final cachedAt = results.first['cached_at'] as int;
    final age = DateTime.now().millisecondsSinceEpoch - cachedAt;
    if (age > const Duration(hours: 24).inMilliseconds) return null;

    return results.first['groups_json'] as String?;
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('schedule_snapshots');
    await db.delete("schedule_days");
    await db.delete('groups_cache');
    await db.delete('current_schedule');
    await db.delete("db_settings");
    await db.delete("sync_log");
    await db.delete("note_tag_links");
    await db.delete("note_revisions");
    await db.delete("note_tags");
    await db.delete("notes");
  }

  Future<void> replaceDatabaseFromFile(String sourcePath) async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    final targetPath = await databaseFilePath();
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const FileSystemException("Файл базы данных не найден");
    }
    final target = File(targetPath);
    if (await target.exists()) {
      await target.delete();
    }
    await source.copy(targetPath);
    _database = await _initDb();
  }

  Future<int> getSnapshotCount() async {
    final db = await database;
    final result =
        await db.rawQuery("SELECT COUNT(*) as cnt FROM schedule_days");
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<void> deleteOldSnapshots(int keepCount) async {
    final db = await database;
    final groups = await db.rawQuery(
      "SELECT DISTINCT group_file, college FROM schedule_days",
    );

    for (final group in groups) {
      final groupFile = group['group_file'] as String;
      final college = group['college'] as String;

      await db.rawDelete('''
        DELETE FROM schedule_days WHERE id NOT IN (
          SELECT id FROM schedule_days
          WHERE group_file = ? AND college = ?
          ORDER BY fetched_at DESC
          LIMIT ?
        ) AND group_file = ? AND college = ?
      ''', [groupFile, college, keepCount, groupFile, college]);
    }
  }

  Future<void> saveDatabaseSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      "db_settings",
      {
        "key": key,
        "value": value,
        "updated_at": DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getDatabaseSetting(String key) async {
    final db = await database;
    final rows = await db.query(
      "db_settings",
      where: "key = ?",
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first["value"] as String?;
  }

  Future<void> addSyncLog({
    required String groupFile,
    required String college,
    required String status,
    required int recordsUpserted,
    String? errorMessage,
  }) async {
    final db = await database;
    await db.insert("sync_log", {
      "group_file": groupFile,
      "college": college,
      "synced_at": DateTime.now().millisecondsSinceEpoch,
      "status": status,
      "records_upserted": recordsUpserted,
      "error_message": errorMessage,
    });
  }

  Future<List<Map<String, dynamic>>> listNotesRaw({
    required bool includeArchived,
    required bool includeDeleted,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <Object>[];
    if (!includeArchived) {
      where.add("is_archived = ?");
      args.add(0);
    }
    if (!includeDeleted) {
      where.add("is_deleted = ?");
      args.add(0);
    }
    return db.query(
      "notes",
      where: where.isEmpty ? null : where.join(" AND "),
      whereArgs: args.isEmpty ? null : args,
      orderBy: "is_pinned DESC, sort_order DESC, updated_at DESC",
    );
  }

  Future<Map<String, List<String>>> listNoteTagsMap() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT l.note_id as note_id, t.name as tag_name
      FROM note_tag_links l
      JOIN note_tags t ON t.id = l.tag_id
    ''');
    final out = <String, List<String>>{};
    for (final row in rows) {
      final noteId = row["note_id"] as String?;
      final tagName = row["tag_name"] as String?;
      if (noteId == null || tagName == null) continue;
      out.putIfAbsent(noteId, () => <String>[]).add(tagName);
    }
    return out;
  }

  Future<void> upsertNoteRaw(
    Map<String, dynamic> note,
    List<String> tags,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert("notes", note,
          conflictAlgorithm: ConflictAlgorithm.replace);

      await txn.delete("note_tag_links",
          where: "note_id = ?", whereArgs: [note["id"]]);

      for (final tag in tags.map((e) => e.trim()).where((e) => e.isNotEmpty)) {
        final existing = await txn.query(
          "note_tags",
          columns: ["id"],
          where: "name = ?",
          whereArgs: [tag],
          limit: 1,
        );
        int tagId;
        if (existing.isNotEmpty) {
          tagId = existing.first["id"] as int;
        } else {
          tagId = await txn.insert("note_tags", {
            "name": tag,
            "created_at": DateTime.now().millisecondsSinceEpoch,
          });
        }
        await txn.insert(
          "note_tag_links",
          {
            "note_id": note["id"],
            "tag_id": tagId,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      await txn.insert("note_revisions", {
        "note_id": note["id"],
        "snapshot_json": jsonEncode(note),
        "created_at": DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  Future<void> saveNotesOrderRaw(List<({String id, double order})> rows) async {
    if (rows.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final row in rows) {
        await txn.update(
          "notes",
          {
            "sort_order": row.order,
            "updated_at": DateTime.now().millisecondsSinceEpoch,
          },
          where: "id = ?",
          whereArgs: [row.id],
        );
      }
    });
  }

  Future<void> setNoteFlagsRaw(
    String id, {
    bool? pinned,
    bool? archived,
    bool? deleted,
  }) async {
    final db = await database;
    final patch = <String, Object>{
      "updated_at": DateTime.now().millisecondsSinceEpoch,
    };
    if (pinned != null) patch["is_pinned"] = pinned ? 1 : 0;
    if (archived != null) patch["is_archived"] = archived ? 1 : 0;
    if (deleted != null) patch["is_deleted"] = deleted ? 1 : 0;
    await db.update("notes", patch, where: "id = ?", whereArgs: [id]);
  }

  Future<void> deleteNotePermanently(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete("note_tag_links", where: "note_id = ?", whereArgs: [id]);
      await txn.delete("note_revisions", where: "note_id = ?", whereArgs: [id]);
      await txn.delete("notes", where: "id = ?", whereArgs: [id]);
    });
  }

  Future<Map<String, dynamic>> exportNotesPayload() async {
    final db = await database;
    final notes = await db.query("notes", orderBy: "updated_at DESC");
    final tags = await db.query("note_tags", orderBy: "name ASC");
    final links = await db.query("note_tag_links");
    final revisions =
        await db.query("note_revisions", orderBy: "created_at DESC");
    return {
      "schema_version": 1,
      "exported_at": DateTime.now().toIso8601String(),
      "notes": notes,
      "note_tags": tags,
      "note_tag_links": links,
      "note_revisions": revisions,
    };
  }

  Future<void> importNotesPayload(
    Map<String, dynamic> payload, {
    required bool replace,
  }) async {
    final db = await database;
    final notes = (payload["notes"] as List<dynamic>? ?? const []).cast<Map>();
    final tags =
        (payload["note_tags"] as List<dynamic>? ?? const []).cast<Map>();
    final links =
        (payload["note_tag_links"] as List<dynamic>? ?? const []).cast<Map>();
    final revisions =
        (payload["note_revisions"] as List<dynamic>? ?? const []).cast<Map>();

    await db.transaction((txn) async {
      if (replace) {
        await txn.delete("note_tag_links");
        await txn.delete("note_revisions");
        await txn.delete("note_tags");
        await txn.delete("notes");
      }

      for (final row in notes) {
        await txn.insert(
          "notes",
          row.map((k, v) => MapEntry(k.toString(), v)),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final row in tags) {
        await txn.insert(
          "note_tags",
          row.map((k, v) => MapEntry(k.toString(), v)),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final row in links) {
        await txn.insert(
          "note_tag_links",
          row.map((k, v) => MapEntry(k.toString(), v)),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final row in revisions) {
        await txn.insert(
          "note_revisions",
          row.map((k, v) => MapEntry(k.toString(), v)),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<void> insertChatMessage({
    required String id,
    required String authorId,
    required String text,
    required int createdAt,
    bool isPinned = false,
    String messageType = "text",
    String? payload,
  }) async {
    final db = await database;
    final map = <String, dynamic>{
      "id": id,
      "author_id": authorId,
      "text": text,
      "created_at": createdAt,
      "is_pinned": isPinned ? 1 : 0,
      "message_type": messageType,
      "payload": payload,
    };
    await db.insert(
      "chat_messages",
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAllChatMessages() async {
    final db = await database;
    final rows = await db.query("chat_messages", orderBy: "created_at ASC");
    return rows.map((m) => Map<String, dynamic>.from(m)).toList();
  }

  Future<void> deleteChatMessage(String id) async {
    final db = await database;
    await db.delete("chat_messages", where: "id = ?", whereArgs: [id]);
  }

  Future<void> updateChatMessage(String id, String text) async {
    final db = await database;
    await db.update(
      "chat_messages",
      {"text": text},
      where: "id = ?",
      whereArgs: [id],
    );
  }

  Future<void> setChatMessagePinned(String? messageId) async {
    final db = await database;
    await db.update("chat_messages", {"is_pinned": 0});
    if (messageId != null && messageId.isNotEmpty) {
      await db.update(
        "chat_messages",
        {"is_pinned": 1},
        where: "id = ?",
        whereArgs: [messageId],
      );
    }
  }

  Future<Map<String, dynamic>?> getPinnedChatMessage() async {
    final db = await database;
    final rows = await db.query(
      "chat_messages",
      where: "is_pinned = 1",
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  DateTime? _parseDate(String? date) {
    if (date == null || date.isEmpty) return null;
    try {
      final parts = date.split(".");
      if (parts.length != 3) return null;
      return DateTime(
        int.parse(parts[2]),
        int.parse(parts[1]),
        int.parse(parts[0]),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _maybeCleanup() async {
    final now = DateTime.now();
    if (_lastCleanup != null &&
        now.difference(_lastCleanup!) < _cleanupInterval) {
      return;
    }
    _lastCleanup = now;
    final retention = await _retentionDays();
    await deleteOldSnapshots(retention);

    final db = await database;
    final cutoff =
        now.subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    await db.delete("sync_log", where: "synced_at < ?", whereArgs: [cutoff]);
  }

  Future<int> _retentionDays() async {
    final saved = await getDatabaseSetting("retention_days");
    final parsed = int.tryParse(saved ?? "");
    return (parsed ?? 90).clamp(14, 365);
  }
}
