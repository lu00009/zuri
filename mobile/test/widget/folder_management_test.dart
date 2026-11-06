import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbrain/domain/entities/folder.dart';
import 'package:pocketbrain/domain/entities/note.dart';
import 'package:pocketbrain/data/repositories/folders_repository.dart';
import 'package:pocketbrain/data/repositories/notes_repository.dart';
import 'package:pocketbrain/presentation/providers/folders_provider.dart';
import 'package:pocketbrain/presentation/providers/notes_provider.dart';
import 'package:pocketbrain/presentation/screens/folder_detail_screen.dart';
import 'package:pocketbrain/presentation/screens/home_screen.dart';
import 'package:pocketbrain/presentation/widgets/create_folder_dialog.dart';

class FakeFoldersRepository implements FoldersRepository {
  List<Folder> folders;

  FakeFoldersRepository(this.folders);

  @override
  Future<List<Folder>> getFolders({String? searchQuery}) async {
    if (searchQuery != null && searchQuery.isNotEmpty) {
      return folders
          .where((f) => f.name.toLowerCase().contains(searchQuery.toLowerCase()))
          .toList();
    }
    return List.from(folders);
  }

  @override
  Future<Folder?> getFolderById(String id) async {
    try {
      return folders.firstWhere((f) => f.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveFolder(Folder folder) async {
    folders.removeWhere((f) => f.id == folder.id);
    folders.insert(0, folder);
  }

  @override
  Future<void> deleteFolder(String id) async {
    folders.removeWhere((f) => f.id == id);
  }

  @override
  Future<void> togglePin(String id) async {
    final idx = folders.indexWhere((f) => f.id == id);
    if (idx != -1) {
      final f = folders[idx];
      folders[idx] = f.copyWith(isPinned: !f.isPinned);
    }
  }

  @override
  Future<void> moveNoteToFolder({required String noteId, required String? folderId}) async {}

  @override
  Future<void> removeNoteFromFolder(String noteId) async {}

  @override
  Future<String?> copyAndSaveCoverImage(String folderId, String sourceFilePath) async {
    return sourceFilePath;
  }
}

class FakeNotesRepo implements NotesRepository {
  List<Note> notes;
  FakeNotesRepo(this.notes);

  @override
  Future<List<Note>> getNotes({bool includeArchived = false, String? searchQuery, String? tag, String? projectId}) async {
    return notes.where((n) {
      if (projectId != null && n.projectId != projectId) return false;
      return true;
    }).toList();
  }

  @override
  Future<Note?> getNoteById(String id) async {
    try {
      return notes.firstWhere((n) => n.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveNote(Note note, {bool isRemoteSync = false}) async {
    notes.removeWhere((n) => n.id == note.id);
    notes.insert(0, note);
  }

  @override
  Future<void> deleteNote(String id, {bool softDelete = true, bool isRemoteSync = false}) async {
    notes.removeWhere((n) => n.id == id);
  }

  @override
  Future<void> togglePin(String id) async {}

  @override
  Future<void> setArchived(String id, bool isArchived) async {}

  @override
  Future<List<String>> getAllTags() async => [];

  @override
  Future<List<String>> getAllProjects() async => [];

  @override
  Future<void> clearAllLocalData() async {}
}

void main() {
  testWidgets('Home screen renders Notebooks and Notes matching reference layout', (tester) async {
    final f1 = Folder.create(name: 'YouTube Ideas', colorAccent: '#EF4444').copyWith(noteCount: 3);
    final f2 = Folder.create(name: 'User Research', colorAccent: '#3B82F6').copyWith(noteCount: 1);

    final n1 = Note.create(title: 'Web Ideas', content: 'Ladakh Tourism, Electric Scooter', projectId: f1.id);
    final n2 = Note.create(title: 'The Role Of Creativity', content: 'What is creativity in UX design?');

    final fakeFoldersRepo = FakeFoldersRepository([f1, f2]);
    final fakeNotesRepo = FakeNotesRepo([n1, n2]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          foldersRepositoryProvider.overrideWithValue(fakeFoldersRepo),
          notesRepositoryProvider.overrideWithValue(fakeNotesRepo),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Verify title is cleanly Zuri, and big Home text is removed
    expect(find.text('Zuri'), findsOneWidget);
    expect(find.text('Home'), findsNothing);

    // Verify sections
    expect(find.text('Notebooks'), findsOneWidget);
    expect(find.text('YouTube Ideas'), findsWidgets);
    expect(find.text('User Research'), findsOneWidget);
    expect(find.text('3 notes'), findsOneWidget);
    expect(find.text('1 note'), findsOneWidget);

    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Web Ideas'), findsOneWidget);
    expect(find.text('The Role Of Creativity'), findsOneWidget);

    // Verify FAB at bottom right
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.floatingActionButtonLocation, FloatingActionButtonLocation.endFloat);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    // Verify theme toggle button
    expect(find.byKey(const Key('home_theme_toggle_button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('home_theme_toggle_button')));
    await tester.pumpAndSettle();

    // Tap FAB -> Opens Bottom Sheet
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // Verify Options in bottom sheet
    expect(find.text('Add Notebook'), findsOneWidget);
    expect(find.text('Add Note'), findsOneWidget);
  });

  testWidgets('CreateFolderDialog renders name input and cover options', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CreateFolderDialog(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('New Notebook'), findsOneWidget);
    expect(find.text('Choose Cover from Gallery'), findsOneWidget);
    expect(find.text('Spine Color Accent'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
  });

  testWidgets('FolderDetailScreen renders notebook banner and notes inside', (tester) async {
    final folder = Folder.create(name: 'YouTube Ideas', colorAccent: '#EF4444');
    final note = Note.create(title: 'Camera Setup', content: 'Sony A7IV', projectId: folder.id);

    final fakeFoldersRepo = FakeFoldersRepository([folder]);
    final fakeNotesRepo = FakeNotesRepo([note]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          foldersRepositoryProvider.overrideWithValue(fakeFoldersRepo),
          notesRepositoryProvider.overrideWithValue(fakeNotesRepo),
        ],
        child: MaterialApp(
          home: FolderDetailScreen(folderId: folder.id),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('YouTube Ideas'), findsWidgets);
    expect(find.text('1 note inside'), findsOneWidget);
    expect(find.text('Add Note Here'), findsOneWidget);
    expect(find.text('Camera Setup'), findsOneWidget);
  });
}
