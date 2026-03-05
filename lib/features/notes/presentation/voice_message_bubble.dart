import "dart:async";

import "package:flutter/material.dart";
import "package:just_audio/just_audio.dart";

class VoiceMessageBubble extends StatefulWidget {
  const VoiceMessageBubble({
    super.key,
    required this.path,
    required this.durationSeconds,
    required this.isSentByMe,
  });

  final String path;
  final int durationSeconds;
  final bool isSentByMe;

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;

  @override
  void initState() {
    super.initState();
    _stateSub = _player.playerStateStream.listen((state) {
      if (mounted) setState(() {});
    });
    _positionSub = _player.positionStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      if (_player.processingState == ProcessingState.idle ||
          _player.processingState == ProcessingState.completed) {
        await _player.setFilePath(widget.path);
      }
      await _player.play();
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return "${m}:${s.toString().padLeft(2, "0")}";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final position = _player.position;
    final duration = _player.duration ?? Duration(seconds: widget.durationSeconds);
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;
    final isPlaying = _player.playing;

    final bgColor = widget.isSentByMe ? cs.primary : cs.surfaceContainerHighest;
    final fgColor = widget.isSentByMe ? cs.onPrimary : cs.onSurface;

    return Semantics(
      label: "Голосовое сообщение ${_formatDuration(duration)}",
      button: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Align(
        alignment: widget.isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Material(
          color: bgColor,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: fgColor,
                    size: 28,
                  ),
                  onPressed: _togglePlay,
                  style: IconButton.styleFrom(
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 120,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 4,
                        child: LinearProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          backgroundColor: fgColor.withValues(alpha: 0.2),
                          valueColor: AlwaysStoppedAnimation<Color>(fgColor),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${_formatDuration(position)} / ${_formatDuration(duration)}",
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: fgColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
