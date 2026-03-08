import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../data/message.dart';
import '../../data/message_repository.dart';

part 'chat_event.dart';
part 'chat_state.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc(this._repo) : super(ChatInitial()) {
    on<ChatLoadMessages>(_onLoadMessages);
    on<ChatSendMessage>(_onSendMessage);
    on<ChatEditMessage>(_onEditMessage);
    on<ChatDeleteMessage>(_onDeleteMessage);
    on<ChatLoadMoreMessages>(_onLoadMore);
    on<ChatPinMessage>(_onPinMessage);
    on<ChatUnpinMessage>(_onUnpinMessage);
    on<ChatClearAll>(_onClearAll);
  }

  final MessageRepository _repo;
  int _offset = 0;
  static const int _pageSize = 50;

  Future<void> _onLoadMessages(ChatLoadMessages event, Emitter<ChatState> emit) async {
    emit(ChatLoading());
    try {
      _offset = 0;
      final messages = await _repo.getMessages(event.chatId, limit: _pageSize, offset: 0);
      _offset = messages.length;
      final pinned = await _repo.getPinnedMessages(event.chatId);
      emit(ChatLoaded(
        chatId: event.chatId,
        messages: messages,
        hasMore: messages.length == _pageSize,
        pinnedMessages: pinned,
        isLoadingMore: false,
      ));
    } catch (e) {
      emit(ChatError(e.toString()));
    }
  }

  Future<void> _onSendMessage(ChatSendMessage event, Emitter<ChatState> emit) async {
    if (state is! ChatLoaded) return;
    final current = state as ChatLoaded;
    final message = Message(
      id: event.messageId ?? MessageRepository.generateId(),
      chatId: event.chatId,
      type: event.type,
      content: event.content,
      replyToId: event.replyToId,
      status: MessageStatus.sent,
      createdAt: DateTime.now(),
      mediaFiles: event.mediaFiles ?? [],
    );
    await _repo.insertMessage(message, media: event.mediaFiles);
    final updated = await _repo.getMessages(event.chatId, limit: _pageSize, offset: 0);
    emit(current.copyWith(messages: updated, pinnedMessages: await _repo.getPinnedMessages(event.chatId)));
  }

  Future<void> _onEditMessage(ChatEditMessage event, Emitter<ChatState> emit) async {
    await _repo.editMessage(event.messageId, event.newContent);
    if (state is! ChatLoaded) return;
    final current = state as ChatLoaded;
    final updated = await _repo.getMessages(current.chatId, limit: current.messages.length + _pageSize, offset: 0);
    emit(current.copyWith(messages: updated));
  }

  Future<void> _onDeleteMessage(ChatDeleteMessage event, Emitter<ChatState> emit) async {
    await _repo.deleteMessage(event.messageId);
    if (state is! ChatLoaded) return;
    final current = state as ChatLoaded;
    final updated = current.messages.where((m) => m.id != event.messageId).toList();
    final stillPinned = current.pinnedMessages.where((m) => m.id != event.messageId).toList();
    if (stillPinned.length != current.pinnedMessages.length) {
      await _repo.unpinMessage(current.chatId, messageId: event.messageId);
      emit(current.copyWith(messages: updated, pinnedMessages: stillPinned));
    } else {
      emit(current.copyWith(messages: updated));
    }
  }

  Future<void> _onLoadMore(ChatLoadMoreMessages event, Emitter<ChatState> emit) async {
    if (state is! ChatLoaded) return;
    final current = state as ChatLoaded;
    if (current.isLoadingMore || !current.hasMore) return;
    emit(current.copyWith(isLoadingMore: true));
    final more = await _repo.getMessages(event.chatId, limit: _pageSize, offset: _offset);
    _offset += more.length;
    emit(current.copyWith(
      messages: [...current.messages, ...more],
      hasMore: more.length == _pageSize,
      isLoadingMore: false,
    ));
  }

  Future<void> _onPinMessage(ChatPinMessage event, Emitter<ChatState> emit) async {
    if (event.messageId.isEmpty) return;
    await _repo.pinMessage(event.chatId, event.messageId);
    if (state is! ChatLoaded) return;
    final current = state as ChatLoaded;
    final pinned = await _repo.getPinnedMessages(event.chatId);
    emit(current.copyWith(pinnedMessages: pinned));
  }

  Future<void> _onUnpinMessage(ChatUnpinMessage event, Emitter<ChatState> emit) async {
    await _repo.unpinMessage(event.chatId, messageId: event.messageId);
    if (state is! ChatLoaded) return;
    final current = state as ChatLoaded;
    final pinned = await _repo.getPinnedMessages(event.chatId);
    emit(current.copyWith(pinnedMessages: pinned));
  }

  Future<void> _onClearAll(ChatClearAll event, Emitter<ChatState> emit) async {
    await _repo.deleteAllMessages(event.chatId);
    if (state is! ChatLoaded) return;
    final current = state as ChatLoaded;
    emit(current.copyWith(messages: [], pinnedMessages: const []));
  }
}
