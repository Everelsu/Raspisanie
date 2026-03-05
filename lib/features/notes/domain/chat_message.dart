import "package:equatable/equatable.dart";

/// UI domain model for a chat message (notes as chat).
class ChatMessage extends Equatable {
  const ChatMessage({
    required this.id,
    required this.type,
    required this.text,
    this.payload,
    required this.createdAt,
    this.status = MessageStatus.saved,
    this.replyToId,
    this.replyPreview,
    this.isPinned = false,
    this.isFavorite = false,
    this.pinnedOrder,
  });

  final String id;
  final String type;
  final String text;
  final String? payload;
  final DateTime createdAt;
  final MessageStatus status;
  final String? replyToId;
  final String? replyPreview;
  final bool isPinned;
  final bool isFavorite;
  final int? pinnedOrder;

  @override
  List<Object?> get props => [id, type, text, payload, createdAt, status, replyToId, replyPreview, isPinned, isFavorite, pinnedOrder];

  ChatMessage copyWith({
    String? id,
    String? type,
    String? text,
    String? payload,
    DateTime? createdAt,
    MessageStatus? status,
    String? replyToId,
    String? replyPreview,
    bool? isPinned,
    bool? isFavorite,
    int? pinnedOrder,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      type: type ?? this.type,
      text: text ?? this.text,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      replyToId: replyToId ?? this.replyToId,
      replyPreview: replyPreview ?? this.replyPreview,
      isPinned: isPinned ?? this.isPinned,
      isFavorite: isFavorite ?? this.isFavorite,
      pinnedOrder: pinnedOrder ?? this.pinnedOrder,
    );
  }
}

enum MessageStatus { sent, saved, error }
