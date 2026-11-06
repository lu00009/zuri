import 'package:uuid/uuid.dart';

class Folder {
  final String id;
  final String name;
  final String? coverImagePath;
  final String? colorAccent;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int noteCount;

  const Folder({
    required this.id,
    required this.name,
    this.coverImagePath,
    this.colorAccent,
    this.isPinned = false,
    required this.createdAt,
    required this.updatedAt,
    this.noteCount = 0,
  });

  factory Folder.create({
    required String name,
    String? coverImagePath,
    String? colorAccent,
    bool isPinned = false,
  }) {
    final now = DateTime.now();
    return Folder(
      id: const Uuid().v4(),
      name: name.trim(),
      coverImagePath: coverImagePath,
      colorAccent: colorAccent ?? '#EF4444',
      isPinned: isPinned,
      createdAt: now,
      updatedAt: now,
      noteCount: 0,
    );
  }

  Folder copyWith({
    String? name,
    String? coverImagePath,
    bool clearCoverImage = false,
    String? colorAccent,
    bool? isPinned,
    DateTime? updatedAt,
    int? noteCount,
  }) {
    return Folder(
      id: id,
      name: name ?? this.name,
      coverImagePath: clearCoverImage ? null : (coverImagePath ?? this.coverImagePath),
      colorAccent: colorAccent ?? this.colorAccent,
      isPinned: isPinned ?? this.isPinned,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      noteCount: noteCount ?? this.noteCount,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'cover_image_path': coverImagePath,
      'color_accent': colorAccent,
      'is_pinned': isPinned ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory Folder.fromMap(Map<String, dynamic> map, {int noteCount = 0}) {
    return Folder(
      id: map['id'] as String,
      name: map['name'] as String? ?? 'Untitled',
      coverImagePath: map['cover_image_path'] as String?,
      colorAccent: map['color_accent'] as String? ?? '#EF4444',
      isPinned: (map['is_pinned'] as int? ?? 0) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      noteCount: noteCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Folder &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          coverImagePath == other.coverImagePath &&
          colorAccent == other.colorAccent &&
          isPinned == other.isPinned &&
          noteCount == other.noteCount &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      (coverImagePath?.hashCode ?? 0) ^
      (colorAccent?.hashCode ?? 0) ^
      isPinned.hashCode ^
      noteCount.hashCode ^
      updatedAt.hashCode;
}

