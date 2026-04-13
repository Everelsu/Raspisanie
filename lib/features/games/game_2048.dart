import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class Game2048Page extends StatefulWidget {
  const Game2048Page({super.key});

  @override
  State<Game2048Page> createState() => _Game2048PageState();
}

class _Game2048PageState extends State<Game2048Page> {
  static const _size = 4;

  late List<List<int>> _grid;
  int _score = 0;
  int _best = 0;
  bool _won = false;
  bool _over = false;
  bool _continueAfterWin = false;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _newGame();
  }

  void _newGame() {
    _grid = List.generate(_size, (_) => List.filled(_size, 0));
    _score = 0;
    _won = false;
    _over = false;
    _continueAfterWin = false;
    _addTile();
    _addTile();
  }

  void _addTile() {
    final empty = <(int, int)>[];
    for (var r = 0; r < _size; r++) {
      for (var c = 0; c < _size; c++) {
        if (_grid[r][c] == 0) empty.add((r, c));
      }
    }
    if (empty.isEmpty) return;
    final pos = empty[_rng.nextInt(empty.length)];
    _grid[pos.$1][pos.$2] = _rng.nextDouble() < 0.9 ? 2 : 4;
  }

  (List<int>, int) _slideRow(List<int> row) {
    final tiles = row.where((v) => v != 0).toList();
    var pts = 0;
    var i = 0;
    while (i < tiles.length - 1) {
      if (tiles[i] == tiles[i + 1]) {
        tiles[i] *= 2;
        pts += tiles[i];
        tiles.removeAt(i + 1);
      }
      i++;
    }
    while (tiles.length < _size) {
      tiles.add(0);
    }
    return (tiles, pts);
  }

  bool _move(int dr, int dc) {
    final prev = _grid.map((r) => List<int>.from(r)).toList();
    var pts = 0;

    if (dr == 0) {
      for (var r = 0; r < _size; r++) {
        var row = List<int>.from(_grid[r]);
        if (dc == 1) row = row.reversed.toList();
        final (slid, p) = _slideRow(row);
        pts += p;
        _grid[r] = dc == 1 ? slid.reversed.toList() : slid;
      }
    } else {
      for (var c = 0; c < _size; c++) {
        var col = List.generate(_size, (r) => _grid[r][c]);
        if (dr == 1) col = col.reversed.toList();
        final (slid, p) = _slideRow(col);
        pts += p;
        final result = dr == 1 ? slid.reversed.toList() : slid;
        for (var r = 0; r < _size; r++) {
          _grid[r][c] = result[r];
        }
      }
    }

    var changed = false;
    outer:
    for (var r = 0; r < _size; r++) {
      for (var c = 0; c < _size; c++) {
        if (_grid[r][c] != prev[r][c]) { changed = true; break outer; }
      }
    }
    if (!changed) return false;

    _score += pts;
    if (_score > _best) _best = _score;
    _addTile();

    if (!_won && !_continueAfterWin) {
      outer2:
      for (var r = 0; r < _size; r++) {
        for (var c = 0; c < _size; c++) {
          if (_grid[r][c] == 2048) { _won = true; break outer2; }
        }
      }
    }
    _over = _isGameOver();
    return true;
  }

  bool _isGameOver() {
    for (var r = 0; r < _size; r++) {
      for (var c = 0; c < _size; c++) {
        if (_grid[r][c] == 0) return false;
        if (r + 1 < _size && _grid[r][c] == _grid[r + 1][c]) return false;
        if (c + 1 < _size && _grid[r][c] == _grid[r][c + 1]) return false;
      }
    }
    return true;
  }

  void _onPanEnd(DragEndDetails d) {
    final vel = d.velocity.pixelsPerSecond;
    if (vel.distance < 80) return;
    int dr = 0, dc = 0;
    if (vel.dx.abs() > vel.dy.abs()) {
      dc = vel.dx > 0 ? 1 : -1;
    } else {
      dr = vel.dy > 0 ? 1 : -1;
    }
    setState(() => _move(dr, dc));
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('🎮 2048'),
            const Spacer(),
            _ScoreBadge(label: 'СЧЁТ', value: _score, accent: accent, theme: theme),
            const SizedBox(width: 8),
            _ScoreBadge(label: 'РЕКОРД', value: _best, accent: accent, theme: theme),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Новая игра',
            onPressed: () {
              HapticFeedback.mediumImpact();
              setState(_newGame);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: GestureDetector(
                  onPanEnd: _onPanEnd,
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: _GridWidget(grid: _grid, theme: theme),
                  ),
                ),
              ),
            ),
            if (_won && !_continueAfterWin)
              _Overlay(
                emoji: '🏆',
                title: 'Победа!',
                subtitle: 'Ты достиг 2048!',
                actions: [
                  TextButton(
                    onPressed: () => setState(() => _continueAfterWin = true),
                    child: const Text('Продолжить'),
                  ),
                  ElevatedButton(
                    onPressed: () { HapticFeedback.mediumImpact(); setState(_newGame); },
                    child: const Text('Заново'),
                  ),
                ],
              ),
            if (_over && !(_won && !_continueAfterWin))
              _Overlay(
                emoji: '😵',
                title: 'Игра окончена',
                subtitle: 'Счёт: $_score',
                actions: [
                  ElevatedButton(
                    onPressed: () { HapticFeedback.mediumImpact(); setState(_newGame); },
                    child: const Text('Заново'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _GridWidget extends StatelessWidget {
  const _GridWidget({required this.grid, required this.theme});
  final List<List<int>> grid;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFBBADA0);
    return Container(
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          for (var r = 0; r < 4; r++) ...[
            if (r > 0) const SizedBox(height: 8),
            Expanded(
              child: Row(
                children: [
                  for (var c = 0; c < 4; c++) ...[
                    if (c > 0) const SizedBox(width: 8),
                    Expanded(child: _Tile(value: grid[r][c], isDark: isDark)),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.value, required this.isDark});
  final int value;
  final bool isDark;

  static Color _bg(int v, bool dark) {
    if (v == 0) return dark ? const Color(0xFF3A3A3C) : const Color(0xFFCDC1B4);
    return switch (v) {
      2    => dark ? const Color(0xFF4A4A4C) : const Color(0xFFEEE4DA),
      4    => dark ? const Color(0xFF5A4A3C) : const Color(0xFFEDE0C8),
      8    => const Color(0xFFF2B179),
      16   => const Color(0xFFF59563),
      32   => const Color(0xFFF67C5F),
      64   => const Color(0xFFF65E3B),
      128  => const Color(0xFFEDCF72),
      256  => const Color(0xFFEDCC61),
      512  => const Color(0xFFEDC850),
      1024 => const Color(0xFF4CAF50),
      2048 => const Color(0xFF9C27B0),
      _    => const Color(0xFF212121),
    };
  }

  static Color _fg(int v, bool dark) {
    if (v == 0) return Colors.transparent;
    if (v <= 4) return dark ? Colors.white70 : const Color(0xFF776E65);
    return Colors.white;
  }

  static double _fs(int v) => v >= 1000 ? 18 : v >= 100 ? 22 : 26;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      decoration: BoxDecoration(
        color: _bg(value, isDark),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: value == 0
            ? null
            : Text(
                '$value',
                style: TextStyle(
                  color: _fg(value, isDark),
                  fontSize: _fs(value),
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.label, required this.value, required this.accent, required this.theme});
  final String label;
  final int value;
  final Color accent;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withAlpha(28),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: theme.textTheme.labelSmall?.copyWith(fontSize: 9)),
          Text('$value', style: TextStyle(fontWeight: FontWeight.bold, color: accent)),
        ],
      ),
    );
  }
}

class _Overlay extends StatelessWidget {
  const _Overlay({required this.emoji, required this.title, required this.subtitle, required this.actions});
  final String emoji;
  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: Colors.black.withAlpha(140),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    actions[i],
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
