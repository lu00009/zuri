import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/folder.dart';
import '../../data/repositories/folders_repository.dart';
import 'auth_provider.dart';
import 'notes_provider.dart';

final foldersRepositoryProvider = Provider<FoldersRepository>((ref) {
  final authState = ref.watch(authProvider);
  return FoldersLocalRepository(userId: authState.user?.id);
});

class FoldersState {
  final List<Folder> folders;
  final bool isLoading;
  final String? errorMessage;
  final String searchQuery;

  const FoldersState({
    this.folders = const [],
    this.isLoading = false,
    this.errorMessage,
    this.searchQuery = '',
  });

  FoldersState copyWith({
    List<Folder>? folders,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    String? searchQuery,
  }) {
    return FoldersState(
      folders: folders ?? this.folders,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

class FoldersNotifier extends StateNotifier<FoldersState> {
  final FoldersRepository repository;
  final Ref ref;

  FoldersNotifier({
    required this.repository,
    required this.ref,
  }) : super(const FoldersState()) {
    loadFolders();
  }

  Future<void> loadFolders() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final folders = await repository.getFolders(
        searchQuery: state.searchQuery.isNotEmpty ? state.searchQuery : null,
      );
      state = state.copyWith(folders: folders, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load folders: $e',
      );
    }
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
    loadFolders();
  }

  Future<Folder?> createFolder({
    required String name,
    String? coverImagePath,
    String? colorAccent,
  }) async {
    final clean = name.trim();
    if (clean.isEmpty) return null;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      var finalCover = coverImagePath;
      final tempId = Folder.create(name: clean).id;
      if (coverImagePath != null && coverImagePath.isNotEmpty) {
        finalCover = await repository.copyAndSaveCoverImage(tempId, coverImagePath);
      }

      final folder = Folder(
        id: tempId,
        name: clean,
        coverImagePath: finalCover,
        colorAccent: colorAccent ?? '#EF4444',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        noteCount: 0,
      );

      await repository.saveFolder(folder);
      await loadFolders();
      return folder;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to create folder: $e',
      );
      return null;
    }
  }

  Future<bool> updateFolder({
    required String id,
    String? name,
    String? coverImagePath,
    bool clearCoverImage = false,
    String? colorAccent,
  }) async {
    try {
      final existing = await repository.getFolderById(id);
      if (existing == null) return false;

      var finalCover = existing.coverImagePath;
      if (clearCoverImage) {
        finalCover = null;
      } else if (coverImagePath != null && coverImagePath != existing.coverImagePath) {
        finalCover = await repository.copyAndSaveCoverImage(id, coverImagePath);
      }

      final updated = existing.copyWith(
        name: name?.trim().isNotEmpty == true ? name!.trim() : existing.name,
        coverImagePath: finalCover,
        clearCoverImage: clearCoverImage,
        colorAccent: colorAccent ?? existing.colorAccent,
        updatedAt: DateTime.now(),
      );

      await repository.saveFolder(updated);
      await loadFolders();
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to update folder: $e');
      return false;
    }
  }

  Future<void> deleteFolder(String id) async {
    try {
      await repository.deleteFolder(id);
      await loadFolders();
      // Refresh notes list to reflect unassigned notes
      ref.read(notesListProvider.notifier).loadNotes();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to delete folder: $e');
    }
  }

  Future<void> togglePin(String id) async {
    try {
      await repository.togglePin(id);
      await loadFolders();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to pin folder: $e');
    }
  }

  Future<void> moveNoteToFolder({required String noteId, required String? folderId}) async {
    try {
      await repository.moveNoteToFolder(noteId: noteId, folderId: folderId);
      await loadFolders();
      ref.read(notesListProvider.notifier).loadNotes();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to move note: $e');
    }
  }

  Future<void> removeNoteFromFolder(String noteId) async {
    await moveNoteToFolder(noteId: noteId, folderId: null);
  }
}

final foldersListProvider =
    StateNotifierProvider<FoldersNotifier, FoldersState>((ref) {
  final repo = ref.watch(foldersRepositoryProvider);
  return FoldersNotifier(repository: repo, ref: ref);
});

final folderDetailProvider = FutureProvider.family<Folder?, String>((ref, folderId) async {
  final repo = ref.watch(foldersRepositoryProvider);
  return repo.getFolderById(folderId);
});
