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
    builder: (ctx) => const _GamesMenuSheet(),
  );
}

class _GamesMenuSheet extends StatelessWidget {
  const _GamesMenuSheet();

  static const _games = [
    (
      icon: '🐍',
      title: 'Змейка',
      subtitle: 'Классическая игра',
      color: Color(0xFF4CAF50),
      builder: _openSnake,
    ),
    (
      icon: '2️⃣',
      title: '2048',
      subtitle: 'Складывай числа',
      color: Color(0xFFFF9800),
      builder: _open2048,
    ),
  ];

  static void _openSnake(BuildContext ctx) =>
      _push(ctx, const SnakePage());

  static void _open2048(BuildContext ctx) =>
      _push(ctx, const Game2048Page());

  static void _push(BuildContext ctx, Widget page) {
    Navigator.of(ctx).pop();
    Navigator.of(ctx).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withAlpha(50),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text('', style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Мини-игры',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Ураа ты нашёл... (WIP)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            for (final game in _games)
              _GameTile(
                icon: game.icon,
                title: game.title,
                subtitle: game.subtitle,
                color: game.color,
                onTap: () => game.builder(context),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final String icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
              border: Border.all(color: color.withAlpha(40), width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withAlpha(30),
                  ),
                  child: Center(
                    child: Text(icon, style: const TextStyle(fontSize: 22)),
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
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
