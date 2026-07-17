import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Режим игры: размер поля, сколько фишек в ряд нужно для победы,
/// и лимит фишек одного игрока на поле (null — без лимита).
enum TicTacToeMode {
  classic(
    label: '3×3',
    subtitle: 'Классика — три в ряд',
    boardSize: 3,
    winLength: 3,
    maxMarks: null,
  ),
  fading(
    label: 'Исчезающие',
    subtitle: 'На поле не больше 3 фишек каждого',
    boardSize: 3,
    winLength: 3,
    maxMarks: 3,
  ),
  big(
    label: '5×5',
    subtitle: 'Большое поле — четыре в ряд',
    boardSize: 5,
    winLength: 4,
    maxMarks: null,
  );

  const TicTacToeMode({
    required this.label,
    required this.subtitle,
    required this.boardSize,
    required this.winLength,
    required this.maxMarks,
  });

  final String label;
  final String subtitle;
  final int boardSize;
  final int winLength;
  final int? maxMarks;
}

/// Крестики-нолики на двоих на одном экране, с выбором поля/режима.
/// Счёт серии держится, пока открыта страница; проигравший раунд
/// ходит первым в следующем.
class TicTacToePage extends StatefulWidget {
  const TicTacToePage({super.key});

  @override
  State<TicTacToePage> createState() => _TicTacToePageState();
}

class _TicTacToePageState extends State<TicTacToePage> {
  TicTacToeMode _mode = TicTacToeMode.classic;
  late List<int> _board; // 0 — пусто, 1 — X, 2 — O
  final List<int> _historyX = [];
  final List<int> _historyO = [];
  int _turn = 1;
  int _winner = 0; // 0 — игра идёт, 1/2 — победитель, 3 — ничья
  List<int> _winLine = const [];
  int _scoreX = 0;
  int _scoreO = 0;
  int _draws = 0;
  int _nextStarts = 2; // кто начнёт следующий раунд

  int get _n => _mode.boardSize;
  int get _cellCount => _n * _n;

  @override
  void initState() {
    super.initState();
    _board = List.filled(_cellCount, 0);
  }

  void _setMode(TicTacToeMode mode) {
    if (mode == _mode) return;
    HapticFeedback.selectionClick();
    setState(() {
      _mode = mode;
      _resetSeries();
    });
  }

  void _tap(int i) {
    if (_winner != 0 || _board[i] != 0) return;
    HapticFeedback.selectionClick();
    setState(() {
      final history = _turn == 1 ? _historyX : _historyO;
      final maxMarks = _mode.maxMarks;
      if (maxMarks != null && history.length >= maxMarks) {
        final removed = history.removeAt(0);
        _board[removed] = 0;
      }
      _board[i] = _turn;
      history.add(i);

      final line = _findWinLine(i, _turn);
      if (line != null) {
        _winner = _turn;
        _winLine = line;
        _nextStarts = _turn == 1 ? 2 : 1;
        if (_turn == 1) {
          _scoreX++;
        } else {
          _scoreO++;
        }
        HapticFeedback.heavyImpact();
        return;
      }
      if (maxMarks == null && !_board.contains(0)) {
        _winner = 3;
        _draws++;
        HapticFeedback.mediumImpact();
        return;
      }
      _turn = _turn == 1 ? 2 : 1;
    });
  }

  /// Сканирует 4 направления через последнюю поставленную клетку [pos] —
  /// достаточно проверить только линии, проходящие через новый ход.
  /// Работает для любого размера поля и длины выигрышной линии.
  List<int>? _findWinLine(int pos, int player) {
    final n = _n;
    final row = pos ~/ n, col = pos % n;
    const dirs = [(1, 0), (0, 1), (1, 1), (1, -1)];
    for (final (dr, dc) in dirs) {
      final line = [pos];
      for (final sign in [1, -1]) {
        var r = row + dr * sign, c = col + dc * sign;
        while (r >= 0 && r < n && c >= 0 && c < n && _board[r * n + c] == player) {
          line.add(r * n + c);
          r += dr * sign;
          c += dc * sign;
        }
      }
      if (line.length >= _mode.winLength) return line;
    }
    return null;
  }

  void _nextRound() {
    HapticFeedback.lightImpact();
    setState(() {
      _board = List.filled(_cellCount, 0);
      _historyX.clear();
      _historyO.clear();
      _winner = 0;
      _winLine = const [];
      _turn = _nextStarts;
    });
  }

  void _resetSeries() {
    _board = List.filled(_cellCount, 0);
    _historyX.clear();
    _historyO.clear();
    _winner = 0;
    _winLine = const [];
    _turn = 1;
    _nextStarts = 2;
    _scoreX = 0;
    _scoreO = 0;
    _draws = 0;
  }

  void _confirmResetSeries() {
    HapticFeedback.mediumImpact();
    setState(_resetSeries);
  }

  Color _xColor(ColorScheme cs) => cs.primary;
  static const _oColor = Color(0xFFFF9800);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final xColor = _xColor(cs);

    final String statusText;
    final Color statusColor;
    switch (_winner) {
      case 1:
        statusText = 'Победили крестики!';
        statusColor = xColor;
      case 2:
        statusText = 'Победили нолики!';
        statusColor = _oColor;
      case 3:
        statusText = 'Ничья';
        statusColor = cs.onSurfaceVariant;
      default:
        statusText = _turn == 1 ? 'Ходят крестики' : 'Ходят нолики';
        statusColor = _turn == 1 ? xColor : _oColor;
    }

    final gameStarted = _historyX.isNotEmpty || _historyO.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('⭕ Крестики-нолики'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded),
            tooltip: 'Сбросить счёт и поле',
            onPressed: _confirmResetSeries,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 10),
            _ModeRow(
              mode: _mode,
              onSelect: _setMode,
              enabled: !gameStarted || _winner != 0,
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _scoreChip(theme, 'X', _scoreX, xColor, _turn == 1 && _winner == 0),
                const SizedBox(width: 10),
                _scoreChip(theme, '=', _draws, cs.onSurfaceVariant, false),
                const SizedBox(width: 10),
                _scoreChip(theme, 'O', _scoreO, _oColor, _turn == 2 && _winner == 0),
              ],
            ),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                statusText,
                key: ValueKey(statusText),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.onSurface.withAlpha(10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: _n,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: _cellCount,
                        itemBuilder: (context, i) => _cell(theme, i),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_winner != 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: FilledButton.icon(
                  onPressed: _nextRound,
                  icon: const Icon(Icons.replay_rounded, size: 18),
                  label: const Text('Следующий раунд'),
                ),
              )
            else
              const SizedBox(height: 64),
          ],
        ),
      ),
    );
  }

  Widget _scoreChip(
    ThemeData theme,
    String label,
    int value,
    Color color,
    bool active,
  ) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(active ? 40 : 18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withAlpha(active ? 200 : 60),
          width: active ? 1.6 : 1,
        ),
      ),
      child: Text(
        '$label · $value',
        style: theme.textTheme.titleSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _cell(ThemeData theme, int i) {
    final cs = theme.colorScheme;
    final v = _board[i];
    final inWinLine = _winLine.contains(i);
    final color = v == 1 ? _xColor(cs) : _oColor;
    // В режиме с лимитом фишка, которая исчезнет следующим ходом,
    // подсвечивается блёкло — предупреждение игроку.
    final history = v == 1 ? _historyX : _historyO;
    final isNextToFade = _mode.maxMarks != null &&
        v != 0 &&
        history.isNotEmpty &&
        history.first == i &&
        history.length >= _mode.maxMarks!;

    return GestureDetector(
      onTap: () => _tap(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: inWinLine
              ? color.withAlpha(50)
              : theme.cardTheme.color ?? cs.surface,
          borderRadius: BorderRadius.circular(_n > 3 ? 8 : 14),
          border: inWinLine ? Border.all(color: color, width: 2) : null,
        ),
        child: Center(
          child: AnimatedScale(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            scale: v == 0 ? 0.0 : 1.0,
            child: v == 0
                ? const SizedBox.shrink()
                : Icon(
                    v == 1 ? Icons.close_rounded : Icons.circle_outlined,
                    size: _n > 3 ? 26 : 44,
                    color: isNextToFade ? color.withAlpha(90) : color,
                  ),
          ),
        ),
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.mode,
    required this.onSelect,
    required this.enabled,
  });

  final TicTacToeMode mode;
  final ValueChanged<TicTacToeMode> onSelect;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: TicTacToeMode.values.map((m) {
          final selected = m == mode;
          return Tooltip(
            message: m.subtitle,
            child: GestureDetector(
              onTap: enabled ? () => onSelect(m) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? cs.primary.withAlpha(28) : cs.onSurface.withAlpha(10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? cs.primary : Colors.transparent,
                    width: 1.4,
                  ),
                ),
                child: Text(
                  m.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: selected ? cs.primary : cs.onSurface.withAlpha(180),
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
