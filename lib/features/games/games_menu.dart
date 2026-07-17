import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_2048.dart';
import 'reaction_game.dart';
import 'snake_game.dart';
import 'tic_tac_toe.dart';

/// Скрытое меню с мини-играми. Открывается долгим нажатием на вкладку «Сеть».
void showGamesMenu(BuildContext context) {
  HapticFeedback.heavyImpact();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => const _GamesMenuSheet(),
  );
}

class _GameInfo {
  const _GameInfo({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.bestKey,
    required this.bestLabel,
    required this.pageBuilder,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final Color color;
  final String bestKey;
  final String Function(int value) bestLabel;
  final Widget Function() pageBuilder;
}

class _GamesMenuSheet extends StatefulWidget {
  const _GamesMenuSheet();

  @override
  State<_GamesMenuSheet> createState() => _GamesMenuSheetState();
}

class _GamesMenuSheetState extends State<_GamesMenuSheet> {
  static final _games = <_GameInfo>[
    _GameInfo(
      emoji: '🐍',
      title: 'Змейка',
      subtitle: 'Классика — ешь, расти, не врежься',
      color: const Color(0xFF4CAF50),
      bestKey: 'snake_best_score',
      bestLabel: (v) => 'Рекорд: $v',
      pageBuilder: () => const SnakePage(),
    ),
    _GameInfo(
      emoji: '🎮',
      title: '2048',
      subtitle: 'Складывай числа до 2048',
      color: const Color(0xFFFF9800),
      bestKey: 'game_2048_best',
      bestLabel: (v) => 'Рекорд: $v',
      pageBuilder: () => const Game2048Page(),
    ),
    _GameInfo(
      emoji: '⚡',
      title: 'Реакция',
      subtitle: 'Жди зелёный — жми быстрее всех',
      color: const Color(0xFF5AC8FA),
      bestKey: 'reaction_best_ms',
      bestLabel: (v) => 'Рекорд: $v мс',
      pageBuilder: () => const ReactionPage(),
    ),
    _GameInfo(
      emoji: '⭕',
      title: 'Крестики-нолики',
      subtitle: 'На двоих: классика, исчезающие фишки, 5×5',
      color: const Color(0xFFB388FF),
      bestKey: '',
      bestLabel: (v) => '',
      pageBuilder: () => const TicTacToePage(),
    ),
  ];

  Map<String, int> _bests = const {};

  @override
  void initState() {
    super.initState();
    _loadBests();
  }

  Future<void> _loadBests() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, int>{};
    for (final g in _games) {
      final v = prefs.getInt(g.bestKey);
      if (v != null && v > 0) map[g.bestKey] = v;
    }
    if (mounted) setState(() => _bests = map);
  }

  void _open(_GameInfo game) {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => game.pageBuilder()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurface.withAlpha(50),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: cs.primary.withAlpha(22),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.sports_esports_rounded,
                    color: cs.primary,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Мини-игры',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Скрытая функция — только для своих',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final game in _games)
            _GameTile(
              game: game,
              best: _bests[game.bestKey],
              onTap: () => _open(game),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({
    required this.game,
    required this.best,
    required this.onTap,
  });

  final _GameInfo game;
  final int? best;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = game.color;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: color.withAlpha(18),
              border: Border.all(color: color.withAlpha(50), width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withAlpha(35),
                  ),
                  child: Center(
                    child:
                        Text(game.emoji, style: const TextStyle(fontSize: 24)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        game.title,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        game.subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (best != null)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: color.withAlpha(30),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      game.bestLabel(best!),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: color.withAlpha(180),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
