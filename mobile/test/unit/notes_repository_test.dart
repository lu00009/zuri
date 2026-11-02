import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pocketbrain/domain/entities/note.dart';
import 'package:pocketbrain/data/repositories/notes_repository.dart';

void main() {
  late Database testDb;
  late NotesLocalRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // In-memory isolated database for each test
    testDb = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE notes (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              content TEXT NOT NULL,
              project_id TEXT,
              is_pinned INTEGER NOT NULL DEFAULT 0,
              is_archived INTEGER NOT NULL DEFAULT 0,
              is_deleted INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              server_version INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE note_tags (
              note_id TEXT NOT NULL,
              tag TEXT NOT NULL,
              PRIMARY KEY (note_id, tag),
              FOREIGN KEY (note_id) REFERENCES notes(id) ON DELETE CASCADE
            )
          ''');
          await db.execute('''
            CREATE TABLE sync_operations (
              op_id TEXT PRIMARY KEY,
              entity_type TEXT NOT NULL,
              entity_id TEXT NOT NULL,
              op_type TEXT NOT NULL,
              payload TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              attempts INTEGER NOT NULL DEFAULT 0,
              last_error TEXT
            )
          ''');
        },
      ),
    );
    repository = NotesLocalRepository(overrideDb: testDb);
  });

  tearDown(() async {
    await testDb.close();
  });

  group('NotesLocalRepository CRUD & Queries', () {
    test('saveNote inserts and retrieves a note with tags', () async {
      final note = Note.create(
        title: 'Meeting Notes',
        content: 'Discussed sync architecture and SQLite schemas.',
        tags: ['work', 'sync'],
        projectId: 'pocketbrain',
      );

      await repository.saveNote(note);

      final retrieved = await repository.getNoteById(note.id);
      expect(retrieved, isNotNull);
      expect(retrieved!.id, note.id);
      expect(retrieved.title, 'Meeting Notes');
      expect(retrieved.tags, containsAll(['work', 'sync']));
      expect(retrieved.projectId, 'pocketbrain');
    });

    test('getNotes filters by text search across title and content', () async {
      final note1 = Note.create(
        title: 'Flutter Riverpod Guide',
        content: 'State management and dependency injection',
        tags: ['flutter'],
      );
      final note2 = Note.create(
        title: 'Python FastAPI Notes',
        content: 'Building asynchronous APIs with Pydantic',
        tags: ['python'],
      );

      await repository.saveNote(note1);
      await repository.saveNote(note2);

      // Search matching title
      final titleMatch = await repository.getNotes(searchQuery: 'Riverpod');
      expect(titleMatch.length, 1);
      expect(titleMatch.first.id, note1.id);

      // Search matching content
      final contentMatch = await repository.getNotes(searchQuery: 'Pydantic');
      expect(contentMatch.length, 1);
      expect(contentMatch.first.id, note2.id);

      // Non-matching search
      final noMatch = await repository.getNotes(searchQuery: 'Kubernetes');
      expect(noMatch, isEmpty);
    });

    test('getNotes filters by tag and project', () async {
      final note1 = Note.create(
        title: 'Note A',
        content: 'Content A',
        tags: ['ai', 'research'],
        projectId: 'project-1',
      );
      final note2 = Note.create(
        title: 'Note B',
        content: 'Content B',
        tags: ['mobile', 'research'],
        projectId: 'project-2',
      );

      await repository.saveNote(note1);
      await repository.saveNote(note2);

      final tagResults = await repository.getNotes(tag: 'ai');
      expect(tagResults.length, 1);
      expect(tagResults.first.id, note1.id);

      final commonTagResults = await repository.getNotes(tag: 'research');
      expect(commonTagResults.length, 2);

      final projectResults = await repository.getNotes(projectId: 'project-2');
      expect(projectResults.length, 1);
      expect(projectResults.first.id, note2.id);
    });

    test('togglePin updates note pinning status', () async {
      final note = Note.create(
        title: 'Important Note',
        content: 'Remember this',
        isPinned: false,
      );
      await repository.saveNote(note);

      await repository.togglePin(note.id);
      final pinned = await repository.getNoteById(note.id);
      expect(pinned!.isPinned, isTrue);

      await repository.togglePin(note.id);
      final unpinned = await repository.getNoteById(note.id);
      expect(unpinned!.isPinned, isFalse);
    });

    test('setArchived toggles note between active and archive views', () async {
      final note = Note.create(
        title: 'Old Note',
        content: 'Archive this',
        isPinned: true,
      );
      await repository.saveNote(note);

      // Archive it
      await repository.setArchived(note.id, true);

      // Should not appear in active notes
      final activeNotes = await repository.getNotes(includeArchived: false);
      expect(activeNotes, isEmpty);

      // Should appear in archive notes (and unpinned)
      final archivedNotes = await repository.getNotes(includeArchived: true);
      expect(archivedNotes.length, 1);
      expect(archivedNotes.first.isArchived, isTrue);
      expect(archivedNotes.first.isPinned, isFalse);
    });

    test('deleteNote soft-deletes record', () async {
      final note = Note.create(
        title: 'Note to Delete',
        content: 'Will be deleted',
      );
      await repository.saveNote(note);

      await repository.deleteNote(note.id, softDelete: true);

      final active = await repository.getNotes();
      expect(active, isEmpty);

      final byId = await repository.getNoteById(note.id);
      expect(byId, isNull);
    });

    test('getAllTags returns distinct tags alphabetically', () async {
      final note1 = Note.create(
        title: 'Note 1',
        content: 'c',
        tags: ['zebra', 'apple'],
      );
      final note2 = Note.create(
        title: 'Note 2',
        content: 'c',
        tags: ['banana', 'apple'],
      );
      await repository.saveNote(note1);
      await repository.saveNote(note2);

      final tags = await repository.getAllTags();
      expect(tags, ['apple', 'banana', 'zebra']);
    });
  });
}
