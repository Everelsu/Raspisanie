import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'database_helper.dart';
import 'message.dart';

class MessageRepository {
  MessageRepository._();
  static final MessageRepository instance = MessageRepository._();
  static const _uuid = Uuid();

  Future<Database> get _db => DatabaseHelper.instance.database;

  static String generateId() => _uuid.v4();

  Future<List<Message>> getMessages(String chatId, {int limit = 50, int offset = 0}) async {
    final db = await _db;
    final maps = await db.rawQuery('''
      SELECT m.*,
             rm.content AS reply_content,
             rm.type AS reply_type,
             rm.created_at AS reply_created_at
      FROM messages m
      LEFT JOIN messages rm ON m.reply_to_id = rm.id AND rm.is_deleted = 0
      WHERE m.chat_id = ? AND m.is_deleted = 0
      ORDER BY m.created_at DESC
      LIMIT ? OFFSET ?
    ''', [chatId, limit, offset]);

    final result = <Message>[];
    for (final m in maps) {
      final replyToId = m['reply_to_id'] as String?;
      Message? replyToMessage;
      if (replyToId != null && m['reply_content'] != null) {
        replyToMessage = Message(
          id: replyToId,
          chatId: chatId,
          type: MessageType.values.byName(m['reply_type'] as String),
          content: m['reply_content'] as String?,
          status: MessageStatus.sent,
          createdAt: DateTime.fromMillisecondsSinceEpoch(m['reply_created_at'] as int),
        );
      }
      final media = await _getMediaForMessage(m['id'] as String);
      result.add(Message.fromMap(Map<String, dynamic>.from(m as Map), replyToMessage: replyToMessage, mediaFiles: media));
    }
    return result;
  }

  Future<List<MediaFile>> _getMediaForMessage(String messageId) async {
    final db = await _db;
    final maps = await db.query('media', where: 'message_id = ?', whereArgs: [messageId]);
    return maps.map((e) => MediaFile.fromMap(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> insertMessage(Message message, {List<MediaFile>? media}) async {
    final db = await _db;
    await db.insert('messages', message.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    if (media != null && media.isNotEmpty) {
      for (final f in media) {
        await db.insert('media', f.toMap(message.chatId, message.id));
      }
    }
    await db.update(
      'chats',
      {'last_message_id': message.id, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [message.chatId],
    );
  }

  Future<void> editMessage(String messageId, String newContent) async {
    final db = await _db;
    await db.update(
      'messages',
      {
        'content': newContent,
        'is_edited': 1,
        'edited_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> deleteMessage(String messageId) async {
    final db = await _db;
    await db.update(
      'messages',
      {'is_deleted': 1},
      where: 'id = ?',
      whereArgs: [messageId],
    );
    final media = await db.query('media', where: 'message_id = ?', whereArgs: [messageId]);
    for (final row in media) {
      final path = row['local_path'] as String?;
      if (path != null && path.isNotEmpty) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
    await db.delete('media', where: 'message_id = ?', whereArgs: [messageId]);
  }

  /// Один закреп (для обратной совместимости).
  Future<Message?> getPinnedMessage(String chatId) async {
    final list = await getPinnedMessages(chatId);
    return list.isEmpty ? null : list.first;
  }

  /// Все закреплённые сообщения (новые сверху).
  Future<List<Message>> getPinnedMessages(String chatId) async {
    final db = await _db;
    final pinned = await db.query('pinned_messages', where: 'chat_id = ?', whereArgs: [chatId], orderBy: 'pinned_at DESC');
    final result = <Message>[];
    for (final row in pinned) {
      final msgId = row['message_id'] as String;
      final msgMaps = await db.query('messages', where: 'id = ? AND is_deleted = 0', whereArgs: [msgId]);
      if (msgMaps.isEmpty) continue;
      final media = await _getMediaForMessage(msgId);
      result.add(Message.fromMap(Map<String, dynamic>.from(msgMaps.first), mediaFiles: media));
    }
    return result;
  }

  Future<void> pinMessage(String chatId, String messageId) async {
    final db = await _db;
    await db.insert('pinned_messages', {
      'id': generateId(),
      'chat_id': chatId,
      'message_id': messageId,
      'pinned_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Если [messageId] задан — снять закреп с одного сообщения, иначе со всех в чате.
  Future<void> unpinMessage(String chatId, {String? messageId}) async {
    final db = await _db;
    if (messageId != null) {
      await db.delete('pinned_messages', where: 'chat_id = ? AND message_id = ?', whereArgs: [chatId, messageId]);
    } else {
      await db.delete('pinned_messages', where: 'chat_id = ?', whereArgs: [chatId]);
    }
  }

  Future<String?> savePickedImage(XFile xFile) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final notesDir = Directory(p.join(dir.path, 'notes_media'));
      if (!await notesDir.exists()) await notesDir.create(recursive: true);
      final name = '${DateTime.now().millisecondsSinceEpoch}${p.extension(xFile.name).isEmpty ? '.jpg' : p.extension(xFile.name)}';
      final file = File(p.join(notesDir.path, name));
      await file.writeAsBytes(await xFile.readAsBytes());
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// Returns a path in notes_media for a new voice recording (call before starting record).
  Future<String> getVoiceRecordingPath() async {
    final dir = await getApplicationDocumentsDirectory();
    final notesDir = Directory(p.join(dir.path, 'notes_media'));
    if (!await notesDir.exists()) await notesDir.create(recursive: true);
    return p.join(notesDir.path, 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
  }

  Future<void> deleteAllMessages(String chatId) async {
    final db = await _db;
    final messages = await db.query('messages', where: 'chat_id = ?', whereArgs: [chatId]);
    for (final m in messages) {
      final mid = m['id'] as String;
      final media = await db.query('media', where: 'message_id = ?', whereArgs: [mid]);
      for (final row in media) {
        final path = row['local_path'] as String?;
        if (path != null && path.isNotEmpty) {
          try {
            final file = File(path);
            if (await file.exists()) await file.delete();
          } catch (_) {}
        }
      }
    }
    await db.delete('media', where: 'chat_id = ?', whereArgs: [chatId]);
    await db.delete('messages', where: 'chat_id = ?', whereArgs: [chatId]);
    await db.delete('pinned_messages', where: 'chat_id = ?', whereArgs: [chatId]);
    await db.update('chats', {'last_message_id': null, 'updated_at': DateTime.now().millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [chatId]);
  }
}
