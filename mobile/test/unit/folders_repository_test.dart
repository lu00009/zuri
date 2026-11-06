import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pocketbrain/domain/entities/folder.dart';
import 'package:pocketbrain/domain/entities/note.dart';
import 'package:pocketbrain/data/repositories/folders_repository.dart';
import 'package:pocketbrain/data/repositories/notes_repository.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late FoldersLocalRepository foldersRepo;
  late NotesLocalRepository notesRepo;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    // Initialize schema
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
        PRIMARY KEY (note_id, tag)
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
    await db.execute('''
      CREATE TABLE folders (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        cover_image_path TEXT,
        color_accent TEXT,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    foldersRepo = FoldersLocalRepository(overrideDatabase: db);
    notesRepo = NotesLocalRepository(overrideDb: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Folders Repository Tests', () {
    test('Create and retrieve folders with note counts', () async {
      final f1 = Folder.create(name: 'YouTube Ideas', colorAccent: '#EF4444');
      final f2 = Folder.create(name: 'User Research', colorAccent: '#3B82F6');

      await foldersRepo.saveFolder(f1);
      await foldersRepo.saveFolder(f2);

      // Create notes inside f1
      final n1 = Note.create(title: 'Video Script 1', content: 'Intro', projectId: f1.id);
      final n2 = Note.create(title: 'Video Script 2', content: 'Body', projectId: f1.id);
      final n3 = Note.create(title: 'General Note', content: 'Not in folder');

      await notesRepo.saveNote(n1);
      await notesRepo.saveNote(n2);
      await notesRepo.saveNote(n3);

      final folders = await foldersRepo.getFolders();
      expect(folders.length, 2);

      final ytFolder = folders.firstWhere((f) => f.id == f1.id);
      expect(ytFolder.name, 'YouTube Ideas');
      expect(ytFolder.noteCount, 2);

      final researchFolder = folders.firstWhere((f) => f.id == f2.id);
      expect(researchFolder.name, 'User Research');
      expect(researchFolder.noteCount, 0);
    });

    test('Pinned folder sorts first and toggling pin works', () async {
      final f1 = Folder.create(name: 'Alpha Folder');
      final f2 = Folder.create(name: 'Beta Folder', isPinned: true);

      await foldersRepo.saveFolder(f1);
      await foldersRepo.saveFolder(f2);

      var folders = await foldersRepo.getFolders();
      expect(folders.first.name, 'Beta Folder');

      // Toggle pin on f2 -> unpin
      await foldersRepo.togglePin(f2.id);
      folders = await foldersRepo.getFolders();
      final updatedF2 = folders.firstWhere((f) => f.id == f2.id);
      expect(updatedF2.isPinned, false);
    });

    test('Moving note to folder and removing note from folder', () async {
      final folder = Folder.create(name: 'Projects');
      await foldersRepo.saveFolder(folder);

      final note = Note.create(title: 'Architecture Doc', content: 'System design');
      await notesRepo.saveNote(note);

      expect(note.projectId, isNull);

      // Move into folder
      await foldersRepo.moveNoteToFolder(noteId: note.id, folderId: folder.id);

      var updatedNote = await notesRepo.getNoteById(note.id);
      expect(updatedNote?.projectId, folder.id);

      var folders = await foldersRepo.getFolders();
      expect(folders.first.noteCount, 1);

      // Remove from folder
      await foldersRepo.removeNoteFromFolder(note.id);
      updatedNote = await notesRepo.getNoteById(note.id);
      expect(updatedNote?.projectId, isNull);

      folders = await foldersRepo.getFolders();
      expect(folders.first.noteCount, 0);
    });

    test('Deleting a folder preserves notes and sets their project_id to NULL', () async {
      final folder = Folder.create(name: 'Temporary Folder');
      await foldersRepo.saveFolder(folder);

      final note1 = Note.create(title: 'Saved Note 1', content: 'Keep this', projectId: folder.id);
      final note2 = Note.create(title: 'Saved Note 2', content: 'Keep this too', projectId: folder.id);
      await notesRepo.saveNote(note1);
      await notesRepo.saveNote(note2);

      // Delete folder
      await foldersRepo.deleteFolder(folder.id);

      // Verify folder deleted
      final folders = await foldersRepo.getFolders();
      expect(folders.isEmpty, true);

      // Verify notes are STILL alive and unassigned
      final n1 = await notesRepo.getNoteById(note1.id);
      final n2 = await notesRepo.getNoteById(note2.id);

      expect(n1, isNotNull);
      expect(n1?.projectId, isNull);
      expect(n1?.title, 'Saved Note 1');

      expect(n2, isNotNull);
      expect(n2?.projectId, isNull);
      expect(n2?.title, 'Saved Note 2');
    });
  });
}
