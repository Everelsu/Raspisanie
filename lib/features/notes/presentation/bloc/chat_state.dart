part of 'chat_bloc.dart';

abstract class ChatState extends Equatable {
  const ChatState();
  @override
  List<Object?> get props => [];
}

class ChatInitial extends ChatState {}

class ChatLoading extends ChatState {}

class ChatLoaded extends ChatState {
  const ChatLoaded({
    required this.chatId,
    required this.messages,
    this.hasMore = false,
    this.pinnedMessages = const [],
    this.isLoadingMore = false,
  });

  final String chatId;
  final List<Message> messages;
  final bool hasMore;
  final List<Message> pinnedMessages;
  final bool isLoadingMore;

  /// Первый закреп (для обратной совместимости).
  Message? get pinnedMessage => pinnedMessages.isEmpty ? null : pinnedMessages.first;

  @override
  List<Object?> get props => [chatId, messages, hasMore, pinnedMessages, isLoadingMore];

  ChatLoaded copyWith({
    String? chatId,
    List<Message>? messages,
    bool? hasMore,
    List<Message>? pinnedMessages,
    bool clearPinned = false,
    bool? isLoadingMore,
  }) {
    return ChatLoaded(
      chatId: chatId ?? this.chatId,
      messages: messages ?? this.messages,
      hasMore: hasMore ?? this.hasMore,
      pinnedMessages: clearPinned ? const [] : (pinnedMessages ?? this.pinnedMessages),
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

class ChatError extends ChatState {
  const ChatError(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}
