import "package:flutter_bloc/flutter_bloc.dart";
import "package:equatable/equatable.dart";

import "../../data/chat_repository.dart";
import "../../domain/chat_message.dart";

// Events
abstract class ChatEvent extends Equatable {
  const ChatEvent();
  @override
  List<Object?> get props => [];
}

class ChatLoadRequested extends ChatEvent {
  const ChatLoadRequested();
}

class ChatSendTextRequested extends ChatEvent {
  const ChatSendTextRequested(this.text);
  final String text;
  @override
  List<Object?> get props => [text];
}

class ChatSendVoiceRequested extends ChatEvent {
  const ChatSendVoiceRequested({required this.filePath, required this.durationSec});
  final String filePath;
  final int durationSec;
  @override
  List<Object?> get props => [filePath, durationSec];
}

class ChatSendImageRequested extends ChatEvent {
  const ChatSendImageRequested({required this.filePath, this.caption});
  final String filePath;
  final String? caption;
  @override
  List<Object?> get props => [filePath, caption];
}

class ChatPinToggled extends ChatEvent {
  const ChatPinToggled(this.messageId);
  final String messageId;
  @override
  List<Object?> get props => [messageId];
}

class ChatFavoriteToggled extends ChatEvent {
  const ChatFavoriteToggled(this.messageId);
  final String messageId;
  @override
  List<Object?> get props => [messageId];
}

class ChatMessageDeleted extends ChatEvent {
  const ChatMessageDeleted(this.messageId);
  final String messageId;
  @override
  List<Object?> get props => [messageId];
}

class ChatMessageUpdated extends ChatEvent {
  const ChatMessageUpdated(this.messageId, this.newText);
  final String messageId;
  final String newText;
  @override
  List<Object?> get props => [messageId, newText];
}

class ChatSearchChanged extends ChatEvent {
  const ChatSearchChanged(this.query);
  final String query;
  @override
  List<Object?> get props => [query];
}

// State
class ChatState extends Equatable {
  const ChatState({
    this.messages = const [],
    this.pinned = const [],
    this.searchQuery = "",
    this.searchResults = const [],
    this.status = ChatStatus.initial,
    this.error,
  });

  final List<ChatMessage> messages;
  final List<ChatMessage> pinned;
  final String searchQuery;
  final List<ChatMessage> searchResults;
  final ChatStatus status;
  final String? error;

  List<ChatMessage> get displayMessages => searchQuery.trim().isEmpty ? messages : searchResults;

  @override
  List<Object?> get props => [messages, pinned, searchQuery, searchResults, status, error];

  ChatState copyWith({
    List<ChatMessage>? messages,
    List<ChatMessage>? pinned,
    String? searchQuery,
    List<ChatMessage>? searchResults,
    ChatStatus? status,
    String? error,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      pinned: pinned ?? this.pinned,
      searchQuery: searchQuery ?? this.searchQuery,
      searchResults: searchResults ?? this.searchResults,
      status: status ?? this.status,
      error: error,
    );
  }
}

enum ChatStatus { initial, loading, loaded, error }

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc(this._repository) : super(const ChatState()) {
    on<ChatLoadRequested>(_onLoad);
    on<ChatSendTextRequested>(_onSendText);
    on<ChatSendVoiceRequested>(_onSendVoice);
    on<ChatSendImageRequested>(_onSendImage);
    on<ChatPinToggled>(_onPinToggled);
    on<ChatFavoriteToggled>(_onFavoriteToggled);
    on<ChatMessageDeleted>(_onMessageDeleted);
    on<ChatMessageUpdated>(_onMessageUpdated);
    on<ChatSearchChanged>(_onSearchChanged);
  }

  final ChatRepository _repository;

  Future<void> _onLoad(ChatLoadRequested event, Emitter<ChatState> emit) async {
    emit(state.copyWith(status: ChatStatus.loading, error: null));
    try {
      await _repository.migrateFromScheduleDatabaseIfNeeded();
      final messages = await _repository.getMessages();
      final pinned = await _repository.getPinnedMessages();
      emit(state.copyWith(
        messages: messages,
        pinned: pinned,
        status: ChatStatus.loaded,
        error: null,
      ));
    } catch (e) {
      emit(state.copyWith(status: ChatStatus.error, error: e.toString()));
    }
  }

  Future<void> _onSendText(ChatSendTextRequested event, Emitter<ChatState> emit) async {
    final text = event.text.trim();
    if (text.isEmpty) return;
    final id = "${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}";
    final msg = ChatMessage(
      id: id,
      type: "text",
      text: text,
      createdAt: DateTime.now().toUtc(),
      status: MessageStatus.saved,
    );
    await _repository.addMessage(msg);
    add(const ChatLoadRequested());
  }

  Future<void> _onSendVoice(ChatSendVoiceRequested event, Emitter<ChatState> emit) async {
    final id = "${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}";
    final msg = ChatMessage(
      id: id,
      type: "voice",
      text: event.durationSec.toString(),
      payload: event.filePath,
      createdAt: DateTime.now().toUtc(),
      status: MessageStatus.saved,
    );
    await _repository.addMessage(msg);
    add(const ChatLoadRequested());
  }

  Future<void> _onSendImage(ChatSendImageRequested event, Emitter<ChatState> emit) async {
    final id = "${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}";
    final msg = ChatMessage(
      id: id,
      type: "image",
      text: event.caption ?? "",
      payload: event.filePath,
      createdAt: DateTime.now().toUtc(),
      status: MessageStatus.saved,
    );
    await _repository.addMessage(msg);
    add(const ChatLoadRequested());
  }

  Future<void> _onPinToggled(ChatPinToggled event, Emitter<ChatState> emit) async {
    await _repository.togglePin(event.messageId);
    add(const ChatLoadRequested());
  }

  Future<void> _onFavoriteToggled(ChatFavoriteToggled event, Emitter<ChatState> emit) async {
    await _repository.toggleFavorite(event.messageId);
    add(const ChatLoadRequested());
  }

  Future<void> _onMessageDeleted(ChatMessageDeleted event, Emitter<ChatState> emit) async {
    await _repository.deleteMessage(event.messageId);
    add(const ChatLoadRequested());
  }

  Future<void> _onMessageUpdated(ChatMessageUpdated event, Emitter<ChatState> emit) async {
    ChatMessage? m;
    for (final x in state.messages) {
      if (x.id == event.messageId) {
        m = x;
        break;
      }
    }
    if (m == null) return;
    final updated = m.copyWith(text: event.newText);
    await _repository.updateMessage(updated);
    add(const ChatLoadRequested());
  }

  Future<void> _onSearchChanged(ChatSearchChanged event, Emitter<ChatState> emit) async {
    if (event.query.trim().isEmpty) {
      emit(state.copyWith(searchQuery: event.query, searchResults: []));
      return;
    }
    final results = await _repository.searchMessages(event.query);
    emit(state.copyWith(searchQuery: event.query, searchResults: results));
  }
}
