import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Мини-игра «Реакция»: жди зелёный — жми как можно быстрее.
/// Рекорд (минимальное время в мс) хранится в SharedPreferences.
class ReactionPage extends StatefulWidget {
  const ReactionPage({super.key});

  @override
  State<ReactionPage> createState() => _ReactionPageState();
}

enum _Phase { idle, waiting, go, tooEarly, result }

class _ReactionPageState extends State<ReactionPage> {
  static const _kBestKey = 'reaction_best_ms';

  _Phase _phase = _Phase.idle;
  Timer? _timer;
  DateTime? _goAt;
  int? _lastMs;
  int? _bestMs;
  final _rand = Random();

  @override
  void initState() {
    super.initState();
    _loadBest();
  }

  Future<void> _loadBest() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _bestMs = prefs.getInt(_kBestKey));
  }

  Future<void> _saveBest(int ms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kBestKey, ms);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    HapticFeedback.selectionClick();
    _timer?.cancel();
    setState(() {
      _phase = _Phase.waiting;
      _lastMs = null;
    });
    _timer = Timer(
      Duration(milliseconds: 1000 + _rand.nextInt(3000)),
      () {
        if (!mounted) return;
        setState(() {
          _phase = _Phase.go;
          _goAt = DateTime.now();
        });
      },
    );
  }

  void _tap() {
    switch (_phase) {
      case _Phase.idle:
      case _Phase.tooEarly:
      case _Phase.result:
        _start();
      case _Phase.waiting:
        HapticFeedback.heavyImpact();
        _timer?.cancel();
        setState(() => _phase = _Phase.tooEarly);
      case _Phase.go:
        final ms = DateTime.now().difference(_goAt!).inMilliseconds;
        HapticFeedback.lightImpact();
        final isRecord = _bestMs == null || ms < _bestMs!;
        setState(() {
          _lastMs = ms;
          _phase = _Phase.result;
          if (isRecord) _bestMs = ms;
        });
        if (isRecord) _saveBest(ms);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final (Color bg, String title, String subtitle) = switch (_phase) {
      _Phase.idle => (
          cs.surface,
          'Реакция',
          'Нажми, чтобы начать.\nЖди зелёный — и жми!',
        ),
      _Phase.waiting => (
          const Color(0xFFB3402F),
          'Жди…',
          'Не торопись',
        ),
      _Phase.go => (
          const Color(0xFF2E9E4F),
          'ЖМИ!',
          '',
        ),
      _Phase.tooEarly => (
          const Color(0xFF8A6D1D),
          'Рано!',
          'Зелёного ещё не было.\nНажми, чтобы попробовать снова',
        ),
      _Phase.result => (
          cs.surface,
          '${_lastMs ?? 0} мс',
          _lastMs != null && _lastMs == _bestMs
              ? 'Новый рекорд! Нажми, чтобы повторить'
              : 'Нажми, чтобы попробовать ещё',
        ),
    };

    final onBg = bg == cs.surface ? cs.onSurface : Colors.white;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Реакция'),
        actions: [
          if (_bestMs != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  'Рекорд: $_bestMs мс',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _tap(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: bg == cs.surface ? cs.primary.withAlpha(14) : bg,
            borderRadius: BorderRadius.circular(24),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.displaySmall?.copyWith(
                  color: onBg,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: onBg.withAlpha(200),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
