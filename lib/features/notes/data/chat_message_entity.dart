import "package:isar/isar.dart";

part "chat_message_entity.g.dart";

@collection
class ChatMessageEntity {
  Id id = Isar.autoIncrement;

  late String messageId;
  late String type;
  late String text;
  String? payload;
  late DateTime createdAt;
  late String status;
  String? replyToId;
  String? replyPreview;
  String? linkPreviewJson;

  ChatMessageEntity();

  factory ChatMessageEntity.fromData({
    required String messageId,
    required String type,
    required String text,
    String? payload,
    required DateTime createdAt,
    String status = "saved",
    String? replyToId,
    String? replyPreview,
    String? linkPreviewJson,
  }) {
    final e = ChatMessageEntity();
    e.messageId = messageId;
    e.type = type;
    e.text = text;
    e.payload = payload;
    e.createdAt = createdAt;
    e.status = status;
    e.replyToId = replyToId;
    e.replyPreview = replyPreview;
    e.linkPreviewJson = linkPreviewJson;
    return e;
  }
}

@collection
class PinnedRefEntity {
  Id id = Isar.autoIncrement;
  late String messageId;
  late int order;

  PinnedRefEntity();
}

@collection
class FavoriteRefEntity {
  Id id = Isar.autoIncrement;
  late String messageId;
  late DateTime addedAt;

  FavoriteRefEntity();
}
