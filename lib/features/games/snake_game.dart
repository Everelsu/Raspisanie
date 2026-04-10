import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

// Encode position as a single int: x * 1000 + y
// Grid is 22 cols x 30 rows, so max x=21, max y=29 — fits easily
int _encode(int x, int y) => x * 1000 + y;
int _decodeX(int v) => v ~/ 1000;
int _decodeY(int v) => v % 1000;

class SnakePage extends StatefulWidget {
  const SnakePage({super.key});

  @override
  State<SnakePage> createState() => _SnakePageState();
}

class _SnakePageState extends State<SnakePage> {
  static const int kCols = 22;
  static const int kRows = 30;
  static const Duration kTickInterval = Duration(milliseconds: 140);

  // Direction encoded: (dx, dy)
  int _dirX = 1;
  int _dirY = 0;

  // Pending direction change (buffered input)
  int _pendingDirX = 1;
  int _pendingDirY = 0;

  // Snake: list of encoded positions, index 0 = head
  late List<int> _snake;

  // Food position
  late int _food;

  int _score = 0;
  int _bestScore = 0;
  bool _gameOver = false;
  bool _started = false;

  Timer? _timer;
  final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _initGame();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _initGame() {
    _timer?.cancel();
    // Start snake in the middle, length 3, going right
    final int startX = kCols ~/ 2;
    final int startY = kRows ~/ 2;
    _snake = [
      _encode(startX, startY),
      _encode(startX - 1, startY),
      _encode(startX - 2, startY),
    ];
    _dirX = 1;
    _dirY = 0;
    _pendingDirX = 1;
    _pendingDirY = 0;
    _score = 0;
    _gameOver = false;
    _started = false;
    _spawnFood();
  }

  void _startGame() {
    _started = true;
    _timer = Timer.periodic(kTickInterval, (_) => _tick());
  }

  void _spawnFood() {
    final Set<int> snakeSet = _snake.toSet();
    final List<int> empty = [];
    for (int x = 0; x < kCols; x++) {
      for (int y = 0; y < kRows; y++) {
        final int pos = _encode(x, y);
        if (!snakeSet.contains(pos)) {
          empty.add(pos);
        }
      }
    }
    if (empty.isEmpty) return;
    _food = empty[_rng.nextInt(empty.length)];
  }

  void _tick() {
    if (_gameOver) return;

    // Apply buffered direction
    _dirX = _pendingDirX;
    _dirY = _pendingDirY;

    final int headX = _decodeX(_snake.first);
    final int headY = _decodeY(_snake.first);
    final int newX = headX + _dirX;
    final int newY = headY + _dirY;

    // Wall collision
    if (newX < 0 || newX >= kCols || newY < 0 || newY >= kRows) {
      _triggerGameOver();
      return;
    }

    final int newHead = _encode(newX, newY);

    // Self collision (ignore tail since it will move)
    for (int i = 0; i < _snake.length - 1; i++) {
      if (_snake[i] == newHead) {
        _triggerGameOver();
        return;
      }
    }

    setState(() {
      _snake.insert(0, newHead);

      if (newHead == _food) {
        _score++;
        if (_score > _bestScore) _bestScore = _score;
        _spawnFood();
        // Don't remove tail — snake grows
      } else {
        _snake.removeLast();
      }
    });
  }

  void _triggerGameOver() {
    _timer?.cancel();
    setState(() {
      _gameOver = true;
    });
  }

  void _changeDirection(int dx, int dy) {
    // Prevent reversing direction
    if (dx == -_dirX && dy == -_dirY) return;
    if (dx == 0 && dy == 0) return;
    if (!_started) {
      _pendingDirX = dx;
      _pendingDirY = dy;
      _startGame();
      return;
    }
    _pendingDirX = dx;
    _pendingDirY = dy;
  }

  void _handleSwipe(Offset velocity) {
    final double vx = velocity.dx;
    final double vy = velocity.dy;
    if (vx.abs() > vy.abs()) {
      _changeDirection(vx > 0 ? 1 : -1, 0);
    } else {
      _changeDirection(0, vy > 0 ? 1 : -1);
    }
  }

  void _restart() {
    setState(() {
      _initGame();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('🐍 Змейка'),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Счёт: $_score',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                Text('Рекорд: $_bestScore',
                    style: theme.textTheme.labelSmall),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onPanEnd: (details) =>
                  _handleSwipe(details.velocity.pixelsPerSecond),
              onTap: () {
                if (!_started && !_gameOver) _startGame();
              },
              child: Stack(
                children: [
                  LayoutBuilder(builder: (context, constraints) {
                    return CustomPaint(
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                      painter: _SnakePainter(
                        snake: _snake,
                        food: _food,
                        cols: kCols,
                        rows: kRows,
                        primaryColor: theme.colorScheme.primary,
                        backgroundColor: theme.scaffoldBackgroundColor,
                        colorScheme: theme.colorScheme,
                      ),
                    );
                  }),
                  if (!_started && !_gameOver)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface
                              .withAlpha(220),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('🐍',
                                style: const TextStyle(fontSize: 48)),
                            const SizedBox(height: 8),
                            Text('Проведи пальцем или',
                                style: theme.textTheme.bodyMedium),
                            Text('нажми кнопку для старта',
                                style: theme.textTheme.bodyMedium),
                          ],
                        ),
                      ),
                    ),
                  if (_gameOver)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 24),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withAlpha(230),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(60),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Игра окончена',
                                style: theme.textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            Text('Счёт: $_score',
                                style: theme.textTheme.titleLarge),
                            if (_score == _bestScore && _score > 0) ...[
                              const SizedBox(height: 4),
                              Text('🏆 Новый рекорд!',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.primary)),
                            ],
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: _restart,
                              icon: const Icon(Icons.refresh),
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
          _buildArrowButtons(theme),
        ],
      ),
    );
  }

  Widget _buildArrowButtons(ThemeData theme) {
    const double btnSize = 52.0;
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Up button
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _arrowButton(
                  icon: Icons.keyboard_arrow_up,
                  onTap: () => _changeDirection(0, -1),
                  size: btnSize,
                  theme: theme),
            ],
          ),
          // Left / Down / Right
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _arrowButton(
                  icon: Icons.keyboard_arrow_left,
                  onTap: () => _changeDirection(-1, 0),
                  size: btnSize,
                  theme: theme),
              SizedBox(width: btnSize),
              _arrowButton(
                  icon: Icons.keyboard_arrow_right,
                  onTap: () => _changeDirection(1, 0),
                  size: btnSize,
                  theme: theme),
            ],
          ),
          // Down button
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _arrowButton(
                  icon: Icons.keyboard_arrow_down,
                  onTap: () => _changeDirection(0, 1),
                  size: btnSize,
                  theme: theme),
            ],
          ),
        ],
      ),
    );
  }

  Widget _arrowButton({
    required IconData icon,
    required VoidCallback onTap,
    required double size,
    required ThemeData theme,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withAlpha(30),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.primary.withAlpha(80),
            width: 1.5,
          ),
        ),
        child: Icon(icon, color: theme.colorScheme.primary, size: 28),
      ),
    );
  }
}

class _SnakePainter extends CustomPainter {
  final List<int> snake;
  final int food;
  final int cols;
  final int rows;
  final Color primaryColor;
  final Color backgroundColor;
  final ColorScheme colorScheme;

  const _SnakePainter({
    required this.snake,
    required this.food,
    required this.cols,
    required this.rows,
    required this.primaryColor,
    required this.backgroundColor,
    required this.colorScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double cellW = size.width / cols;
    final double cellH = size.height / rows;
    final double cellSize = cellW < cellH ? cellW : cellH;

    // Offset to center the grid
    final double offsetX = (size.width - cellSize * cols) / 2;
    final double offsetY = (size.height - cellSize * rows) / 2;

    // Draw background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = backgroundColor,
    );

    // Draw subtle grid
    final Paint gridPaint = Paint()
      ..color = colorScheme.onSurface.withAlpha(18)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    for (int x = 0; x <= cols; x++) {
      canvas.drawLine(
        Offset(offsetX + x * cellSize, offsetY),
        Offset(offsetX + x * cellSize, offsetY + rows * cellSize),
        gridPaint,
      );
    }
    for (int y = 0; y <= rows; y++) {
      canvas.drawLine(
        Offset(offsetX, offsetY + y * cellSize),
        Offset(offsetX + cols * cellSize, offsetY + y * cellSize),
        gridPaint,
      );
    }

    // Draw food
    final int foodX = _decodeX(food);
    final int foodY = _decodeY(food);
    final Offset foodCenter = Offset(
      offsetX + foodX * cellSize + cellSize / 2,
      offsetY + foodY * cellSize + cellSize / 2,
    );
    final double foodRadius = cellSize * 0.38;

    // Food glow
    canvas.drawCircle(
      foodCenter,
      foodRadius + 2,
      Paint()..color = Colors.red.withAlpha(60),
    );
    canvas.drawCircle(
      foodCenter,
      foodRadius,
      Paint()..color = Colors.red,
    );
    // Food highlight
    canvas.drawCircle(
      foodCenter - Offset(foodRadius * 0.25, foodRadius * 0.25),
      foodRadius * 0.3,
      Paint()..color = Colors.white.withAlpha(160),
    );

    // Draw snake segments
    final int len = snake.length;
    for (int i = len - 1; i >= 0; i--) {
      final int sx = _decodeX(snake[i]);
      final int sy = _decodeY(snake[i]);

      // Gradient: head is full primary, tail fades
      final double t = len > 1 ? i / (len - 1) : 0.0;
      // t=0 → head (bright), t=1 → tail (dim)
      final int alpha = (255 - (t * 120).round()).clamp(135, 255);
      final Color segColor = i == 0
          ? primaryColor
          : Color.lerp(primaryColor, primaryColor.withAlpha(135), t)!;

      final Rect segRect = Rect.fromLTWH(
        offsetX + sx * cellSize + 1.5,
        offsetY + sy * cellSize + 1.5,
        cellSize - 3,
        cellSize - 3,
      );
      final double radius = cellSize * 0.3;

      canvas.drawRRect(
        RRect.fromRectAndRadius(segRect, Radius.circular(radius)),
        Paint()..color = segColor.withAlpha(alpha),
      );

      // Head eyes
      if (i == 0 && len > 0) {
        _drawEyes(canvas, offsetX + sx * cellSize, offsetY + sy * cellSize,
            cellSize);
      }
    }
  }

  void _drawEyes(Canvas canvas, double x, double y, double cell) {
    final double eyeRadius = cell * 0.1;
    final double eyeY = y + cell * 0.35;
    final Paint eyePaint = Paint()..color = Colors.white;
    final Paint pupilPaint = Paint()..color = Colors.black;

    // Left eye
    canvas.drawCircle(Offset(x + cell * 0.33, eyeY), eyeRadius, eyePaint);
    canvas.drawCircle(
        Offset(x + cell * 0.33, eyeY), eyeRadius * 0.5, pupilPaint);
    // Right eye
    canvas.drawCircle(Offset(x + cell * 0.67, eyeY), eyeRadius, eyePaint);
    canvas.drawCircle(
        Offset(x + cell * 0.67, eyeY), eyeRadius * 0.5, pupilPaint);
  }

  @override
  bool shouldRepaint(_SnakePainter old) => true;
}
