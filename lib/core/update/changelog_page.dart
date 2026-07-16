import "package:flutter/material.dart";
import "package:flutter/services.dart" show rootBundle;
import "package:flutter_markdown_plus/flutter_markdown_plus.dart";

/// Экран «Что нового» — полный журнал изменений из CHANGELOG.md (asset).
class ChangelogPage extends StatelessWidget {
  const ChangelogPage({super.key});

  /// Убирает вводный текст для мейнтейнеров — показываем с первой записи версии.
  static String _stripPreamble(String markdown) {
    final firstEntry = markdown.indexOf(RegExp(r"^## ", multiLine: true));
    if (firstEntry <= 0) return markdown;
    return markdown.substring(firstEntry);
  }
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text("Что нового")),
      body: FutureBuilder<String>(
        future: rootBundle.loadString("CHANGELOG.md"),
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return Markdown(
            data: _stripPreamble(data),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            styleSheet: MarkdownStyleSheet.fromTheme(theme),
          );
        },
      ),
    );
  }
}
