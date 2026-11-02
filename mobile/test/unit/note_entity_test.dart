import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbrain/domain/entities/note.dart';

void main() {
  group('Note Entity', () {
    test('create generates unique id, cleans tags, and sets timestamps', () {
      final note = Note.create(
        title: ' Architecture Decision ',
        content: ' Use SQLite for local storage ',
        tags: [' Flutter ', 'SQLite', 'ARCHITECTURE'],
        projectId: 'pocketbrain',
        isPinned: true,
      );

      expect(note.id, isNotEmpty);
      expect(note.title, 'Architecture Decision');
      expect(note.content, 'Use SQLite for local storage');
      expect(note.tags, ['flutter', 'sqlite', 'architecture']);
      expect(note.projectId, 'pocketbrain');
      expect(note.isPinned, isTrue);
      expect(note.isArchived, isFalse);
      expect(note.isDeleted, isFalse);
      expect(note.createdAt, isNotNull);
      expect(note.updatedAt, isNotNull);
      expect(note.serverVersion, 0);
    });

    test('copyWith updates specified fields and preserves others', () {
      final original = Note.create(
        title: 'Original Title',
        content: 'Original Content',
        tags: ['tag1'],
      );

      final updated = original.copyWith(
        title: 'Updated Title',
        isPinned: true,
        isArchived: true,
      );

      expect(updated.id, original.id);
      expect(updated.title, 'Updated Title');
      expect(updated.content, 'Original Content');
      expect(updated.tags, ['tag1']);
      expect(updated.isPinned, isTrue);
      expect(updated.isArchived, isTrue);
      expect(updated.createdAt, original.createdAt);
    });

    test('toMap and fromMap serialize and deserialize accurately', () {
      final note = Note.create(
        title: 'Serialization Test',
        content: 'Testing SQLite serialization',
        tags: ['test', 'dart'],
        projectId: 'project-a',
        isPinned: true,
      );

      final map = note.toMap();
      expect(map['id'], note.id);
      expect(map['title'], 'Serialization Test');
      expect(map['is_pinned'], 1);
      expect(map['is_archived'], 0);
      expect(map['is_deleted'], 0);

      final restored = Note.fromMap(map, tags: ['test', 'dart']);
      expect(restored.id, note.id);
      expect(restored.title, note.title);
      expect(restored.content, note.content);
      expect(restored.tags, ['test', 'dart']);
      expect(restored.projectId, note.projectId);
      expect(restored.isPinned, isTrue);
      expect(restored.isArchived, isFalse);
      expect(restored.isDeleted, isFalse);
    });
  });
}
