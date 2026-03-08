import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/database_helper.dart';
import '../data/message_repository.dart';
import 'bloc/chat_bloc.dart';
import 'chat_screen.dart';

/// Notes tab: Telegram-like chat backed by SQLite (single chat "notes").
class NotesPage extends StatelessWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ChatBloc(MessageRepository.instance),
      child: const ChatScreen(
        chatId: DatabaseHelper.kNotesChatId,
        title: 'Заметки',
      ),
    );
  }
}
