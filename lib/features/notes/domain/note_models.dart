import "dart:convert";

import "package:flutter_quill/flutter_quill.dart" as quill;

enum NoteType {
  text,
  checklist,
}

enum NoteSortMode {
  updatedDesc,
  updatedAsc,
  createdDesc,
  createdAsc,
}

class NoteChecklistItem {
  const NoteChecklistItem({
    required this.id,
    required this.text,
    required this.done,
  });

  final String id;
  final String text;
  final bool done;

  Map<String, dynamic> toJson() => {
        "id": id,
        "text": text,
        "done": done,
      };

  factory NoteChecklistItem.fromJson(Map<String, dynamic> json) =>
      NoteChecklistItem(
        id: json["id"] as String? ?? "",
        text: json["text"] as String? ?? "",
        done: json["done"] as bool? ?? false,
      );
}

class NoteItem {
  const NoteItem({
    required this.id,
    required this.title,
    required this.content,
    required this.type,
    required this.color,
    required this.tags,
    required this.checklist,
    required this.isPinned,
    required this.isArchived,
    required this.isDeleted,
    required this.createdAt,
    required this.updatedAt,
    this.reminderAt,
    required this.sortOrder,
    this.scheduleDate,
    this.lessonNumber,
    this.groupFile,
    this.college,
    this.imagePath,
    this.imagePaths = const [],
    this.voicePaths = const [],
    this.replyToId,
    this.replyPreview,
  });

  final String id;
  final String title;
  final String content;
  final NoteType type;
  final String color;
  final List<String> tags;
  final List<NoteChecklistItem> checklist;
  final bool isPinned;
  final bool isArchived;
  final bool isDeleted;
  final int createdAt;
  final int updatedAt;
  final int? reminderAt;
  final double sortOrder;
  final String? scheduleDate;
  final int? lessonNumber;
  final String? groupFile;
  final String? college;
  final String? imagePath;
  final List<String> imagePaths;
  final List<String> voicePaths;
  final String? replyToId;
  final String? replyPreview;

  bool get isEmpty =>
      title.trim().isEmpty && content.trim().isEmpty && checklist.isEmpty;

  String get plainContent {
    if (content.isEmpty) return "";
    try {
      final decoded = jsonDecode(content);
      if (decoded is List) {
        final doc = quill.Document.fromJson(decoded);
        return doc.toPlainText().trim();
      }
      if (decoded is Map<String, dynamic>) {
        return _plainTextFromAppFlowyJson(decoded).trim();
      }
    } catch (_) {}
    return content;
  }

  bool get isQuillDelta {
    if (content.isEmpty) return false;
    try {
      final decoded = jsonDecode(content);
      return decoded is List;
    } catch (_) {
      return false;
    }
  }

  bool get isAppFlowyDocument {
    if (content.isEmpty) return false;
    try {
      final decoded = jsonDecode(content);
      return decoded is Map<String, dynamic> && decoded["document"] is Map;
    } catch (_) {
      return false;
    }
  }

  static String _plainTextFromAppFlowyJson(Map<String, dynamic> json) {
    final buffer = StringBuffer();
    void visit(dynamic node) {
      if (node is! Map) return;
      final data = node["data"];
      if (data is Map && data["delta"] is List) {
        for (final op in data["delta"] as List) {
          if (op is Map && op["insert"] is String) {
            buffer.write(op["insert"]);
          }
        }
      }
      final children = node["children"];
      if (children is List) {
        for (final c in children) visit(c);
      }
    }
    final doc = json["document"];
    if (doc is Map) visit(doc);
    return buffer.toString();
  }

  static String plainTextToDelta(String text) {
    if (text.isEmpty) return jsonEncode([{"insert": "\n"}]);
    final doc = quill.Document()..insert(0, text);
    return jsonEncode(doc.toDelta().toJson());
  }

  NoteItem copyWith({
    String? id,
    String? title,
    String? content,
    NoteType? type,
    String? color,
    List<String>? tags,
    List<NoteChecklistItem>? checklist,
    bool? isPinned,
    bool? isArchived,
    bool? isDeleted,
    int? createdAt,
    int? updatedAt,
    int? reminderAt,
    double? sortOrder,
    String? scheduleDate,
    int? lessonNumber,
    String? groupFile,
    String? college,
    String? imagePath,
    List<String>? imagePaths,
    List<String>? voicePaths,
    String? replyToId,
    String? replyPreview,
  }) {
    return NoteItem(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      type: type ?? this.type,
      color: color ?? this.color,
      tags: tags ?? this.tags,
      checklist: checklist ?? this.checklist,
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reminderAt: reminderAt ?? this.reminderAt,
      sortOrder: sortOrder ?? this.sortOrder,
      scheduleDate: scheduleDate ?? this.scheduleDate,
      lessonNumber: lessonNumber ?? this.lessonNumber,
      groupFile: groupFile ?? this.groupFile,
      college: college ?? this.college,
      imagePath: imagePath ?? this.imagePath,
      imagePaths: imagePaths ?? this.imagePaths,
      voicePaths: voicePaths ?? this.voicePaths,
      replyToId: replyToId ?? this.replyToId,
      replyPreview: replyPreview ?? this.replyPreview,
    );
  }

  Map<String, dynamic> toDbMap() => {
        "id": id,
        "title": title,
        "content": content,
        "type": type.name,
        "color": color,
        "checklist_json": jsonEncode(checklist.map((e) => e.toJson()).toList()),
        "is_pinned": isPinned ? 1 : 0,
        "is_archived": isArchived ? 1 : 0,
        "is_deleted": isDeleted ? 1 : 0,
        "created_at": createdAt,
        "updated_at": updatedAt,
        "reminder_at": reminderAt,
        "sort_order": sortOrder,
        "schedule_date": scheduleDate,
        "lesson_number": lessonNumber,
        "group_file": groupFile,
        "college": college,
        "image_path": imagePath,
        "image_paths": jsonEncode(imagePaths),
        "voice_paths": jsonEncode(voicePaths),
        "reply_to_id": replyToId,
        "reply_preview": replyPreview,
      };

  factory NoteItem.fromDbMap(
    Map<String, dynamic> map, {
    List<String> tags = const [],
  }) {
    List<NoteChecklistItem> parsedChecklist = const [];
    try {
      final raw = map["checklist_json"] as String? ?? "[]";
      final arr = jsonDecode(raw) as List<dynamic>;
      parsedChecklist = arr
          .map((e) => NoteChecklistItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {}

    List<String> parsedImagePaths = [];
    try {
      final raw = map["image_paths"] as String? ?? "[]";
      final arr = jsonDecode(raw) as List<dynamic>;
      parsedImagePaths = arr.map((e) => e.toString()).toList();
    } catch (_) {}
    if (parsedImagePaths.isEmpty) {
      final single = map["image_path"] as String?;
      if (single != null && single.isNotEmpty) {
        parsedImagePaths = [single];
      }
    }

    List<String> parsedVoicePaths = [];
    try {
      final raw = map["voice_paths"] as String? ?? "[]";
      final arr = jsonDecode(raw) as List<dynamic>;
      parsedVoicePaths = arr.map((e) => e.toString()).toList();
    } catch (_) {}

    final typeRaw = map["type"] as String? ?? "text";
    final type =
        typeRaw == NoteType.checklist.name ? NoteType.checklist : NoteType.text;

    final singleImagePath = map["image_path"] as String?;

    return NoteItem(
      id: map["id"] as String? ?? "",
      title: map["title"] as String? ?? "",
      content: map["content"] as String? ?? "",
      type: type,
      color: map["color"] as String? ?? "default",
      tags: tags,
      checklist: parsedChecklist,
      isPinned: (map["is_pinned"] as int? ?? 0) == 1,
      isArchived: (map["is_archived"] as int? ?? 0) == 1,
      isDeleted: (map["is_deleted"] as int? ?? 0) == 1,
      createdAt: map["created_at"] as int? ?? 0,
      updatedAt: map["updated_at"] as int? ?? 0,
      reminderAt: map["reminder_at"] as int?,
      sortOrder: (map["sort_order"] as num?)?.toDouble() ?? 0,
      scheduleDate: map["schedule_date"] as String?,
      lessonNumber: map["lesson_number"] as int?,
      groupFile: map["group_file"] as String?,
      college: map["college"] as String?,
      imagePath: singleImagePath,
      imagePaths: parsedImagePaths,
      voicePaths: parsedVoicePaths,
      replyToId: map["reply_to_id"] as String?,
      replyPreview: map["reply_preview"] as String?,
    );
  }
}
