import "dart:io";

import "package:image_picker/image_picker.dart";
import "package:path/path.dart" as p;
import "package:path_provider/path_provider.dart";

class NotesMediaHelper {
  static Future<Directory> _notesMediaDir() async {
    final app = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(app.path, "notes_media"));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String _uniqueName(String prefix, String extension) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final r = now.remainder(100000);
    return "${prefix}_${now}_$r.$extension";
  }

  /// Saves picked image files to app storage and returns local paths.
  static Future<List<String>> saveImageFiles(List<XFile> files) async {
    if (files.isEmpty) return [];
    final dir = await _notesMediaDir();
    final paths = <String>[];
    for (final f in files) {
      final ext = p.extension(f.name).isEmpty ? "jpg" : p.extension(f.name).replaceFirst(".", "");
      final name = _uniqueName("img", ext);
      final dest = File(p.join(dir.path, name));
      final bytes = await f.readAsBytes();
      await dest.writeAsBytes(bytes);
      paths.add(dest.path);
    }
    return paths;
  }

  /// Saves a single image file (e.g. from camera) and returns local path.
  static Future<String?> saveImageFile(XFile file) async {
    final list = await saveImageFiles([file]);
    return list.isEmpty ? null : list.single;
  }

  /// Returns a new path in notes_media for recording a voice message.
  static Future<String> getNewVoicePath() async {
    final dir = await _notesMediaDir();
    return p.join(dir.path, _uniqueName("voice", "m4a"));
  }

  /// Copies a recorded file from [sourcePath] into notes_media (e.g. when recorder uses temp dir).
  static Future<String> saveVoiceFileFrom(String sourcePath) async {
    final dir = await _notesMediaDir();
    final name = _uniqueName("voice", "m4a");
    final dest = File(p.join(dir.path, name));
    await File(sourcePath).copy(dest.path);
    return dest.path;
  }

  /// Saves a file (e.g. from file_picker) to notes_media and returns the local path.
  static Future<String?> saveFile(String sourcePath, {String? name}) async {
    final dir = await _notesMediaDir();
    final base = name ?? p.basename(sourcePath);
    final ext = p.extension(base).isEmpty ? "" : p.extension(base).replaceFirst(".", "");
    final finalName = _uniqueName("file", ext.isEmpty ? "bin" : ext);
    final dest = File(p.join(dir.path, finalName));
    await File(sourcePath).copy(dest.path);
    return dest.path;
  }

  /// Optional: delete files when note is permanently deleted.
  static Future<void> deleteFiles(List<String> paths) async {
    for (final path in paths) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }
}
