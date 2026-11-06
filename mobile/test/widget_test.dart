import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbrain/app.dart';
import 'package:pocketbrain/domain/entities/note.dart';
import 'package:pocketbrain/data/repositories/notes_repository.dart';
import 'package:pocketbrain/presentation/providers/notes_provider.dart';

class FakeNotesRepository implements NotesRepository {
  final List<Note> _notes = [];

  FakeNotesRepository([List<Note>? initialNotes]) {
    if (initialNotes != null) {
      _notes.addAll(initialNotes);
    }
  }

  @override
  Future<List<Note>> getNotes({
    bool includeArchived = false,
    String? searchQuery,
    String? tag,
    String? projectId,
  }) async {
    return _notes.where((n) {
      if (n.isDeleted) return false;
      if (n.isArchived != includeArchived) return false;
      if (projectId != null && n.projectId != projectId) return false;
      if (tag != null && !n.tags.contains(tag.toLowerCase())) return false;
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final query = searchQuery.toLowerCase();
        final matchesTitle = n.title.toLowerCase().contains(query);
        final matchesContent = n.content.toLowerCase().contains(query);
        if (!matchesTitle && !matchesContent) return false;
      }
      return true;
    }).toList()..sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
  }

  @override
  Future<Note?> getNoteById(String id) async {
    try {
      return _notes.firstWhere((n) => n.id == id && !n.isDeleted);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveNote(Note note, {bool isRemoteSync = false}) async {
    final index = _notes.indexWhere((n) => n.id == note.id);
    if (index >= 0) {
      _notes[index] = note;
    } else {
      _notes.add(note);
    }
  }

  @override
  Future<void> togglePin(String id) async {
    final note = await getNoteById(id);
    if (note != null) {
      await saveNote(note.copyWith(isPinned: !note.isPinned));
    }
  }

  @override
  Future<void> setArchived(String id, bool isArchived) async {
    final note = await getNoteById(id);
    if (note != null) {
      await saveNote(
        note.copyWith(
          isArchived: isArchived,
          isPinned: isArchived ? false : note.isPinned,
        ),
      );
    }
  }

  @override
  Future<void> deleteNote(
    String id, {
    bool softDelete = true,
    bool isRemoteSync = false,
  }) async {
    final note = await getNoteById(id);
    if (note != null) {
      if (softDelete) {
        await saveNote(note.copyWith(isDeleted: true));
      } else {
        _notes.removeWhere((n) => n.id == id);
      }
    }
  }

  @override
  Future<List<String>> getAllTags() async {
    final tags = <String>{};
    for (final n in _notes) {
      if (!n.isDeleted) {
        tags.addAll(n.tags);
      }
    }
    final sorted = tags.toList()..sort();
    return sorted;
  }

  @override
  Future<List<String>> getAllProjects() async {
    final projects = <String>{};
    for (final n in _notes) {
      if (!n.isDeleted && n.projectId != null && n.projectId!.isNotEmpty) {
        projects.add(n.projectId!);
      }
    }
    final sorted = projects.toList()..sort();
    return sorted;
  }

  @override
  Future<void> clearAllLocalData() async {
    _notes.clear();
  }
}

void main() {
  testWidgets('PocketBrain Phase 2 Empty State and FAB test', (
    WidgetTester tester,
  ) async {
    final fakeRepo = FakeNotesRepository([]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [notesRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const PocketBrainApp(),
      ),
    );

    // Initial load pump
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Verify app bar title
    expect(find.text('Zuri'), findsOneWidget);

    // Verify empty state message
    expect(find.text('No notes yet'), findsOneWidget);
    // expect(find.text('Offline Storage Active'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('PocketBrain displays notes, supports search and archive view', (
    WidgetTester tester,
  ) async {
    final note1 = Note.create(
      title: 'First Thought',
      content: 'Local SQLite offline storage works seamlessly',
      tags: ['sqlite', 'offline'],
      isPinned: true,
    );
    final note2 = Note.create(
      title: 'Second Thought',
      content: 'FastAPI sync will follow in Phase 3',
      tags: ['backend'],
    );
    final fakeRepo = FakeNotesRepository([note1, note2]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [notesRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const PocketBrainApp(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Verify both notes are shown
    expect(find.text('First Thought'), findsOneWidget);
    expect(find.text('Second Thought'), findsOneWidget);
    // Verify tags are rendered in both filter bar and note cards
    expect(find.text('#sqlite'), findsNWidgets(2));
    expect(find.text('#backend'), findsNWidgets(2));

    // Test search filter
    await tester.enterText(find.byType(SearchBar), 'First');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('First Thought'), findsOneWidget);
    expect(find.text('Second Thought'), findsNothing);

    // Clear search
    await tester.enterText(find.byType(SearchBar), '');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('First Thought'), findsOneWidget);
    expect(find.text('Second Thought'), findsOneWidget);

    // Test toggle to Archive view via Account dialog or direct action
    await tester.tap(find.byKey(const Key('home_account_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View Archived Notes'));
    // Settle archive switch and FAB exit animation
    await tester.pumpAndSettle();

    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Archive is empty'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
