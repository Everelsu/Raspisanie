import 'dart:async';
import 'dart:io';
import 'dart:math' show max, min, sin, sqrt;
import 'dart:typed_data';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flyer_chat_image_message/flyer_chat_image_message.dart';
import 'package:flyer_chat_file_message/flyer_chat_file_message.dart';
import 'package:flyer_chat_text_message/flyer_chat_text_message.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cross_file/cross_file.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../data/message.dart' as app;
import '../data/message_repository.dart';
import 'bloc/chat_bloc.dart';
import 'flyer_message_adapter.dart';
import 'voice_player_service.dart';

final RegExp _urlInTextRegExp = RegExp(
  r'https?://[^\s<>"{}|\\^`\[\]\u0000-\u001F]+',
  caseSensitive: false,
);

String? _extractFirstUrl(String text) {
  final match = _urlInTextRegExp.firstMatch(text);
  return match?.group(0);
}

Future<LinkPreviewData?> _fetchOgPreview(String pageUrl) async {
  try {
    final uri = Uri.parse(pageUrl);
    if (!uri.hasScheme || (!uri.scheme.startsWith('http'))) return null;
    final response = await http.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    final html = response.body;
    String? title = _ogContent(html, 'og:title');
    String? description = _ogContent(html, 'og:description');
    String? imageUrl = _ogContent(html, 'og:image');
    if (imageUrl != null && imageUrl.isNotEmpty && !imageUrl.startsWith('http')) {
      imageUrl = uri.resolve(imageUrl).toString();
    }
    ImagePreviewData? image;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      image = ImagePreviewData(url: imageUrl, width: 0, height: 0);
    }
    return LinkPreviewData(
      link: pageUrl,
      title: title,
      description: description,
      image: image,
    );
  } catch (_) {
    return null;
  }
}

String? _ogContent(String html, String property) {
  final re = RegExp(
    'meta[^>]*property=["\']${RegExp.escape(property)}["\'][^>]*content=["\']([^"\']*)["\']',
    caseSensitive: false,
  );
  final m = re.firstMatch(html);
  return m?.group(1)?.trim();
}

ChatTheme _chatThemeFromAppTheme(ThemeData theme) {
  final cs = theme.colorScheme;
  final base =
      theme.brightness == Brightness.dark ? ChatTheme.dark() : ChatTheme.light();
  return theme.brightness == Brightness.dark
      ? base.withDarkColors(
          primary: cs.primary,
          onPrimary: cs.onPrimary,
          surface: cs.surface,
          onSurface: cs.onSurface,
          surfaceContainer: cs.surfaceContainer,
          surfaceContainerLow: cs.surfaceContainerLow,
          surfaceContainerHigh: cs.surfaceContainerHigh,
        )
      : base.withLightColors(
          primary: cs.primary,
          onPrimary: cs.onPrimary,
          surface: cs.surface,
          onSurface: cs.onSurface,
          surfaceContainer: cs.surfaceContainer,
          surfaceContainerLow: cs.surfaceContainerLow,
          surfaceContainerHigh: cs.surfaceContainerHigh,
        );
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.chatId,
    this.title = 'Заметки',
  });

  final String chatId;
  final String title;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final InMemoryChatController _chatController = InMemoryChatController();
  final TextEditingController _composerController = TextEditingController();
  final _uuid = const Uuid();

  /// Flyer message we're replying to (for reply bar and send).
  Message? _replyingTo;
  /// Flyer message we're editing (for edit bar and send).
  Message? _editingMessage;
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  bool _isLocked = false;
  String? _recordPath;
  Duration _recordElapsed = Duration.zero;
  bool _recordPaused = false;
  double _recordDragDx = 0;
  double _recordDragDy = 0;
  List<double> _recordWaveform = [];
  Timer? _recordTimer;
  Timer? _recordAmplitudeTimer;

  /// Текущий индекс закреплённого в единой полосе; при смене списка сбрасывается.
  int _pinnedIndex = 0;
  /// Панель закрепов скрыта по ✕ или свайпу вверх (без открепления).
  bool _pinnedBarHidden = false;

  /// Вложенные фото, ожидающие отправки (подпись вводится в основном поле).
  List<XFile> _pendingImages = [];


  @override
  void initState() {
    super.initState();
    context.read<ChatBloc>().add(ChatLoadMessages(chatId: widget.chatId));
    _composerController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _recordAmplitudeTimer?.cancel();
    if (_isRecording) _audioRecorder.stop().ignore();
    _audioRecorder.dispose();
    _composerController.dispose();
    _chatController.dispose();
    super.dispose();
  }

  static const int _cancelDragThresholdPx = 80;

  Future<void> _startRecording() async {
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет доступа к микрофону')));
      return;
    }
    try {
      final path = await MessageRepository.instance.getVoiceRecordingPath();
      if (!mounted) return;
      await _audioRecorder.start(const RecordConfig(), path: path);
      if (!mounted) return;
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _recordElapsed += const Duration(seconds: 1));
      });
      _recordAmplitudeTimer?.cancel();
      _recordWaveform = [];
      _recordAmplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
        if (!mounted || !_isRecording) return;
        try {
          final amp = await _audioRecorder.getAmplitude();
          final normalized = ((amp.current + 160) / 160).clamp(0.0, 1.0);
          final smoothed = sqrt(normalized);
          if (mounted) {
            setState(() {
            _recordWaveform = [..._recordWaveform, smoothed];
            if (_recordWaveform.length > 120) _recordWaveform = _recordWaveform.sublist(_recordWaveform.length - 120);
          });
          }
        } catch (_) {}
      });
      setState(() {
        _isRecording = true;
        _recordPath = path;
        _recordElapsed = Duration.zero;
        _recordPaused = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isRecording = false);
    }
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    _recordAmplitudeTimer?.cancel();
    _recordTimer = null;
    _recordAmplitudeTimer = null;
    await _audioRecorder.stop();
    final path = _recordPath;
    if (path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _isRecording = false;
        _isLocked = false;
        _recordPath = null;
        _recordElapsed = Duration.zero;
        _recordPaused = false;
        _recordWaveform = [];
      });
    }
  }

  void _togglePauseRecord() async {
    if (_recordPaused) {
      await _audioRecorder.resume();
      if (mounted) setState(() => _recordPaused = false);
    } else {
      await _audioRecorder.pause();
      if (mounted) setState(() => _recordPaused = true);
    }
  }

  Future<void> _stopAndSendVoice() async {
    _recordTimer?.cancel();
    _recordAmplitudeTimer?.cancel();
    _recordTimer = null;
    _recordAmplitudeTimer = null;
    final path = _recordPath;
    await _audioRecorder.stop();
    if (!mounted || path == null) {
      if (mounted) {
        setState(() {
        _isRecording = false;
        _isLocked = false;
        _recordPath = null;
      });
      }
      return;
    }
    final messageId = _uuid.v4();
    final now = DateTime.now().toUtc();
    final flyerMsg = AudioMessage(
      id: '${messageId}_v',
      authorId: currentUserId,
      createdAt: now,
      sentAt: now,
      source: path,
      duration: _recordElapsed,
      metadata: {'ourMessageId': messageId, 'durationMs': _recordElapsed.inMilliseconds},
    );
    await _chatController.insertMessage(flyerMsg);
    if (!mounted) return;
    context.read<ChatBloc>().add(ChatSendMessage(
      chatId: widget.chatId,
      type: app.MessageType.voice,
      messageId: messageId,
      mediaFiles: [app.MediaFile(id: _uuid.v4(), messageId: messageId, type: 'voice', localPath: path, createdAt: DateTime.now())],
    ));
    setState(() {
      _isRecording = false;
      _isLocked = false;
      _recordPath = null;
      _recordElapsed = Duration.zero;
      _recordPaused = false;
      _recordWaveform = [];
    });
  }

  void _onMicPanStart(DragStartDetails details) {
    _recordDragDx = 0;
    _recordDragDy = 0;
    HapticFeedback.mediumImpact();
    _startRecording();
  }

  void _onMicPanUpdate(DragUpdateDetails details) {
    setState(() {
      _recordDragDx += details.delta.dx;
      _recordDragDy += details.delta.dy;
    });
  }

  void _onMicPanEnd(DragEndDetails details) {
    if (_recordPath == null) return;
    if (_recordDragDx < -_cancelDragThresholdPx) {
      HapticFeedback.lightImpact();
      _cancelRecording();
      return;
    }
    if (_recordDragDy < -_cancelDragThresholdPx) {
      setState(() => _isLocked = true);
      return;
    }
    _stopAndSendVoice();
  }

  Future<void> _scrollToPinnedMessage([app.Message? message]) async {
    final state = context.read<ChatBloc>().state;
    if (state is! ChatLoaded) return;
    final toScroll = message ?? state.pinnedMessage;
    if (toScroll == null) return;
    final firstPartId = firstFlyerMessageId(toScroll);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    await _chatController.scrollToMessage(firstPartId, alignment: 0.25);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
          ? colorScheme.surface
          : colorScheme.surface.withValues(alpha: 0.98),
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(widget.title),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: colorScheme.onSurface),
            onSelected: (value) {
              if (value == 'show_pinned') setState(() => _pinnedBarHidden = false);
              if (value == 'clear') _confirmClearAll();
            },
            itemBuilder: (context) {
              final state = context.read<ChatBloc>().state;
              final hasPinned = state is ChatLoaded && state.pinnedMessages.isNotEmpty;
              return [
                if (_pinnedBarHidden && hasPinned)
                  const PopupMenuItem(
                    value: 'show_pinned',
                    child: Row(
                      children: [
                        Icon(Icons.push_pin_outlined),
                        SizedBox(width: 12),
                        Text('Показать закрепы'),
                      ],
                    ),
                  ),
                const PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep_outlined),
                      SizedBox(width: 12),
                      Text('Очистить все заметки'),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      body: Column(
        children: [
          BlocConsumer<ChatBloc, ChatState>(
            listenWhen: (prev, curr) => curr is ChatLoaded,
            listener: (context, state) {
              if (state is! ChatLoaded) return;
              if (state.messages.isEmpty) {
                if (_chatController.messages.isNotEmpty) {
                  _chatController.setMessages([], animated: false);
                }
              } else {
                // Синхронизируем список с state (в т.ч. после редактирования).
                final oldestFirst = state.messages.reversed.toList();
                _chatController.setMessages(appMessagesToFlyer(oldestFirst), animated: false);
              }
              if (state.pinnedMessages.isNotEmpty) {
                setState(() {
                  _pinnedBarHidden = false;
                  if (_pinnedIndex >= state.pinnedMessages.length) _pinnedIndex = 0;
                });
              }
            },
            buildWhen: (prev, curr) => curr is ChatLoaded,
            builder: (context, state) {
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => SizeTransition(
                  sizeFactor: anim,
                  axisAlignment: -1,
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: state is ChatLoaded && state.pinnedMessages.isNotEmpty && !_pinnedBarHidden
                    ? _PinnedMessageBar(
                        key: ValueKey('pinned-${state.pinnedMessages.map((m) => m.id).join(",")}'),
                        pinnedMessages: state.pinnedMessages,
                        currentIndex: _pinnedIndex,
                        onTap: () async {
                          final msg = state.pinnedMessages[_pinnedIndex];
                          await _scrollToPinnedMessage(msg);
                          if (!mounted) return;
                          setState(() => _pinnedIndex = (state.pinnedMessages.length > 1) ? (_pinnedIndex + 1) % state.pinnedMessages.length : 0);
                        },
                        onClose: () => setState(() => _pinnedBarHidden = true),
                        onUnpin: (messageId) => context.read<ChatBloc>().add(ChatUnpinMessage(chatId: widget.chatId, messageId: messageId)),
                      )
                    : const SizedBox.shrink(key: ValueKey('no-pinned')),
              );
            },
          ),
          Expanded(
            child: BlocBuilder<ChatBloc, ChatState>(
              builder: (context, state) {
                if (state is ChatLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is ChatError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                          const SizedBox(height: 16),
                          Text(
                            state.message,
                            style: theme.textTheme.bodyLarge,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => context.read<ChatBloc>().add(ChatLoadMessages(chatId: widget.chatId)),
                            icon: const Icon(Icons.refresh, size: 20),
                            label: const Text('Повторить'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (state is ChatLoaded) {
                  return Column(
                    children: [
                      Expanded(
                        child: Chat(
                          chatController: _chatController,
                          currentUserId: currentUserId,
                          resolveUser: (id) => Future.value(User(id: id, name: 'Вы')),
                          theme: _chatThemeFromAppTheme(theme),
                          timeFormat: DateFormat('HH:mm'),
                          decoration: BoxDecoration(
                            color: _chatThemeFromAppTheme(theme).colors.surface,
                          ),
                          onMessageSend: _onMessageSend,
                          onAttachmentTap: _onAttachmentTap,
                          onMessageLongPress: _onMessageLongPress,
                          builders: Builders(
                      textMessageBuilder: (context, message, index, {required isSentByMe, groupStatus}) {
                        if (message.linkPreviewData != null) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FlyerChatTextMessage(message: message, index: index),
                              _LinkPreviewCard(preview: message.linkPreviewData!),
                            ],
                          );
                        }
                        return FlyerChatTextMessage(message: message, index: index);
                      },
                      imageMessageBuilder: (context, message, index, {required isSentByMe, groupStatus}) {
                        final source = message.source;
                        return GestureDetector(
                          onTap: () => _openPhotoGallery(context, [source], 0),
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.bottomRight,
                            children: [
                              FlyerChatImageMessage(
                                message: message,
                                index: index,
                                customImageProvider: isLocalFileSource(message.source)
                                    ? FileImage(File(message.source))
                                    : null,
                              ),
                              Positioned(
                                bottom: 4,
                                right: 8,
                                child: _MessageTime(
                                  createdAt: message.createdAt ?? DateTime.now(),
                                  inline: true,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      fileMessageBuilder: (context, message, index, {required isSentByMe, groupStatus}) =>
                          Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.bottomRight,
                            children: [
                              FlyerChatFileMessage(message: message, index: index),
                              Positioned(
                                bottom: 4,
                                right: 8,
                                child: _MessageTime(
                                  createdAt: message.createdAt ?? DateTime.now(),
                                  inline: true,
                                ),
                              ),
                            ],
                          ),
                      audioMessageBuilder: (context, message, index, {required isSentByMe, groupStatus}) =>
                          _VoiceMessageBubble(message: message, isMine: isSentByMe),
                      customMessageBuilder: (context, message, index, {required isSentByMe, groupStatus}) {
                        if (message.metadata?['type'] == 'album') {
                          return _AlbumBubble(
                            message: message,
                            messageWidth: MediaQuery.sizeOf(context).width * 0.8,
                            isMine: isSentByMe,
                            isDark: theme.brightness == Brightness.dark,
                            theme: theme,
                            onImageTap: (sources, initialIndex) => _openPhotoGallery(context, sources, initialIndex),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                      chatMessageBuilder: (context, message, index, animation, child, {isRemoved, required isSentByMe, groupStatus}) =>
                          ChatMessage(
                            message: message,
                            index: index,
                            animation: animation,
                            isRemoved: isRemoved,
                            groupStatus: groupStatus,
                            horizontalPadding: 8,
                            child: child,
                          ),
                      emptyChatListBuilder: (context) => _EmptyChatPlaceholder(theme: theme, colorScheme: colorScheme),
                      composerBuilder: (context) => const SizedBox.shrink(),
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: _buildFullComposer(context, theme, colorScheme),
                ),
              ],
            );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildLockedVoiceBar(ThemeData theme, ColorScheme colorScheme) {
    final mm = _recordElapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = _recordElapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
        border: Border(left: BorderSide(color: colorScheme.primary, width: 3)),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: _cancelRecording,
            child: Text('Отмена', style: TextStyle(color: colorScheme.error)),
          ),
          Text('$mm:$ss', style: theme.textTheme.titleMedium?.copyWith(fontFeatures: [const FontFeature.tabularFigures()])),
          const SizedBox(width: 16),
          IconButton(
            icon: Icon(_recordPaused ? Icons.mic_rounded : Icons.pause_rounded, color: colorScheme.primary),
            onPressed: _togglePauseRecord,
          ),
          IconButton(
            icon: Icon(Icons.send_rounded, color: colorScheme.primary),
            onPressed: _stopAndSendVoice,
          ),
        ],
      ),
    );
  }

  Widget? _buildComposerTop(ThemeData theme, ColorScheme colorScheme) {
    if (_isLocked) return _buildLockedVoiceBar(theme, colorScheme);
    final hasPending = _pendingImages.isNotEmpty;
    final hasReplyOrEdit = _replyingTo != null || _editingMessage != null;
    if (!hasPending && !hasReplyOrEdit) return null;
    final children = <Widget>[];
    if (hasPending) children.add(_buildPendingImagesStrip(theme, colorScheme));
    if (_editingMessage != null) {
      final msg = _editingMessage!;
      final snippet = msg is TextMessage ? (msg.text.length > 40 ? '${msg.text.substring(0, 40)}...' : msg.text) : 'Фото';
      children.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.25),
            border: Border(left: BorderSide(color: colorScheme.tertiary, width: 3)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('✏ Редактирование', style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.tertiary, fontWeight: FontWeight.w600, fontSize: 11)),
                    const SizedBox(height: 2),
                    Text(snippet, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.85)), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _editingMessage = null;
                  _composerController.clear();
                }),
                child: const Text('Отмена'),
              ),
            ],
          ),
        ),
      );
    } else if (_replyingTo != null) {
    final reply = _replyingTo!;
    final snippet = reply is TextMessage ? (reply.text.length > 40 ? '${reply.text.substring(0, 40)}...' : reply.text) : 'Фото';
    children.add(
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          border: Border(left: BorderSide(color: colorScheme.primary, width: 3)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('↩ В ответ на', style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.w600, fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(snippet, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.85)), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, size: 20, color: colorScheme.onSurface.withValues(alpha: 0.7)),
              onPressed: () => setState(() => _replyingTo = null),
              style: IconButton.styleFrom(minimumSize: const Size(36, 36), padding: EdgeInsets.zero),
            ),
          ],
        ),
      ),
    );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }

  Widget _buildPendingImagesStrip(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(bottom: BorderSide(color: colorScheme.outline.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 72,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _pendingImages.length,
                itemBuilder: (context, i) {
                  final x = _pendingImages[i];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 72,
                            height: 72,
                            child: x.path.isNotEmpty && File(x.path).existsSync()
                                ? Image.file(File(x.path), fit: BoxFit.cover)
                                : FutureBuilder<Uint8List>(
                                    future: x.readAsBytes(),
                                    builder: (_, snap) {
                                      if (snap.hasData && snap.data != null) {
                                        return Image.memory(snap.data!, fit: BoxFit.cover);
                                      }
                                      return const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
                                    },
                                  ),
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _pendingImages = List.from(_pendingImages)..removeAt(i);
                            }),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                              child: const Icon(Icons.close, size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          if (_pendingImages.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _pendingImages = []),
              child: const Text('Убрать все'),
            ),
        ],
      ),
    );
  }

  Widget _buildFullComposer(BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_buildComposerTop(theme, colorScheme) != null) _buildComposerTop(theme, colorScheme)!,
        _buildComposerRow(context, theme, colorScheme),
      ],
    );
  }

  Widget _buildComposerRow(BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    final chatColors = _chatThemeFromAppTheme(theme).colors;
    final isRecording = _isRecording && !_isLocked;
    return Container(
      padding: const EdgeInsets.all(8),
      color: chatColors.surfaceContainer,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isRecording)
            IconButton(
              icon: Icon(Icons.attachment, color: chatColors.onSurface),
              onPressed: _onAttachmentTap,
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(22),
              ),
              child: isRecording
                  ? _RecordingIndicator(
                      elapsed: _recordElapsed,
                      waveform: _recordWaveform,
                      dragX: _recordDragDx,
                      theme: theme,
                      colorScheme: colorScheme,
                    )
                  : TextField(
                      controller: _composerController,
                      decoration: InputDecoration(
                        hintText: 'Сообщение...',
                        border: const OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(24))),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest,
                      ),
                      maxLines: 3,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (t) {
                        if (_pendingImages.isNotEmpty) {
                          _sendPendingImagesAndClear();
                        } else if (t.trim().isNotEmpty) {
                          _onMessageSend(t);
                        }
                      },
                    ),
            ),
          ),
          const SizedBox(width: 8),
          _buildSendOrMicButton(theme, colorScheme, chatColors),
        ],
      ),
    );
  }

  Widget _buildSendOrMicButton(ThemeData theme, ColorScheme colorScheme, ChatColors chatColors) {
    final hasText = _composerController.text.trim().isNotEmpty;
    final hasPending = _pendingImages.isNotEmpty;
    final isRecording = _isRecording && !_isLocked;
    if (hasText || hasPending) {
      return IconButton(
        icon: Icon(Icons.send_rounded, color: colorScheme.primary),
        onPressed: () {
          if (hasPending) {
            _sendPendingImagesAndClear();
          } else {
            _onMessageSend(_composerController.text);
          }
        },
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: _onMicPanStart,
      onPanUpdate: _onMicPanUpdate,
      onPanEnd: _onMicPanEnd,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.all(12),
        child: Icon(
          Icons.mic_rounded,
          color: isRecording ? colorScheme.error : colorScheme.primary,
        ),
      ),
    );
  }

  void _onMessageSend(String? text) async {
    final t = text?.trim() ?? '';
    if (_editingMessage != null) {
      final ourId = ourMessageIdFromFlyer(_editingMessage!);
      context.read<ChatBloc>().add(ChatEditMessage(messageId: ourId, newContent: t));
      setState(() {
        _editingMessage = null;
        _composerController.clear();
      });
      return;
    }
    if (t.isEmpty && _replyingTo == null) return;

    final messageId = _uuid.v4();
    final replyToId = _replyingTo != null ? ourMessageIdFromFlyer(_replyingTo!) : null;
    final now = DateTime.now().toUtc();

    final flyerMsg = TextMessage(
      id: '${messageId}_t',
      authorId: currentUserId,
      replyToMessageId: _replyingTo?.id,
      createdAt: now,
      sentAt: now,
      text: t.isEmpty ? ' ' : t,
      metadata: {'ourMessageId': messageId},
    );
    await _chatController.insertMessage(flyerMsg);
    context.read<ChatBloc>().add(ChatSendMessage(
          chatId: widget.chatId,
          content: t.isEmpty ? null : t,
          type: app.MessageType.text,
          replyToId: replyToId,
          messageId: messageId,
        ));
    setState(() {
      _replyingTo = null;
      _composerController.clear();
    });
    final firstUrl = _extractFirstUrl(t);
    if (firstUrl != null) _fetchAndAttachLinkPreview(flyerMsg, firstUrl);
  }

  Future<void> _fetchAndAttachLinkPreview(TextMessage message, String url) async {
    final preview = await _fetchOgPreview(url);
    if (!mounted || preview == null) return;
    final list = _chatController.messages;
    final idx = list.indexWhere((m) => m.id == message.id);
    if (idx < 0) return;
    final oldMsg = list[idx];
    final updated = (oldMsg as TextMessage).copyWith(linkPreviewData: preview);
    await _chatController.updateMessage(oldMsg, updated);
  }

  void _onAttachmentTap() async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final picker = ImagePicker();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.collections_outlined, color: colorScheme.primary),
                title: Text('Галерея', style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final images = await picker.pickMultiImage();
                  if (images.isNotEmpty && mounted) setState(() => _pendingImages = images);
                },
              ),
              ListTile(
                leading: Icon(Icons.camera_alt_outlined, color: colorScheme.primary),
                title: Text('Камера', style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final image = await picker.pickImage(source: ImageSource.camera);
                  if (image != null && mounted) setState(() => _pendingImages = [image]);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Отправка вложенных фото (подпись берётся из поля ввода) и очистка.
  Future<void> _sendPendingImagesAndClear() async {
    if (_pendingImages.isEmpty) return;
    final files = List<XFile>.from(_pendingImages);
    final caption = _composerController.text.trim();
    final content = caption.isEmpty ? null : caption;
    setState(() {
      _pendingImages = [];
      _composerController.clear();
    });
    if (files.length == 1) {
      await _sendImage(files.single, content: content);
    } else {
      await _sendImages(files, content: content);
    }
  }

  Future<void> _sendImage(XFile xFile, {String? content}) async {
    final messageId = _uuid.v4();
    final saved = await MessageRepository.instance.savePickedImage(xFile);
    if (saved == null || !mounted) return;
    final now = DateTime.now().toUtc();
    final flyerMsg = ImageMessage(
      id: '${messageId}_i0',
      authorId: currentUserId,
      createdAt: now,
      sentAt: now,
      source: saved,
      text: (content != null && content.trim().isNotEmpty) ? content.trim() : null,
      metadata: {'ourMessageId': messageId},
    );
    await _chatController.insertMessage(flyerMsg);
    if (!mounted) return;
    context.read<ChatBloc>().add(ChatSendMessage(
          chatId: widget.chatId,
          type: app.MessageType.image,
          messageId: messageId,
          content: content?.trim().isEmpty == true ? null : content,
          mediaFiles: [app.MediaFile(id: _uuid.v4(), messageId: messageId, type: 'image', localPath: saved, createdAt: DateTime.now())],
        ));
  }

  /// Отправка нескольких фото одним сообщением (альбом с опциональной подписью).
  Future<void> _sendImages(List<XFile> xFiles, {String? content}) async {
    if (xFiles.isEmpty) return;
    final messageId = _uuid.v4();
    final now = DateTime.now().toUtc();
    final mediaFiles = <app.MediaFile>[];
    final repo = MessageRepository.instance;

    for (var i = 0; i < xFiles.length; i++) {
      final saved = await repo.savePickedImage(xFiles[i]);
      if (saved != null) {
        mediaFiles.add(app.MediaFile(
          id: _uuid.v4(),
          messageId: messageId,
          type: 'image',
          localPath: saved,
          createdAt: DateTime.now(),
        ));
      }
      if (!mounted) return;
    }

    if (mediaFiles.isEmpty) return;

    if (mediaFiles.length == 1) {
      final flyerMsg = ImageMessage(
        id: '${messageId}_i0',
        authorId: currentUserId,
        createdAt: now,
        sentAt: now,
        source: mediaFiles[0].localPath,
        text: (content != null && content.trim().isNotEmpty) ? content.trim() : null,
        metadata: {'ourMessageId': messageId},
      );
      await _chatController.insertMessage(flyerMsg);
    } else {
      final sources = mediaFiles.map((e) => e.localPath).toList();
      final albumMeta = {'ourMessageId': messageId, 'type': 'album', 'sources': sources};
      if (content != null && content.trim().isNotEmpty) albumMeta['caption'] = content.trim();
      final albumMsg = Message.custom(
        id: '${messageId}_album',
        authorId: currentUserId,
        createdAt: now,
        sentAt: now,
        metadata: albumMeta,
      );
      await _chatController.insertMessage(albumMsg);
    }
    if (!mounted) return;

    context.read<ChatBloc>().add(ChatSendMessage(
          chatId: widget.chatId,
          type: app.MessageType.image,
          messageId: messageId,
          content: content?.trim().isEmpty == true ? null : content,
          mediaFiles: mediaFiles,
        ));
  }

  void _onMessageLongPress(BuildContext context, Message message, {required int index, required LongPressStartDetails details}) async {
    final ourId = ourMessageIdFromFlyer(message);
    final screenSize = MediaQuery.sizeOf(context);
    final state = context.read<ChatBloc>().state;
    final isPinned = state is ChatLoaded && state.pinnedMessages.any((m) => m.id == ourId);
    const menuWidth = 220.0;
    const menuHeight = 320.0;
    var left = details.globalPosition.dx - menuWidth / 2;
    var top = details.globalPosition.dy - menuHeight - 12;
    if (left < 8) left = 8;
    if (left + menuWidth > screenSize.width - 8) left = screenSize.width - menuWidth - 8;
    if (top < 8) top = details.globalPosition.dy + 8;
    final position = RelativeRect.fromLTRB(left, top, screenSize.width - left - menuWidth, screenSize.height - top - menuHeight);

    await showMenu<String>(
      context: context,
      position: position,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      elevation: 8,
      items: [
        if (message is TextMessage)
          _menuItem(context, Icons.copy, 'Копировать', () {
            Clipboard.setData(ClipboardData(text: message.text));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопировано'), duration: Duration(seconds: 1)));
          }),
        _menuItem(context, Icons.share_outlined, 'Поделиться', () => _shareMessage(ourId)),
        if (message is TextMessage)
          _menuItem(context, Icons.edit_outlined, 'Редактировать', () {
            setState(() {
              _editingMessage = message;
              _composerController.text = message.text;
              _composerController.selection = TextSelection.collapsed(offset: message.text.length);
            });
          }),
        if (isPinned)
          _menuItem(context, Icons.push_pin_outlined, 'Открепить', () => context.read<ChatBloc>().add(ChatUnpinMessage(chatId: widget.chatId, messageId: ourId))),
        if (!isPinned)
          _menuItem(context, Icons.push_pin, 'Закрепить', () => context.read<ChatBloc>().add(ChatPinMessage(chatId: widget.chatId, messageId: ourId))),
        PopupMenuItem<String>(
          value: 'delete',
          onTap: () => _deleteFlyerMessage(ourId),
          child: Row(
            children: [
              Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error, size: 22),
              const SizedBox(width: 12),
              Text('Удалить', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopupMenuItem<String>(
      value: label,
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: colorScheme.primary, size: 22),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }

  Future<void> _deleteFlyerMessage(String ourId) async {
    final toRemove = _chatController.messages.where((m) => ourMessageIdFromFlyer(m) == ourId).toList();
    for (final m in toRemove) {
      await _chatController.removeMessage(m);
    }
    context.read<ChatBloc>().add(ChatDeleteMessage(messageId: ourId));
  }

  Future<void> _shareMessage(String ourId) async {
    final state = context.read<ChatBloc>().state;
    if (state is! ChatLoaded) return;
    final appMsg = state.messages.cast<app.Message?>().firstWhere((m) => m?.id == ourId, orElse: () => null);
    if (appMsg == null) return;
    final paths = appMsg.mediaFiles.map((e) => e.localPath).toList();
    if (paths.isNotEmpty) {
      await Share.shareXFiles(paths.map((p) => XFile(p)).toList(), text: appMsg.content ?? '');
    } else if (appMsg.content != null && appMsg.content!.isNotEmpty) {
      await Share.share(appMsg.content!);
    }
  }

  void _confirmClearAll() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorScheme.surface,
        title: Text('Очистить заметки?', style: theme.textTheme.titleLarge?.copyWith(color: colorScheme.onSurface)),
        content: Text('Все сообщения будут удалены.', style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена', style: TextStyle(color: colorScheme.primary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _chatController.setMessages([]);
              context.read<ChatBloc>().add(ChatClearAll(chatId: widget.chatId));
            },
            child: Text('Очистить', style: TextStyle(color: colorScheme.error)),
          ),
        ],
      ),
    );
  }
}

/// Индикатор записи голоса: мигающая точка, таймер, waveform, подсказка «Отмена».
class _RecordingIndicator extends StatelessWidget {
  const _RecordingIndicator({
    required this.elapsed,
    required this.waveform,
    required this.dragX,
    required this.theme,
    required this.colorScheme,
  });
  final Duration elapsed;
  final List<double> waveform;
  final double dragX;
  final ThemeData theme;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          const _BlinkingDot(),
          const SizedBox(width: 8),
          Text(
            '$m:$s',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 22,
              child: CustomPaint(
                painter: _MiniWaveformPainter(
                  waveform: waveform,
                  color: colorScheme.error.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
          AnimatedOpacity(
            opacity: dragX.abs() < 20 ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 100),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chevron_left, size: 16, color: colorScheme.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 2),
                Text(
                  'Отмена',
                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot();

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot> with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _c,
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.error,
            shape: BoxShape.circle,
          ),
        ),
      );
}

class _MiniWaveformPainter extends CustomPainter {
  _MiniWaveformPainter({required this.waveform, required this.color});
  final List<double> waveform;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final count = min(waveform.length, 30);
    final step = size.width / count;
    final cy = size.height / 2;
    for (int i = 0; i < count; i++) {
      final amp = waveform[waveform.length - count + i];
      final h = max(2.0, amp * size.height * 0.9);
      final x = i * step + step / 2;
      canvas.drawLine(Offset(x, cy - h / 2), Offset(x, cy + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_MiniWaveformPainter o) => o.waveform != waveform;
}

/// Card showing link preview (title, description, image); tap opens in browser.
class _LinkPreviewCard extends StatelessWidget {
  const _LinkPreviewCard({required this.preview});
  final LinkPreviewData preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final link = preview.link;
    final title = preview.title;
    final description = preview.description;
    final image = preview.image;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            final uri = Uri.tryParse(link);
            if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (image != null && image.url.isNotEmpty)
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    child: Image.network(image.url, height: 140, width: double.infinity, fit: BoxFit.cover),
                  ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (title != null && title.isNotEmpty)
                        Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (description != null && description.isNotEmpty) ...[
                        if (title != null && title.isNotEmpty) const SizedBox(height: 4),
                        Text(description, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.8)), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                      const SizedBox(height: 4),
                      Text(link, style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.primary), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Время сообщения под баблом или внутри бабла (голос, фото, альбом).
class _MessageTime extends StatelessWidget {
  const _MessageTime({required this.createdAt, this.inline = false, this.color});
  final DateTime createdAt;
  /// When true, used inside a bubble (no top padding).
  final bool inline;
  /// Optional color for time text (e.g. onPrimary when inside a "mine" bubble).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatColors = _chatThemeFromAppTheme(theme).colors;
    final timeStr = DateFormat('HH:mm').format(createdAt.toLocal());
    final textColor = color ?? chatColors.onSurface.withValues(alpha: 0.6);
    return Padding(
      padding: EdgeInsets.only(top: inline ? 0 : 2),
      child: Text(
        timeStr,
        style: theme.textTheme.labelSmall?.copyWith(
          color: textColor,
          fontSize: 11,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Голосовое сообщение: play/pause, waveform (seek), таймер, скорость, «прослушано».
class _VoiceMessageBubble extends StatelessWidget {
  const _VoiceMessageBubble({required this.message, required this.isMine});
  final AudioMessage message;
  final bool isMine;

  int get _durationMs {
    final meta = message.metadata;
    if (meta != null && meta['durationMs'] != null) {
      final v = meta['durationMs'];
      if (v is int) return v;
      if (v is double) return v.round();
    }
    return message.duration.inMilliseconds;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatColors = _chatThemeFromAppTheme(theme).colors;
    // Same as text bubbles: mine = primary, other = surfaceContainer
    final bgColor = isMine ? chatColors.primary : chatColors.surfaceContainer;
    final activeColor = isMine ? chatColors.onPrimary : chatColors.primary;
    final inactiveColor = isMine ? chatColors.onPrimary.withValues(alpha: 0.4) : chatColors.onSurface.withValues(alpha: 0.4);
    final textColor = isMine ? chatColors.onPrimary : chatColors.onSurface;

    return ListenableBuilder(
      listenable: VoicePlayerService.instance,
      builder: (context, _) {
        final svc = VoicePlayerService.instance;
        final isActive = svc.isActive(message.id);
        final isPlaying = svc.isPlayingMessage(message.id);
        final progress = isActive ? svc.progress : 0.0;
        final elapsed = isActive ? svc.position : Duration(milliseconds: _durationMs);

        return Container(
          width: 260,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(_kBubbleRadius),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
                  if (isPlaying) {
                    svc.pause();
                  } else if (isActive) {
                    svc.resume();
                  } else {
                    svc.play(messageId: message.id, path: message.source);
                  }
                },
                child: _VoicePlayButton(
                  isPlaying: isPlaying,
                  isMine: isMine,
                  progress: isActive ? progress : 0,
                  activeColor: activeColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onHorizontalDragUpdate: (d) {
                        if (!isActive) return;
                        final box = context.findRenderObject() as RenderBox?;
                        if (box == null) return;
                        final local = box.globalToLocal(d.globalPosition);
                        final p = (local.dx / box.size.width).clamp(0.0, 1.0);
                        svc.seek(p);
                      },
                      onTapDown: (d) {
                        if (!isActive) return;
                        final box = context.findRenderObject() as RenderBox?;
                        if (box == null) return;
                        final local = box.globalToLocal(d.globalPosition);
                        final p = (local.dx / box.size.width).clamp(0.0, 1.0);
                        svc.seek(p);
                      },
                      child: SizedBox(
                        height: 30,
                        child: CustomPaint(
                          painter: _WaveformPainter(
                            waveform: const [],
                            progress: progress,
                            activeColor: activeColor,
                            inactiveColor: inactiveColor,
                          ),
                          size: const Size(double.infinity, 30),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(elapsed),
                          style: TextStyle(
                            color: textColor.withValues(alpha: 0.7),
                            fontSize: 11,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isActive)
                              GestureDetector(
                                onTap: svc.toggleSpeed,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: activeColor.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${svc.speed == svc.speed.truncateToDouble() ? svc.speed.toInt() : svc.speed}×',
                                    style: TextStyle(
                                      color: activeColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            if (isActive) const SizedBox(width: 6),
                            _MessageTime(
                              createdAt: message.createdAt ?? DateTime.now(),
                              inline: true,
                              color: textColor.withValues(alpha: 0.7),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _VoicePlayButton extends StatelessWidget {
  const _VoicePlayButton({
    required this.isPlaying,
    required this.isMine,
    required this.progress,
    required this.activeColor,
  });
  final bool isPlaying;
  final bool isMine;
  final double progress;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isPlaying || progress > 0)
            CircularProgressIndicator(
              value: progress,
              strokeWidth: 2.5,
              backgroundColor: activeColor.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation(activeColor),
            ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              key: ValueKey(isPlaying),
              color: activeColor,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> waveform;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  _WaveformPainter({
    required this.waveform,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty) {
      _drawFallback(canvas, size);
      return;
    }
    final barCount = min(waveform.length, 60);
    final barWidth = size.width / (barCount * 2 - 1);
    final progressX = size.width * progress;
    final centerY = size.height / 2;
    const minH = 3.0;
    for (int i = 0; i < barCount; i++) {
      final x = i * barWidth * 2;
      final amp = waveform[(i * waveform.length ~/ barCount).clamp(0, waveform.length - 1)];
      final barH = max(minH, amp * size.height * 0.85);
      final paint = Paint()
        ..color = x < progressX ? activeColor : inactiveColor
        ..strokeCap = StrokeCap.round
        ..strokeWidth = barWidth * 0.85
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(x + barWidth / 2, centerY - barH / 2),
        Offset(x + barWidth / 2, centerY + barH / 2),
        paint,
      );
    }
  }

  void _drawFallback(Canvas canvas, Size size) {
    const count = 30;
    final step = size.width / count;
    final centerY = size.height / 2;
    final progressX = size.width * progress;
    for (int i = 0; i < count; i++) {
      final x = i * step + step / 2;
      final h = (sin(i * 0.7) * 0.4 + 0.5) * size.height * 0.7;
      final paint = Paint()
        ..color = x < progressX ? activeColor : inactiveColor
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(x, centerY - h / 2),
        Offset(x, centerY + h / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress || old.waveform != waveform;
}

/// Единая полоса закрепов: прогресс N/M, тап — скролл к текущему и переход к следующему, ✕/свайп вверх — скрыть, long-press — открепить.
class _PinnedMessageBar extends StatefulWidget {
  const _PinnedMessageBar({
    super.key,
    required this.pinnedMessages,
    required this.currentIndex,
    required this.onTap,
    required this.onClose,
    this.onUnpin,
  });

  final List<app.Message> pinnedMessages;
  final int currentIndex;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final void Function(String messageId)? onUnpin;

  @override
  State<_PinnedMessageBar> createState() => _PinnedMessageBarState();
}

class _PinnedMessageBarState extends State<_PinnedMessageBar> with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<Offset> _slide;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
    _slide = Tween<Offset>(begin: Offset.zero, end: const Offset(0, -1)).animate(CurvedAnimation(parent: _anim, curve: Curves.easeIn));
    _fade = Tween<double>(begin: 1, end: 0).animate(CurvedAnimation(parent: _anim, curve: Curves.easeIn));
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _hide() async {
    await _anim.forward();
    if (mounted) widget.onClose();
  }

  static String _preview(app.Message msg) {
    final hasText = msg.content != null && msg.content!.trim().isNotEmpty;
    final imageCount = msg.mediaFiles.where((e) => e.type == 'image').length;
    final hasVoice = msg.mediaFiles.any((e) => e.type == 'voice');
    if (hasText) return msg.content!.length > 45 ? '${msg.content!.substring(0, 45)}...' : msg.content!;
    if (hasVoice) return 'Голосовое сообщение';
    return imageCount > 1 ? 'Фото ($imageCount)' : 'Фото';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatColors = _chatThemeFromAppTheme(theme).colors;
    final list = widget.pinnedMessages;
    if (list.isEmpty) return const SizedBox.shrink();
    final idx = widget.currentIndex.clamp(0, list.length - 1);
    final msg = list[idx];
    final total = list.length;

    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: GestureDetector(
          onVerticalDragEnd: (d) {
            if (d.primaryVelocity != null && d.primaryVelocity! < -200) _hide();
          },
          onLongPress: widget.onUnpin != null ? () => widget.onUnpin!(msg.id) : null,
          child: Material(
            color: theme.scaffoldBackgroundColor,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: chatColors.primary, width: 3),
                  bottom: BorderSide(color: chatColors.onSurface.withValues(alpha: 0.12), width: 0.5),
                ),
              ),
              child: InkWell(
                onTap: widget.onTap,
                child: Row(
                  children: [
                    _PinnedProgress(current: idx, total: total, color: chatColors.primary),
                    const SizedBox(width: 10),
                    Icon(Icons.push_pin_outlined, size: 16, color: chatColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            total == 1 ? 'Закреплённое сообщение' : 'Закреплённое ${idx + 1}/$total',
                            style: theme.textTheme.labelSmall?.copyWith(color: chatColors.primary, fontWeight: FontWeight.w600, fontSize: 11),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            _preview(msg),
                            style: theme.textTheme.bodySmall?.copyWith(color: chatColors.onSurface.withValues(alpha: 0.9), fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _hide,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(Icons.close, size: 18, color: chatColors.onSurface.withValues(alpha: 0.6)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PinnedProgress extends StatelessWidget {
  final int current;
  final int total;
  final Color color;

  const _PinnedProgress({required this.current, required this.total, required this.color});

  @override
  Widget build(BuildContext context) {
    if (total <= 1) {
      return Container(
        width: 3,
        height: 28,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
      );
    }
    return SizedBox(
      width: 3,
      height: 28,
      child: Column(
        children: List.generate(total, (i) {
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 1),
              decoration: BoxDecoration(
                color: i == current ? color : color.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class PinnedMessageBanner extends StatelessWidget {
  const PinnedMessageBanner({
    super.key,
    required this.message,
    required this.onTap,
    required this.onClose,
  });

  final app.Message message;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatColors = _chatThemeFromAppTheme(theme).colors;
    final hasText = message.content != null && message.content!.trim().isNotEmpty;
    final imageCount = message.mediaFiles.where((e) => e.type == 'image').length;
    final snippet = hasText
        ? (message.content!.length > 45 ? '${message.content!.substring(0, 45)}...' : message.content!)
        : (imageCount > 1 ? 'Фото ($imageCount)' : 'Фото');
    return Material(
      color: chatColors.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: chatColors.primary, width: 3)),
          ),
          child: Row(
            children: [
              Icon(Icons.push_pin, color: chatColors.primary, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  snippet,
                  style: theme.textTheme.bodySmall?.copyWith(color: chatColors.onSurface.withValues(alpha: 0.9), fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, size: 20, color: chatColors.onSurface.withValues(alpha: 0.6)),
                onPressed: onClose,
                style: IconButton.styleFrom(minimumSize: const Size(36, 36), padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const double _kAlbumMaxWidth = 280;
const double _kAlbumSpacing = 2;
const double _kAlbumRadius = 12;
const double _kBubbleRadius = 12;

/// Один тайл альбома (картинка + опционально оверлей "+N").
Widget _albumTile(
  List<String> images,
  int index,
  double width,
  double height,
  BorderRadius borderRadius, {
  int? overlayPlusN,
  required void Function(List<String>, int) onImageTap,
}) {
  final path = images[index];
  final content = ClipRRect(
    borderRadius: borderRadius,
    child: isLocalFileSource(path)
        ? Image.file(File(path), fit: BoxFit.cover, width: width, height: height)
        : Image.network(path, fit: BoxFit.cover, width: width, height: height),
  );
  return GestureDetector(
    onTap: () => onImageTap(images, index),
    child: SizedBox(
      width: width,
      height: height,
      child: overlayPlusN != null
          ? Stack(
              fit: StackFit.expand,
              children: [
                content,
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: borderRadius,
                    child: Container(
                      color: Colors.black54,
                      alignment: Alignment.center,
                      child: Text('+$overlayPlusN', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            )
          : content,
    ),
  );
}

/// Альбом в стиле Telegram: 1 — во всю ширину; 2 — два в ряд; 3 — большое слева + два справа; 4 — 2×2; 5+ — строки по 2/3; >10 — оверлей "+N".
class _AlbumBubble extends StatelessWidget {
  const _AlbumBubble({
    required this.message,
    required this.messageWidth,
    required this.isMine,
    required this.isDark,
    required this.theme,
    required this.onImageTap,
  });

  final Message message;
  final double messageWidth;
  final bool isMine;
  final bool isDark;
  final ThemeData theme;
  final void Function(List<String> sources, int initialIndex) onImageTap;

  @override
  Widget build(BuildContext context) {
    final raw = message.metadata?['sources'];
    final sources = (raw is List<dynamic>)
        ? raw.map((e) => e is String ? e : e.toString()).toList()
        : <String>[];
    final images = sources.take(10).toList();
    if (images.isEmpty) return const SizedBox.shrink();

    final chatColors = _chatThemeFromAppTheme(theme).colors;
    // Same as text bubbles: mine = primary, other = surfaceContainer
    final bubbleColor = isMine ? chatColors.primary : chatColors.surfaceContainer;
    final textColor = isMine ? chatColors.onPrimary : chatColors.onSurface;
    final replySnippet = message.metadata?['replySnippet'] as String?;
    final caption = message.metadata?['caption'] as String?;
    final totalCount = sources.length;
    final overlayN = totalCount > 10 ? totalCount - 10 : null;
    final hasCaption = caption != null && caption.isNotEmpty;

    final timeWidget = _MessageTime(
      createdAt: message.createdAt ?? DateTime.now(),
      inline: true,
      color: textColor.withValues(alpha: 0.7),
    );
    final timeOverPhoto = _MessageTime(
      createdAt: message.createdAt ?? DateTime.now(),
      inline: true,
      color: Colors.white,
    );

    return Container(
      constraints: BoxConstraints(maxWidth: messageWidth.clamp(0, _kAlbumMaxWidth)),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(_kBubbleRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replySnippet != null && replySnippet.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: isMine ? chatColors.onPrimary : chatColors.primary, width: 3)),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(_kBubbleRadius)),
              ),
              child: Text(
                replySnippet,
                style: theme.textTheme.bodySmall?.copyWith(color: textColor.withValues(alpha: 0.85)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.all(_kAlbumSpacing),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) => _buildGrid(context, images, overlayN, constraints.maxWidth),
                ),
                // When no caption: time at bottom-right of the photo grid (slight bg for readability)
                if (!hasCaption)
                  Positioned(
                    bottom: 4,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: timeOverPhoto,
                    ),
                  ),
              ],
            ),
          ),
          if (hasCaption)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: textColor.withValues(alpha: 0.12), width: 1)),
                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(_kBubbleRadius), bottomRight: Radius.circular(_kBubbleRadius)),
              ),
              child: Text(
                caption,
                style: theme.textTheme.bodyMedium?.copyWith(color: textColor, height: 1.35),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          // When has caption: time row below caption
          if (hasCaption)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [timeWidget],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context, List<String> images, int? overlayN, double maxW) {
    final n = images.length;
    if (n == 1) return _buildSingle(images, overlayN, maxW);
    if (n == 2) return _build2(images, maxW);
    if (n == 3) return _build3(images, maxW);
    if (n == 4) return _build4(images, maxW);
    return _buildMulti(images, overlayN, maxW);
  }

  Widget _buildSingle(List<String> images, int? overlayN, double maxW) {
    return _albumTile(
      images, 0, maxW, 200,
      BorderRadius.circular(_kAlbumRadius - _kAlbumSpacing),
      overlayPlusN: overlayN,
      onImageTap: onImageTap,
    );
  }

  Widget _build2(List<String> images, double maxW) {
    final w = (maxW - _kAlbumSpacing) / 2;
    return Row(
      children: [
        _albumTile(images, 0, w, 150, const BorderRadius.horizontal(left: Radius.circular(_kAlbumRadius - _kAlbumSpacing)), onImageTap: onImageTap),
        SizedBox(width: _kAlbumSpacing),
        _albumTile(images, 1, w, 150, const BorderRadius.horizontal(right: Radius.circular(_kAlbumRadius - _kAlbumSpacing)), onImageTap: onImageTap),
      ],
    );
  }

  Widget _build3(List<String> images, double maxW) {
    final contentW = maxW - _kAlbumSpacing;
    final bigW = contentW * 2 / 3;
    final smallW = contentW / 3;
    final smallH = (200 - _kAlbumSpacing) / 2;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _albumTile(images, 0, bigW, 200, const BorderRadius.only(topLeft: Radius.circular(_kAlbumRadius - _kAlbumSpacing), bottomLeft: Radius.circular(_kAlbumRadius - _kAlbumSpacing)), onImageTap: onImageTap),
        SizedBox(width: _kAlbumSpacing),
        Column(
          children: [
            _albumTile(images, 1, smallW, smallH, const BorderRadius.only(topRight: Radius.circular(_kAlbumRadius - _kAlbumSpacing)), onImageTap: onImageTap),
            SizedBox(height: _kAlbumSpacing),
            _albumTile(images, 2, smallW, smallH, const BorderRadius.only(bottomRight: Radius.circular(_kAlbumRadius - _kAlbumSpacing)), onImageTap: onImageTap),
          ],
        ),
      ],
    );
  }

  Widget _build4(List<String> images, double maxW) {
    final cell = (maxW - _kAlbumSpacing) / 2;
    return Column(
      children: [
        Row(
          children: [
            _albumTile(images, 0, cell, 140, const BorderRadius.only(topLeft: Radius.circular(_kAlbumRadius - _kAlbumSpacing)), onImageTap: onImageTap),
            SizedBox(width: _kAlbumSpacing),
            _albumTile(images, 1, cell, 140, const BorderRadius.only(topRight: Radius.circular(_kAlbumRadius - _kAlbumSpacing)), onImageTap: onImageTap),
          ],
        ),
        SizedBox(height: _kAlbumSpacing),
        Row(
          children: [
            _albumTile(images, 2, cell, 140, const BorderRadius.only(bottomLeft: Radius.circular(_kAlbumRadius - _kAlbumSpacing)), onImageTap: onImageTap),
            SizedBox(width: _kAlbumSpacing),
            _albumTile(images, 3, cell, 140, const BorderRadius.only(bottomRight: Radius.circular(_kAlbumRadius - _kAlbumSpacing)), onImageTap: onImageTap),
          ],
        ),
      ],
    );
  }

  Widget _buildMulti(List<String> images, int? overlayN, double maxW) {
    final firstRowCount = images.length % 3 == 0 ? 3 : 2;
    final rows = <Widget>[];
    var idx = 0;
    final cellW = (maxW - _kAlbumSpacing * 2) / 3;
    final cellH = 90.0;

    final firstRow = <Widget>[];
    for (var i = 0; i < firstRowCount; i++) {
      final isLast = (idx == 9 && overlayN != null);
      firstRow.add(Expanded(
        child: Padding(
          padding: EdgeInsets.only(left: i > 0 ? _kAlbumSpacing : 0),
          child: _albumTile(images, idx, cellW, cellH, BorderRadius.circular(6), overlayPlusN: isLast ? overlayN : null, onImageTap: onImageTap),
        ),
      ));
      idx++;
    }
    rows.add(Row(children: firstRow));

    while (idx < images.length) {
      final rowChildren = <Widget>[];
      for (var c = 0; c < 3 && idx < images.length; c++) {
        final isLast = (idx == 9 && overlayN != null);
        rowChildren.add(Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: c > 0 ? _kAlbumSpacing : 0),
            child: _albumTile(images, idx, cellW, cellH, BorderRadius.circular(6), overlayPlusN: isLast ? overlayN : null, onImageTap: onImageTap),
          ),
        ));
        idx++;
      }
      rows.add(Padding(padding: EdgeInsets.only(top: _kAlbumSpacing), child: Row(children: rowChildren)));
    }

    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

void _openPhotoGallery(BuildContext context, List<String> sources, int initialIndex) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (ctx) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            PhotoViewGallery.builder(
              itemCount: sources.length,
              pageController: PageController(initialPage: initialIndex),
              builder: (context, index) {
                final path = sources[index];
                final ImageProvider provider = isLocalFileSource(path)
                    ? FileImage(File(path))
                    : NetworkImage(path);
                return PhotoViewGalleryPageOptions(
                  imageProvider: provider,
                  minScale: PhotoViewComputedScale.contained * 0.5,
                  maxScale: PhotoViewComputedScale.covered * 3,
                );
              },
            ),
            Positioned(
              top: MediaQuery.paddingOf(ctx).top + 8,
              left: 8,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(24),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 22),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _EmptyChatPlaceholder extends StatelessWidget {
  const _EmptyChatPlaceholder({required this.theme, required this.colorScheme});

  final ThemeData theme;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.primary.withValues(alpha: 0.15),
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 36,
                color: colorScheme.primary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Напишите сообщение или прикрепите фото',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.8),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
