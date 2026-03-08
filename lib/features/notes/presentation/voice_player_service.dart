import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Singleton service for playing voice messages: one active at a time, seek, speed.
class VoicePlayerService extends ChangeNotifier {
  VoicePlayerService._();
  static VoicePlayerService? _instance;
  static VoicePlayerService get instance {
    if (_instance == null) {
      _instance = VoicePlayerService._();
      _instance!._init();
    }
    return _instance!;
  }

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;

  String? _activeMessageId;
  Duration _position = Duration.zero;
  Duration? _duration;
  double _speed = 1.0;
  static const List<double> _speeds = [1.0, 1.5, 2.0];

  String? get activeMessageId => _activeMessageId;
  Duration get position => _position;
  Duration? get duration => _duration;
  double get speed => _speed;
  bool get isPlaying => _player.playing;

  double get progress {
    final d = _duration;
    if (d == null || d.inMilliseconds <= 0) return 0.0;
    return (_position.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0);
  }

  bool isActive(String messageId) => _activeMessageId == messageId;
  bool isPlayingMessage(String messageId) => _activeMessageId == messageId && _player.playing;

  void _init() {
    _positionSub = _player.positionStream.listen((p) {
      _position = p;
      notifyListeners();
    });
    _durationSub = _player.durationStream.listen((d) {
      _duration = d;
      notifyListeners();
    });
    _stateSub = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _activeMessageId = null;
        _position = Duration.zero;
        notifyListeners();
      } else {
        notifyListeners();
      }
    });
  }

  Future<void> play({required String messageId, required String path}) async {
    if (_activeMessageId == messageId && _player.playing) return;
    if (_activeMessageId != messageId) {
      await _player.setFilePath(path);
      _activeMessageId = messageId;
      _duration = _player.duration;
    }
    await _player.setSpeed(_speed);
    await _player.play();
    notifyListeners();
  }

  Future<void> pause() async {
    await _player.pause();
    notifyListeners();
  }

  Future<void> resume() async {
    await _player.play();
    notifyListeners();
  }

  Future<void> seek(double fraction) async {
    final d = _duration ?? _player.duration;
    if (d == null) return;
    final ms = (d.inMilliseconds * fraction.clamp(0.0, 1.0)).round();
    await _player.seek(Duration(milliseconds: ms));
    notifyListeners();
  }

  void toggleSpeed() {
    final idx = _speeds.indexOf(_speed);
    _speed = _speeds[(idx + 1) % _speeds.length];
    _player.setSpeed(_speed);
    notifyListeners();
  }

  void setDurationMs(int ms) {
    _duration = Duration(milliseconds: ms);
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _stateSub?.cancel();
    await _player.dispose();
    super.dispose();
  }
}
