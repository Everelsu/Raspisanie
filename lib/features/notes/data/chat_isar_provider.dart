import "package:isar/isar.dart";
import "package:path_provider/path_provider.dart";

import "chat_message_entity.dart";

/// Single Isar instance for notes (chat) feature.
class ChatIsarProvider {
  ChatIsarProvider._();
  static Isar? _instance;
  static bool _opening = false;

  static Future<Isar> get instance async {
    if (_instance != null) return _instance!;
    if (_opening) {
      while (_instance == null) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return _instance!;
    }
    _opening = true;
    final dir = await getApplicationDocumentsDirectory();
    _instance = await Isar.open(
      [ChatMessageEntitySchema, PinnedRefEntitySchema, FavoriteRefEntitySchema],
      directory: dir.path,
      name: "chat_db",
    );
    _opening = false;
    return _instance!;
  }

  static Future<void> close() async {
    final isar = _instance;
    _instance = null;
    await isar?.close();
  }
}
