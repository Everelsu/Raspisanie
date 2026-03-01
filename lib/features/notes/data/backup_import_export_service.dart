import "dart:io";

import "package:file_picker/file_picker.dart";
import "package:path_provider/path_provider.dart";
import "package:share_plus/share_plus.dart";

import "notes_repository.dart";

class BackupImportExportService {
  BackupImportExportService({NotesRepository? repository})
      : _repository = repository ?? NotesRepository();

  final NotesRepository _repository;

  Future<void> exportNotes() async {
    final json = await _repository.exportJson();
    final dir = await getTemporaryDirectory();
    final file = File(
      "${dir.path}/raspiflutter_notes_${DateTime.now().millisecondsSinceEpoch}.json",
    );
    await file.writeAsString(json, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: "Экспорт заметок Raspisanie",
        text: "Резервная копия заметок",
      ),
    );
  }

  Future<void> importNotes({required bool replace}) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ["json"],
      withData: false,
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.single.path;
    if (path == null || path.isEmpty) return;
    final raw = await File(path).readAsString();
    await _repository.importJson(raw, replace: replace);
  }
}
