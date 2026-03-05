import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:intl/intl.dart";

import "../data/chat_repository.dart";
import "../domain/chat_message.dart";
import "bloc/chat_bloc.dart";
import "widgets/chat_input_bar.dart";
import "widgets/message_bubble.dart";
import "widgets/pinned_banner.dart";

/// Заметки в виде чата (Telegram-style). Isar + BLoC.
class NotesPage extends StatelessWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ChatBloc(ChatRepository())..add(const ChatLoadRequested()),
      child: const _NotesPageBody(),
    );
  }
}

class _NotesPageBody extends StatelessWidget {
  const _NotesPageBody();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Заметки"),
        actions: [
          IconButton(
            icon: const Icon(Icons.mic_rounded),
            onPressed: () => _startVoiceRecording(context),
            tooltip: "Голосовое сообщение",
          ),
        ],
      ),
      body: Column(
        children: [
          BlocBuilder<ChatBloc, ChatState>(
            buildWhen: (a, b) => a.pinned != b.pinned,
            builder: (context, state) {
              if (state.pinned.isEmpty) return const SizedBox.shrink();
              return PinnedBanner(
                message: state.pinned.first,
                onTap: () {},
                onClose: () => context.read<ChatBloc>().add(ChatPinToggled(state.pinned.first.id)),
              );
            },
          ),
          Expanded(
            child: BlocBuilder<ChatBloc, ChatState>(
              buildWhen: (a, b) =>
                  a.messages != b.messages ||
                  a.searchResults != b.searchResults ||
                  a.searchQuery != b.searchQuery,
              builder: (context, state) {
                if (state.status == ChatStatus.loading && state.messages.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = state.displayMessages;
                if (list.isEmpty) {
                  return Center(
                    child: Text(
                      "Нет сообщений. Напишите что-нибудь.",
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  reverse: true,
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final msg = list[list.length - 1 - index];
                    final showDate = _showDateHeader(list, list.length - 1 - index);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showDate) _DateHeader(date: msg.createdAt),
                        MessageBubble(
                          message: msg,
                          onLongPress: () => _showContextMenu(context, msg),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          const ChatInputBar(),
        ],
      ),
    );
  }

  bool _showDateHeader(List<ChatMessage> list, int index) {
    if (index <= 0) return true;
    final prev = list[index - 1].createdAt;
    final curr = list[index].createdAt;
    return prev.day != curr.day ||
        prev.month != curr.month ||
        prev.year != curr.year;
  }

  void _showContextMenu(BuildContext context, ChatMessage msg) {
    final bloc = context.read<ChatBloc>();
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.push_pin_outlined, color: theme.colorScheme.onSurface),
              title: Text(msg.isPinned ? "Открепить" : "Закрепить"),
              onTap: () {
                Navigator.pop(ctx);
                bloc.add(ChatPinToggled(msg.id));
              },
            ),
            ListTile(
              leading: Icon(Icons.star_outline, color: theme.colorScheme.onSurface),
              title: Text(msg.isFavorite ? "Убрать из избранного" : "В избранное"),
              onTap: () {
                Navigator.pop(ctx);
                bloc.add(ChatFavoriteToggled(msg.id));
              },
            ),
            if (msg.type == "text")
              ListTile(
                leading: Icon(Icons.edit_outlined, color: theme.colorScheme.onSurface),
                title: const Text("Редактировать"),
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditDialog(context, msg);
                },
              ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
              title: Text("Удалить", style: TextStyle(color: theme.colorScheme.error)),
              onTap: () {
                Navigator.pop(ctx);
                bloc.add(ChatMessageDeleted(msg.id));
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context, ChatMessage msg) {
    final controller = TextEditingController(text: msg.text);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Редактировать"),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(hintText: "Текст сообщения"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Отмена"),
          ),
          FilledButton(
            onPressed: () {
              final t = controller.text.trim();
              Navigator.pop(ctx);
              if (t.isNotEmpty) {
                context.read<ChatBloc>().add(ChatMessageUpdated(msg.id, t));
              }
            },
            child: const Text("Сохранить"),
          ),
        ],
      ),
    );
  }

  void _startVoiceRecording(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Голосовые — в разработке")),
    );
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);
    String label;
    if (dateOnly == today) {
      label = "Сегодня";
    } else if (dateOnly == yesterday) {
      label = "Вчера";
    } else {
      label = DateFormat("d MMMM yyyy", "ru").format(date);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ),
    );
  }
}
