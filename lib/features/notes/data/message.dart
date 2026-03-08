import 'package:equatable/equatable.dart';

enum MessageType { text, image, video, file, audio, voice, sticker }

enum MessageStatus { sending, sent, delivered, read }

class MediaFile extends Equatable {
  const MediaFile({
    required this.id,
    required this.messageId,
    required this.type,
    required this.localPath,
    this.fileName,
    this.width,
    this.height,
    required this.createdAt,
  });

  final String id;
  final String messageId;
  final String type;
  final String localPath;
  final String? fileName;
  final int? width;
  final int? height;
  final DateTime createdAt;

  @override
  List<Object?> get props => [id, messageId, localPath];

  factory MediaFile.fromMap(Map<String, dynamic> map) {
    return MediaFile(
      id: map['id'] as String,
      messageId: map['message_id'] as String,
      type: map['type'] as String,
      localPath: map['local_path'] as String,
      fileName: map['file_name'] as String?,
      width: map['width'] as int?,
      height: map['height'] as int?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  Map<String, dynamic> toMap(String chatId, [String? overrideMessageId]) => {
        'id': id,
        'message_id': overrideMessageId ?? messageId,
        'chat_id': chatId,
        'type': type,
        'local_path': localPath,
        'file_name': fileName,
        'width': width,
        'height': height,
        'created_at': createdAt.millisecondsSinceEpoch,
      };
}

class Message extends Equatable {
  const Message({
    required this.id,
    required this.chatId,
    this.senderId,
    required this.type,
    this.content,
    this.replyToId,
    this.replyToMessage,
    this.isForwarded = false,
    required this.status,
    this.isEdited = false,
    this.editedAt,
    this.isDeleted = false,
    required this.createdAt,
    this.mediaFiles = const [],
  });

  final String id;
  final String chatId;
  final String? senderId;
  final MessageType type;
  final String? content;
  final String? replyToId;
  final Message? replyToMessage;
  final bool isForwarded;
  final MessageStatus status;
  final bool isEdited;
  final DateTime? editedAt;
  final bool isDeleted;
  final DateTime createdAt;
  final List<MediaFile> mediaFiles;

  @override
  List<Object?> get props => [id, chatId, createdAt];

  bool get isOutgoing => true;

  factory Message.fromMap(Map<String, dynamic> map, {Message? replyToMessage, List<MediaFile>? mediaFiles}) {
    return Message(
      id: map['id'] as String,
      chatId: map['chat_id'] as String,
      senderId: map['sender_id'] as String?,
      type: MessageType.values.byName(map['type'] as String),
      content: map['content'] as String?,
      replyToId: map['reply_to_id'] as String?,
      replyToMessage: replyToMessage,
      isForwarded: (map['is_forwarded'] as int?) == 1,
      status: MessageStatus.values.byName((map['status'] as String?) ?? 'sent'),
      isEdited: (map['is_edited'] as int?) == 1,
      editedAt: map['edited_at'] != null ? DateTime.fromMillisecondsSinceEpoch(map['edited_at'] as int) : null,
      isDeleted: (map['is_deleted'] as int?) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      mediaFiles: mediaFiles ?? [],
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'chat_id': chatId,
        'sender_id': senderId,
        'type': type.name,
        'content': content,
        'reply_to_id': replyToId,
        'is_forwarded': isForwarded ? 1 : 0,
        'status': status.name,
        'is_edited': isEdited ? 1 : 0,
        'edited_at': editedAt?.millisecondsSinceEpoch,
        'is_deleted': isDeleted ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  Message copyWith({
    String? id,
    String? chatId,
    String? senderId,
    MessageType? type,
    String? content,
    String? replyToId,
    Message? replyToMessage,
    bool? isForwarded,
    MessageStatus? status,
    bool? isEdited,
    DateTime? editedAt,
    bool? isDeleted,
    DateTime? createdAt,
    List<MediaFile>? mediaFiles,
  }) {
    return Message(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      type: type ?? this.type,
      content: content ?? this.content,
      replyToId: replyToId ?? this.replyToId,
      replyToMessage: replyToMessage ?? this.replyToMessage,
      isForwarded: isForwarded ?? this.isForwarded,
      status: status ?? this.status,
      isEdited: isEdited ?? this.isEdited,
      editedAt: editedAt ?? this.editedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt ?? this.createdAt,
      mediaFiles: mediaFiles ?? this.mediaFiles,
    );
  }
}
