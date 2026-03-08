import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../data/message.dart' as app;

const String _kCurrentUserId = 'me';

/// Converts our app messages to flyer messages.
/// Input order is preserved (передавайте [oldest first] для корректного отображения в Chat).
/// One app message can expand to multiple flyer messages (text, images, voice).
List<Message> appMessagesToFlyer(List<app.Message> appMessages) {
  final list = <Message>[];
  for (final m in appMessages) {
    final meta = <String, dynamic>{'ourMessageId': m.id};
    final authorId = _kCurrentUserId;
    final createdAt = m.createdAt.toUtc();
    /// First part of replied message is always _t in our convention.
    final replyToMessageId = m.replyToId != null ? '${m.replyToId}_t' : null;

    if (m.content != null && m.content!.trim().isNotEmpty) {
      list.add(TextMessage(
        id: '${m.id}_t',
        authorId: authorId,
        replyToMessageId: replyToMessageId,
        createdAt: createdAt,
        sentAt: null,
        text: m.content!,
        metadata: Map.from(meta),
      ));
    }

    final images = m.mediaFiles.where((e) => e.type == 'image').toList();
    if (images.length > 1) {
      // Альбом: до 10 фото в одном bubble; если больше 10 — следующие в следующее сообщение (chunk по 10)
      const maxPerAlbum = 10;
      for (var start = 0; start < images.length; start += maxPerAlbum) {
        final chunk = images.skip(start).take(maxPerAlbum).map((e) => e.localPath).toList();
        final albumMeta = Map<String, dynamic>.from(meta)
          ..['type'] = 'album'
          ..['sources'] = chunk;
        if (start == 0 && m.content != null && m.content!.trim().isNotEmpty) {
          albumMeta['caption'] = m.content!.trim();
        }
        if (start == 0 && m.replyToId != null) {
          albumMeta['replySnippet'] = m.replyToMessage?.content?.trim().isNotEmpty == true
              ? (m.replyToMessage!.content!.length > 40 ? '${m.replyToMessage!.content!.substring(0, 40)}...' : m.replyToMessage!.content)
              : 'Фото';
        }
        list.add(Message.custom(
          id: '${m.id}_album$start',
          authorId: authorId,
          replyToMessageId: replyToMessageId,
          createdAt: createdAt,
          sentAt: null,
          metadata: albumMeta,
        ));
      }
    } else if (images.length == 1) {
      list.add(ImageMessage(
        id: '${m.id}_i0',
        authorId: authorId,
        replyToMessageId: replyToMessageId,
        createdAt: createdAt,
        sentAt: null,
        source: images[0].localPath,
        text: (m.content != null && m.content!.trim().isNotEmpty) ? m.content!.trim() : null,
        metadata: Map.from(meta),
      ));
    }

    final voice = m.mediaFiles.where((e) => e.type == 'voice').toList();
    if (voice.isNotEmpty) {
      list.add(AudioMessage(
        id: '${m.id}_v',
        authorId: authorId,
        replyToMessageId: replyToMessageId,
        createdAt: createdAt,
        sentAt: null,
        source: voice.first.localPath,
        duration: const Duration(seconds: 0),
        metadata: Map.from(meta),
      ));
    }

    if (list.isEmpty) {
      list.add(TextMessage(
        id: '${m.id}_t',
        authorId: authorId,
        replyToMessageId: replyToMessageId,
        createdAt: createdAt,
        sentAt: null,
        text: ' ',
        metadata: Map.from(meta),
      ));
    }
  }
  return list;
}

/// Returns the app message id for a flyer message (from metadata or id prefix).
String ourMessageIdFromFlyer(Message fm) {
  final meta = fm.metadata;
  if (meta != null && meta['ourMessageId'] != null) {
    return meta['ourMessageId'] as String;
  }
  final id = fm.id;
  if (id.contains('_t') || id.contains('_i') || id.contains('_v') || id.contains('_album')) {
    return id.replaceAll(RegExp(r'_(t|i\d+|v|album\d*)$'), '');
  }
  return id;
}

String get currentUserId => _kCurrentUserId;

/// Whether [source] is a local file path (not http/https URL).
bool isLocalFileSource(String source) {
  return source.startsWith('/') ||
      (!source.startsWith('http://') && !source.startsWith('https://'));
}

/// Первый flyer message id для скролла к сообщению (текст → _t, одно фото → _i0, альбом → _album0, голос → _v).
String firstFlyerMessageId(app.Message m) {
  if (m.content != null && m.content!.trim().isNotEmpty) return '${m.id}_t';
  final images = m.mediaFiles.where((e) => e.type == 'image').toList();
  if (images.length > 1) return '${m.id}_album0';
  if (images.length == 1) return '${m.id}_i0';
  final voice = m.mediaFiles.where((e) => e.type == 'voice').toList();
  if (voice.isNotEmpty) return '${m.id}_v';
  return '${m.id}_t';
}
