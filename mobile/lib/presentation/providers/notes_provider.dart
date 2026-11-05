import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/notes_repository.dart';
import '../../domain/entities/note.dart';
import 'auth_provider.dart';

final notesRepositoryProvider = Provider<NotesRepository>((ref) {
  final authState = ref.watch(authProvider);
  final userId = authState.user?.id ?? authState.user?.email;
  return NotesLocalRepository(userId: userId);
});

class NotesListState {
  final bool isLoading;
  final List<Note> notes;
  final List<String> availableTags;
  final String? selectedTag;
  final String? selectedProject;
  final String searchQuery;
  final bool isArchiveView;
  final String? errorMessage;

  const NotesListState({
    this.isLoading = false,
    this.notes = const [],
    this.availableTags = const [],
    this.selectedTag,
    this.selectedProject,
    this.searchQuery = '',
    this.isArchiveView = false,
    this.errorMessage,
  });

  NotesListState copyWith({
    bool? isLoading,
    List<Note>? notes,
    List<String>? availableTags,
    String? selectedTag,
    bool clearSelectedTag = false,
    String? selectedProject,
    bool clearSelectedProject = false,
    String? searchQuery,
    bool? isArchiveView,
    String? errorMessage,
    bool clearError = false,
  }) {
    return NotesListState(
      isLoading: isLoading ?? this.isLoading,
      notes: notes ?? this.notes,
      availableTags: availableTags ?? this.availableTags,
      selectedTag: clearSelectedTag ? null : (selectedTag ?? this.selectedTag),
      selectedProject: clearSelectedProject ? null : (selectedProject ?? this.selectedProject),
      searchQuery: searchQuery ?? this.searchQuery,
      isArchiveView: isArchiveView ?? this.isArchiveView,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class NotesListNotifier extends StateNotifier<NotesListState> {
  final NotesRepository _repository;

  NotesListNotifier(this._repository) : super(const NotesListState(isLoading: true)) {
    loadNotes();
  }

  Future<void> loadNotes() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final notes = await _repository.getNotes(
        includeArchived: state.isArchiveView,
        searchQuery: state.searchQuery,
        tag: state.selectedTag,
        projectId: state.selectedProject,
      );
      final tags = await _repository.getAllTags();
      state = state.copyWith(
        isLoading: false,
        notes: notes,
        availableTags: tags,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load notes: $e',
      );
    }
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
    loadNotes();
  }

  void selectTag(String? tag) {
    if (state.selectedTag == tag) {
      // Toggle off
      state = state.copyWith(clearSelectedTag: true);
    } else {
      state = state.copyWith(selectedTag: tag);
    }
    loadNotes();
  }

  void toggleArchiveView() {
    state = state.copyWith(
      isArchiveView: !state.isArchiveView,
      clearSelectedTag: true,
      searchQuery: '',
    );
    loadNotes();
  }

  Future<void> togglePin(String id) async {
    try {
      await _repository.togglePin(id);
      await loadNotes();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to update pin: $e');
    }
  }

  Future<void> setArchived(String id, bool isArchived) async {
    try {
      await _repository.setArchived(id, isArchived);
      await loadNotes();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to update archive status: $e');
    }
  }

  Future<void> deleteNote(String id) async {
    try {
      await _repository.deleteNote(id, softDelete: true);
      await loadNotes();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to delete note: $e');
    }
  }

  void clearNotes() {
    state = const NotesListState(isLoading: false, notes: [], availableTags: []);
  }
}

final notesListProvider = StateNotifierProvider<NotesListNotifier, NotesListState>((ref) {
  final repo = ref.watch(notesRepositoryProvider);
  return NotesListNotifier(repo);
});
