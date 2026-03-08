part of 'chat_bloc.dart';

abstract class ChatEvent extends Equatable {
  const ChatEvent();
  @override
  List<Object?> get props => [];
}

class ChatLoadMessages extends ChatEvent {
  const ChatLoadMessages({required this.chatId});
  final String chatId;
  @override
  List<Object?> get props => [chatId];
}

class ChatSendMessage extends ChatEvent {
  const ChatSendMessage({
    required this.chatId,
    this.content,
    required this.type,
    this.replyToId,
    this.mediaFiles,
    this.messageId,
  });
  final String chatId;
  final String? content;
  final MessageType type;
  final String? replyToId;
  final List<MediaFile>? mediaFiles;
  /// If set, used as message id (e.g. for optimistic UI with flyer).
  final String? messageId;
  @override
  List<Object?> get props => [chatId, content, type, replyToId, messageId];
}

class ChatEditMessage extends ChatEvent {
  const ChatEditMessage({required this.messageId, required this.newContent});
  final String messageId;
  final String newContent;
  @override
  List<Object?> get props => [messageId, newContent];
}

class ChatDeleteMessage extends ChatEvent {
  const ChatDeleteMessage({required this.messageId});
  final String messageId;
  @override
  List<Object?> get props => [messageId];
}

class ChatLoadMoreMessages extends ChatEvent {
  const ChatLoadMoreMessages({required this.chatId});
  final String chatId;
  @override
  List<Object?> get props => [chatId];
}

class ChatPinMessage extends ChatEvent {
  const ChatPinMessage({required this.chatId, required this.messageId});
  final String chatId;
  final String messageId;
  @override
  List<Object?> get props => [chatId, messageId];
}

class ChatUnpinMessage extends ChatEvent {
  const ChatUnpinMessage({required this.chatId, this.messageId});
  final String chatId;
  /// Если задан — снять закреп только с этого сообщения.
  final String? messageId;
  @override
  List<Object?> get props => [chatId, messageId];
}

class ChatClearAll extends ChatEvent {
  const ChatClearAll({required this.chatId});
  final String chatId;
  @override
  List<Object?> get props => [chatId];
}
