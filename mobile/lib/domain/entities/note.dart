import 'package:uuid/uuid.dart';

class Note {
  final String id;
  final String title;
  final String content;
  final List<String> tags;
  final String? projectId;
  final bool isPinned;
  final bool isArchived;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int serverVersion;

  const Note({
    required this.id,
    required this.title,
    required this.content,
    this.tags = const [],
    this.projectId,
    this.isPinned = false,
    this.isArchived = false,
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
    this.serverVersion = 0,
  });

  /// Factory constructor to create a brand new note with client-generated UUID
  factory Note.create({
    required String title,
    required String content,
    List<String> tags = const [],
    String? projectId,
    bool isPinned = false,
  }) {
    final now = DateTime.now();
    return Note(
      id: const Uuid().v4(),
      title: title.trim(),
      content: content.trim(),
      tags: tags.map((t) => t.trim().toLowerCase()).where((t) => t.isNotEmpty).toList(),
      projectId: projectId,
      isPinned: isPinned,
      isArchived: false,
      isDeleted: false,
      createdAt: now,
      updatedAt: now,
      serverVersion: 0,
    );
  }

  Note copyWith({
    String? title,
    String? content,
    List<String>? tags,
    String? projectId,
    bool? isPinned,
    bool? isArchived,
    bool? isDeleted,
    DateTime? updatedAt,
    int? serverVersion,
  }) {
    return Note(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      tags: tags ?? this.tags,
      projectId: projectId ?? this.projectId,
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      serverVersion: serverVersion ?? this.serverVersion,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'project_id': projectId,
      'is_pinned': isPinned ? 1 : 0,
      'is_archived': isArchived ? 1 : 0,
      'is_deleted': isDeleted ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'server_version': serverVersion,
    };
  }

  factory Note.fromMap(Map<String, dynamic> map, {List<String> tags = const []}) {
    return Note(
      id: map['id'] as String,
      title: map['title'] as String? ?? '',
      content: map['content'] as String? ?? '',
      tags: tags,
      projectId: map['project_id'] as String?,
      isPinned: (map['is_pinned'] as int? ?? 0) == 1,
      isArchived: (map['is_archived'] as int? ?? 0) == 1,
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      serverVersion: map['server_version'] as int? ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Note &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          content == other.content &&
          isPinned == other.isPinned &&
          isArchived == other.isArchived &&
          isDeleted == other.isDeleted &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode =>
      id.hashCode ^
      title.hashCode ^
      content.hashCode ^
      isPinned.hashCode ^
      isArchived.hashCode ^
      isDeleted.hashCode ^
      updatedAt.hashCode;
}
