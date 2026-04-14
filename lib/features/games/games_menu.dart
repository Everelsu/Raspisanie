import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game_2048.dart';
import 'snake_game.dart';

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

class _GamesMenuSheet extends StatelessWidget {
  const _GamesMenuSheet();

  static const _games = [
    (
      icon: Icons.phishing_rounded,
      emoji: '🐍',
      title: 'Змейка',
      subtitle: 'Классика — ешь, расти, не врежься',
      color: Color(0xFF4CAF50),
      builder: _openSnake,
    ),
    (
      icon: Icons.grid_4x4_rounded,
      emoji: '🎮',
      title: '2048',
      subtitle: 'Складывай числа до 2048',
      color: Color(0xFFFF9800),
      builder: _open2048,
    ),
  ];

  static void _openSnake(BuildContext ctx) => _push(ctx, const SnakePage());
  static void _open2048(BuildContext ctx) => _push(ctx, const Game2048Page());

  static void _push(BuildContext ctx, Widget page) {
    Navigator.of(ctx).pop();
    Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurface.withAlpha(50),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          // Header
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
              icon: game.icon,
              emoji: game.emoji,
              title: game.title,
              subtitle: game.subtitle,
              color: game.color,
              onTap: () => game.builder(context),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({
    required this.icon,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String emoji;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
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
                    child: Text(emoji, style: const TextStyle(fontSize: 24)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
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
