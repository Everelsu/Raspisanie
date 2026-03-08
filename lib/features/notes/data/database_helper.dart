import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// SQLite helper for Telegram-like chat (notes as single chat).
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    _database ??= await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final path = join(await getDatabasesPath(), 'notes_chat.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE chats (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        title TEXT,
        last_message_id TEXT,
        unread_count INTEGER DEFAULT 0,
        is_pinned INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        chat_id TEXT NOT NULL,
        sender_id TEXT,
        type TEXT NOT NULL,
        content TEXT,
        reply_to_id TEXT,
        is_forwarded INTEGER DEFAULT 0,
        status TEXT DEFAULT 'sent',
        is_edited INTEGER DEFAULT 0,
        edited_at INTEGER,
        is_deleted INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (chat_id) REFERENCES chats(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE media (
        id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        chat_id TEXT NOT NULL,
        type TEXT NOT NULL,
        local_path TEXT,
        file_name TEXT,
        width INTEGER,
        height INTEGER,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (message_id) REFERENCES messages(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE pinned_messages (
        id TEXT PRIMARY KEY,
        chat_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        pinned_at INTEGER NOT NULL,
        FOREIGN KEY (chat_id) REFERENCES chats(id),
        FOREIGN KEY (message_id) REFERENCES messages(id)
      )
    ''');

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('chats', {
      'id': kNotesChatId,
      'type': 'saved',
      'title': 'Заметки',
      'created_at': now,
      'updated_at': now,
    });
  }

  static const String kNotesChatId = 'notes';
}
