import "package:isar/isar.dart";

import "../../../core/database/schedule_database.dart";
import "../domain/chat_message.dart";
import "chat_isar_provider.dart";
import "chat_message_entity.dart";

/// Notes (chat) repository: Isar for messages, pinned, favorites; migrates from ScheduleDatabase.
class ChatRepository {
  ChatRepository();

  Future<Isar> get _isar async => ChatIsarProvider.instance;

  Future<List<ChatMessage>> getMessages() async {
    final isar = await _isar;
    final refs = await isar.pinnedRefEntitys.where().sortByOrder().findAll();
    final pinnedIds = refs.map((r) => r.messageId).toList();
    final favRefs = await isar.favoriteRefEntitys.where().findAll();
    final favoriteIds = favRefs.map((r) => r.messageId).toSet();
    final list = await isar.chatMessageEntitys.where().sortByCreatedAtDesc().findAll();
    final orderMap = <String, int>{};
    for (var i = 0; i < pinnedIds.length; i++) {
      orderMap[pinnedIds[i]] = i;
    }
    return list.map((e) => _entityToMessage(e, orderMap[e.messageId], favoriteIds.contains(e.messageId))).toList();
  }

  Future<List<ChatMessage>> getPinnedMessages() async {
    final isar = await _isar;
    final refs = await isar.pinnedRefEntitys.where().sortByOrder().findAll();
    if (refs.isEmpty) return [];
    final all = await isar.chatMessageEntitys.where().findAll();
    final byId = {for (var e in all) e.messageId: e};
    final favRefs = await isar.favoriteRefEntitys.where().findAll();
    final favoriteIds = favRefs.map((r) => r.messageId).toSet();
    return refs
        .map((r) => byId[r.messageId])
        .whereType<ChatMessageEntity>()
        .map((e) => _entityToMessage(e, refs.firstWhere((r) => r.messageId == e.messageId).order, favoriteIds.contains(e.messageId)))
        .toList();
  }

  Future<List<ChatMessage>> getFavoriteMessages() async {
    final isar = await _isar;
    final refs = await isar.favoriteRefEntitys.where().sortByAddedAtDesc().findAll();
    if (refs.isEmpty) return [];
    final all = await isar.chatMessageEntitys.where().findAll();
    final byId = {for (var e in all) e.messageId: e};
    final pinnedRefs = await isar.pinnedRefEntitys.where().findAll();
    final pinnedOrders = {for (var r in pinnedRefs) r.messageId: r.order};
    return refs
        .map((r) => byId[r.messageId])
        .whereType<ChatMessageEntity>()
        .map((e) => _entityToMessage(e, pinnedOrders[e.messageId], true))
        .toList();
  }

  Future<List<ChatMessage>> searchMessages(String query) async {
    if (query.trim().isEmpty) return getMessages();
    final isar = await _isar;
    final q = query.trim().toLowerCase();
    final list = await isar.chatMessageEntitys.where().sortByCreatedAtDesc().findAll();
    final filtered = list.where((e) => e.text.toLowerCase().contains(q)).toList();
    final refs = await isar.pinnedRefEntitys.where().sortByOrder().findAll();
    final orderMap = {for (var i = 0; i < refs.length; i++) refs[i].messageId: i};
    final favRefs = await isar.favoriteRefEntitys.where().findAll();
    final favoriteIds = favRefs.map((r) => r.messageId).toSet();
    return filtered.map((e) => _entityToMessage(e, orderMap[e.messageId], favoriteIds.contains(e.messageId))).toList();
  }

  ChatMessage _entityToMessage(ChatMessageEntity e, int? pinnedOrder, bool isFavorite) {
    return ChatMessage(
      id: e.messageId,
      type: e.type,
      text: e.text,
      payload: e.payload,
      createdAt: e.createdAt,
      status: _parseStatus(e.status),
      replyToId: e.replyToId,
      replyPreview: e.replyPreview,
      isPinned: pinnedOrder != null,
      isFavorite: isFavorite,
      pinnedOrder: pinnedOrder,
    );
  }

  MessageStatus _parseStatus(String s) {
    switch (s) {
      case "sent":
        return MessageStatus.sent;
      case "error":
        return MessageStatus.error;
      default:
        return MessageStatus.saved;
    }
  }

  static String _statusString(MessageStatus s) {
    switch (s) {
      case MessageStatus.sent:
        return "sent";
      case MessageStatus.error:
        return "error";
      default:
        return "saved";
    }
  }

  Future<void> addMessage(ChatMessage message) async {
    final isar = await _isar;
    final e = ChatMessageEntity.fromData(
      messageId: message.id,
      type: message.type,
      text: message.text,
      payload: message.payload,
      createdAt: message.createdAt,
      status: _statusString(message.status),
      replyToId: message.replyToId,
      replyPreview: message.replyPreview,
    );
    await isar.writeTxn(() async {
      await isar.chatMessageEntitys.put(e);
    });
  }

  Future<void> updateMessage(ChatMessage message) async {
    final isar = await _isar;
    final existing = await isar.chatMessageEntitys.where().filter().messageIdEqualTo(message.id).findFirst();
    if (existing == null) return;
    existing.text = message.text;
    existing.status = _statusString(message.status);
    await isar.writeTxn(() async {
      await isar.chatMessageEntitys.put(existing);
    });
  }

  Future<void> deleteMessage(String messageId) async {
    final isar = await _isar;
    await isar.writeTxn(() async {
      await isar.pinnedRefEntitys.where().filter().messageIdEqualTo(messageId).deleteAll();
      await isar.favoriteRefEntitys.where().filter().messageIdEqualTo(messageId).deleteAll();
      await isar.chatMessageEntitys.where().filter().messageIdEqualTo(messageId).deleteAll();
    });
  }

  Future<void> togglePin(String messageId) async {
    final isar = await _isar;
    final existing = await isar.pinnedRefEntitys.where().filter().messageIdEqualTo(messageId).findFirst();
    await isar.writeTxn(() async {
      if (existing != null) {
        await isar.pinnedRefEntitys.delete(existing.id);
      } else {
        final count = await isar.pinnedRefEntitys.count();
        final ref = PinnedRefEntity()
          ..messageId = messageId
          ..order = count;
        await isar.pinnedRefEntitys.put(ref);
      }
    });
  }

  Future<void> toggleFavorite(String messageId) async {
    final isar = await _isar;
    final existing = await isar.favoriteRefEntitys.where().filter().messageIdEqualTo(messageId).findFirst();
    await isar.writeTxn(() async {
      if (existing != null) {
        await isar.favoriteRefEntitys.delete(existing.id);
      } else {
        final ref = FavoriteRefEntity()
          ..messageId = messageId
          ..addedAt = DateTime.now().toUtc();
        await isar.favoriteRefEntitys.put(ref);
      }
    });
  }

  Future<void> migrateFromScheduleDatabaseIfNeeded() async {
    final isar = await _isar;
    final count = await isar.chatMessageEntitys.count();
    if (count > 0) return;
    final db = ScheduleDatabase.instance;
    final rows = await db.getAllChatMessages();
    if (rows.isEmpty) return;
    await isar.writeTxn(() async {
      for (final r in rows) {
        final e = ChatMessageEntity.fromData(
          messageId: r["id"] as String,
          type: r["message_type"] as String? ?? "text",
          text: r["text"] as String? ?? "",
          payload: r["payload"] as String?,
          createdAt: DateTime.fromMillisecondsSinceEpoch(r["created_at"] as int).toUtc(),
          status: "saved",
        );
        await isar.chatMessageEntitys.put(e);
      }
      final pinnedId = await db.getPinnedChatMessage();
      if (pinnedId != null && pinnedId["id"] != null) {
        final ref = PinnedRefEntity()
          ..messageId = pinnedId["id"] as String
          ..order = 0;
        await isar.pinnedRefEntitys.put(ref);
      }
    });
  }
}
