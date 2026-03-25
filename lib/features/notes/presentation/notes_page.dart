import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/database_helper.dart';
import '../data/message_repository.dart';
import 'bloc/chat_bloc.dart';
import 'chat_screen.dart';

/// Notes tab: Telegram-like chat with deferred load and smooth entrance animation.
/// First frame shows a light placeholder so tab transition doesn't jank; then content fades in.
class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> with TickerProviderStateMixin {
  bool _contentBuilt = false;
  late final AnimationController _entranceCtrl;
  late final Animation<double> _entranceAnim;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _entranceAnim = CurvedAnimation(
      parent: _entranceCtrl,
      curve: Curves.easeOutCubic,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _contentBuilt = true);
      _entranceCtrl.forward();
    });
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_contentBuilt) {
      final color = Theme.of(context).colorScheme.surface;
      return RepaintBoundary(
        child: ColoredBox(
          color: color,
          child: const SizedBox.expand(),
        ),
      );
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _entranceAnim,
        builder: (context, child) {
          return FadeTransition(
            opacity: _entranceAnim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.03),
                end: Offset.zero,
              ).animate(_entranceAnim),
              child: child,
            ),
          );
        },
        child: BlocProvider(
          create: (_) => ChatBloc(MessageRepository.instance),
          child: const ChatScreen(
            chatId: DatabaseHelper.kNotesChatId,
            title: 'Заметки',
          ),
        ),
      ),
    );
  }
}

