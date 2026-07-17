import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Position encoded as x * 1000 + y (grid ≤ 999 in each dimension)
int _enc(int x, int y) => x * 1000 + y;
int _decX(int v) => v ~/ 1000;
int _decY(int v) => v % 1000;

class SnakePage extends StatefulWidget {
  const SnakePage({super.key});

  @override
  State<SnakePage> createState() => _SnakePageState();
}

class _SnakePageState extends State<SnakePage> with WidgetsBindingObserver {
  static const int kCols = 22;
  static const int kRows = 30;
  static const String _kBestKey = 'snake_best_score';

  /// Скорость растёт со счётом: 140 мс на старте, минимум 75 мс.
  Duration get _tickDuration =>
      Duration(milliseconds: (140 - _score * 3).clamp(75, 140));

  int _dirX = 1, _dirY = 0;
  int _pendingDirX = 1, _pendingDirY = 0;
  late List<int> _snake;
  late int _food;
  int _score = 0;
  int _best = 0;
  bool _gameOver = false;
  bool _started = false;
  bool _paused = false;
  Timer? _timer;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBest();
    _initGame();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _started && !_gameOver) {
      _pause();
    }
  }

  Future<void> _loadBest() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _best = prefs.getInt(_kBestKey) ?? 0);
  }

  Future<void> _saveBest(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kBestKey, value);
  }

  void _initGame() {
    _timer?.cancel();
    final int sx = kCols ~/ 2, sy = kRows ~/ 2;
    _snake = [_enc(sx, sy), _enc(sx - 1, sy), _enc(sx - 2, sy)];
    _dirX = 1; _dirY = 0;
    _pendingDirX = 1; _pendingDirY = 0;
    _score = 0;
    _gameOver = false;
    _started = false;
    _paused = false;
    _spawnFood();
  }

  void _startGame() {
    _started = true;
    _paused = false;
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_tickDuration, (_) => _tick());
  }

  void _pause() {
    if (!_started || _gameOver) return;
    _timer?.cancel();
    setState(() => _paused = true);
  }

  void _resume() {
    if (!_paused) return;
    setState(() => _paused = false);
    _restartTimer();
  }

  void _togglePause() {
    if (_paused) {
      _resume();
    } else {
      _pause();
    }
  }

  void _spawnFood() {
    final Set<int> occupied = _snake.toSet();
    final List<int> empty = [];
    for (int x = 0; x < kCols; x++) {
      for (int y = 0; y < kRows; y++) {
        final int p = _enc(x, y);
        if (!occupied.contains(p)) empty.add(p);
      }
    }
    if (empty.isEmpty) return;
    _food = empty[_rng.nextInt(empty.length)];
  }

  void _tick() {
    if (_gameOver || _paused) return;
    _dirX = _pendingDirX;
    _dirY = _pendingDirY;
    final int hx = _decX(_snake.first), hy = _decY(_snake.first);
    final int nx = hx + _dirX, ny = hy + _dirY;

    if (nx < 0 || nx >= kCols || ny < 0 || ny >= kRows) {
      _triggerGameOver();
      return;
    }
    final int newHead = _enc(nx, ny);
    for (int i = 0; i < _snake.length - 1; i++) {
      if (_snake[i] == newHead) { _triggerGameOver(); return; }
    }

    setState(() {
      _snake.insert(0, newHead);
      if (newHead == _food) {
        _score++;
        HapticFeedback.lightImpact();
        if (_score > _best) {
          _best = _score;
          _saveBest(_best);
        }
        _spawnFood();
        // Змейка ускоряется с каждым съеденным яблоком.
        _restartTimer();
      } else {
        _snake.removeLast();
      }
    });
  }

  void _triggerGameOver() {
    _timer?.cancel();
    HapticFeedback.heavyImpact();
    setState(() => _gameOver = true);
  }

  void _changeDirection(int dx, int dy) {
    if (dx == -_dirX && dy == -_dirY) return;
    if (_paused) return;
    if (!_started && !_gameOver) {
      _pendingDirX = dx; _pendingDirY = dy;
      setState(() => _startGame());
      return;
    }
    _pendingDirX = dx;
    _pendingDirY = dy;
  }

  // Свайп срабатывает сразу по порогу движения (18px), а не в конце жеста:
  // поворот применяется мгновенно, управление не «запаздывает».
  Offset _panDelta = Offset.zero;
  bool _panConsumed = false;

  void _onPanStart(DragStartDetails d) {
    _panDelta = Offset.zero;
    _panConsumed = false;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_panConsumed) return;
    _panDelta += d.delta;
    if (_panDelta.distance < 18) return;
    _panConsumed = true;
    HapticFeedback.selectionClick();
    if (_panDelta.dx.abs() > _panDelta.dy.abs()) {
      _changeDirection(_panDelta.dx > 0 ? 1 : -1, 0);
    } else {
      _changeDirection(0, _panDelta.dy > 0 ? 1 : -1);
    }
  }

  void _restart() => setState(_initGame);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('🐍 Змейка'),
        centerTitle: false,
        actions: [
          // Score display
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Счёт: $_score',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Рекорд: $_best',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          // Pause / new game
          if (_started && !_gameOver)
            IconButton(
              icon: Icon(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
              tooltip: _paused ? 'Продолжить' : 'Пауза',
              onPressed: _togglePause,
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Заново',
            onPressed: _restart,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onTap: () {
                if (_paused) { _resume(); return; }
                if (!_started && !_gameOver) _startGame();
              },
              child: Stack(
                children: [
                  LayoutBuilder(builder: (ctx, constraints) {
                    return CustomPaint(
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                      painter: _SnakePainter(
                        snake: _snake,
                        food: _food,
                        cols: kCols,
                        rows: kRows,
                        dirX: _dirX,
                        dirY: _dirY,
                        primaryColor: cs.primary,
                        backgroundColor: theme.scaffoldBackgroundColor,
                        colorScheme: cs,
                      ),
                    );
                  }),
                  // "Tap to start" overlay
                  if (!_started && !_gameOver)
                    Center(
                      child: _InfoOverlay(
                        theme: theme,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🐍', style: TextStyle(fontSize: 52)),
                            const SizedBox(height: 10),
                            Text(
                              'Змейка',
                              style: theme.textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Проведи пальцем или нажми\nстрелку для старта',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Pause overlay
                  if (_paused)
                    Center(
                      child: _InfoOverlay(
                        theme: theme,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.pause_circle_rounded,
                                size: 52, color: cs.primary),
                            const SizedBox(height: 10),
                            Text(
                              'Пауза',
                              style: theme.textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Нажми ▶ или проведи пальцем',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Game over overlay
                  if (_gameOver)
                    Center(
                      child: _InfoOverlay(
                        theme: theme,
                        elevated: true,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('💀', style: TextStyle(fontSize: 52)),
                            const SizedBox(height: 10),
                            Text(
                              'Игра окончена',
                              style: theme.textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Счёт: $_score',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(color: cs.primary),
                            ),
                            if (_score > 0 && _score == _best) ...[
                              const SizedBox(height: 4),
                              Text(
                                '🏆 Новый рекорд!',
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: cs.primary),
                              ),
                            ],
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: _restart,
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('Заново'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          _ArrowPad(onDirection: _changeDirection, theme: theme),
        ],
      ),
    );
  }
}

// ── Overlays ──────────────────────────────────────────────────────────────────

class _InfoOverlay extends StatelessWidget {
  const _InfoOverlay({
    required this.theme,
    required this.child,
    this.elevated = false,
  });
  final ThemeData theme;
  final Widget child;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 48),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withAlpha(elevated ? 240 : 220),
        borderRadius: BorderRadius.circular(20),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: Colors.black.withAlpha(70),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

// ── Arrow pad ─────────────────────────────────────────────────────────────────

class _ArrowPad extends StatelessWidget {
  const _ArrowPad({required this.onDirection, required this.theme});
  final void Function(int dx, int dy) onDirection;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    const double s = 52.0;
    return Container(
      color: theme.colorScheme.surface,
      padding: EdgeInsets.only(
        top: 8,
        bottom: MediaQuery.paddingOf(context).bottom + 8,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ABtn(icon: Icons.keyboard_arrow_up, onTap: () => onDirection(0, -1), size: s, theme: theme),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ABtn(icon: Icons.keyboard_arrow_left, onTap: () => onDirection(-1, 0), size: s, theme: theme),
                  SizedBox(width: s + 8),
                  _ABtn(icon: Icons.keyboard_arrow_right, onTap: () => onDirection(1, 0), size: s, theme: theme),
                ],
              ),
              _ABtn(icon: Icons.keyboard_arrow_down, onTap: () => onDirection(0, 1), size: s, theme: theme),
            ],
          ),
        ],
      ),
    );
  }
}

class _ABtn extends StatelessWidget {
  const _ABtn({
    required this.icon,
    required this.onTap,
    required this.size,
    required this.theme,
  });
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: size,
        height: size,
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withAlpha(22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.primary.withAlpha(60),
            width: 1.5,
          ),
        ),
        child: Icon(icon, color: theme.colorScheme.primary, size: 30),
      ),
    );
  }
}

// ── Painter ───────────────────────────────────────────────────────────────────

class _SnakePainter extends CustomPainter {
  const _SnakePainter({
    required this.snake,
    required this.food,
    required this.cols,
    required this.rows,
    required this.dirX,
    required this.dirY,
    required this.primaryColor,
    required this.backgroundColor,
    required this.colorScheme,
  });

  final List<int> snake;
  final int food;
  final int cols, rows;
  final int dirX, dirY;
  final Color primaryColor;
  final Color backgroundColor;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final double cellW = size.width / cols;
    final double cellH = size.height / rows;
    final double cell = cellW < cellH ? cellW : cellH;
    final double ox = (size.width - cell * cols) / 2;
    final double oy = (size.height - cell * rows) / 2;

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = backgroundColor,
    );

    // Grid
    final gridPaint = Paint()
      ..color = colorScheme.onSurface.withAlpha(14)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    for (int x = 0; x <= cols; x++) {
      canvas.drawLine(
          Offset(ox + x * cell, oy), Offset(ox + x * cell, oy + rows * cell), gridPaint);
    }
    for (int y = 0; y <= rows; y++) {
      canvas.drawLine(
          Offset(ox, oy + y * cell), Offset(ox + cols * cell, oy + y * cell), gridPaint);
    }

    // Food
    final int fx = _decX(food), fy = _decY(food);
    final Offset fc = Offset(ox + fx * cell + cell / 2, oy + fy * cell + cell / 2);
    final double fr = cell * 0.38;
    canvas.drawCircle(fc, fr + 3, Paint()..color = Colors.red.withAlpha(50));
    canvas.drawCircle(fc, fr, Paint()..color = const Color(0xFFE53935));
    canvas.drawCircle(
      fc - Offset(fr * 0.25, fr * 0.25),
      fr * 0.28,
      Paint()..color = Colors.white.withAlpha(180),
    );

    // Snake
    final int len = snake.length;
    for (int i = len - 1; i >= 0; i--) {
      final int sx = _decX(snake[i]), sy = _decY(snake[i]);
      final double t = len > 1 ? i / (len - 1) : 0.0;
      final Color seg = i == 0
          ? primaryColor
          : Color.lerp(primaryColor, primaryColor.withAlpha(120), t)!;
      final double r = cell * 0.3;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(ox + sx * cell + 1.5, oy + sy * cell + 1.5, cell - 3, cell - 3),
          Radius.circular(r),
        ),
        Paint()..color = seg,
      );
      if (i == 0) {
        _drawEyes(canvas, ox + sx * cell, oy + sy * cell, cell);
      }
    }
  }

  void _drawEyes(Canvas canvas, double x, double y, double cell) {
    final double er = cell * 0.10;
    final Paint eye = Paint()..color = Colors.white;
    final Paint pupil = Paint()..color = Colors.black;

    // Offset eyes based on direction
    final double eyePerpX = dirY.toDouble();   // perpendicular to movement
    final double eyePerpY = -dirX.toDouble();
    final double cx = x + cell / 2 + dirX * cell * 0.15;
    final double cy = y + cell / 2 + dirY * cell * 0.15;
    final Offset e1 = Offset(cx + eyePerpX * cell * 0.22, cy + eyePerpY * cell * 0.22);
    final Offset e2 = Offset(cx - eyePerpX * cell * 0.22, cy - eyePerpY * cell * 0.22);

    canvas.drawCircle(e1, er, eye);
    canvas.drawCircle(e1, er * 0.5, pupil);
    canvas.drawCircle(e2, er, eye);
    canvas.drawCircle(e2, er * 0.5, pupil);
  }

  @override
  bool shouldRepaint(_SnakePainter old) => true;
}
