import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../domain/entities/folder.dart';
import '../../domain/entities/note.dart';
import '../providers/folders_provider.dart';
import '../providers/notes_provider.dart';
import '../widgets/create_folder_dialog.dart';
import '../widgets/move_to_folder_dialog.dart';
import '../widgets/notebook_illustration.dart';

class FolderDetailScreen extends ConsumerStatefulWidget {
  final String folderId;

  const FolderDetailScreen({super.key, required this.folderId});

  @override
  ConsumerState<FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends ConsumerState<FolderDetailScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showDeleteConfirmation(Folder folder) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Notebook?',
          style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete "${folder.name}"? All notes inside this notebook will be preserved safely.',
          style: TextStyle(color: isDark ? const Color(0xFF9E9EA7) : const Color(0xFF64748B)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF64748B))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(foldersListProvider.notifier).deleteFolder(folder.id);
              if (mounted) context.pop();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(Folder folder) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => CreateFolderDialog(folderToEdit: folder),
    );

    if (result != null) {
      await ref.read(foldersListProvider.notifier).updateFolder(
            id: folder.id,
            name: result['name'] as String?,
            coverImagePath: result['coverImagePath'] as String?,
            clearCoverImage: result['clearCoverImage'] as bool? ?? false,
            colorAccent: result['colorAccent'] as String?,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final foldersState = ref.watch(foldersListProvider);
    final allNotes = ref.watch(notesListProvider).notes;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Find the current folder
    final folder = foldersState.folders.firstWhere(
      (f) => f.id == widget.folderId,
      orElse: () => Folder(
        id: widget.folderId,
        name: 'Notebook',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    // Notes belonging to this folder
    final folderNotes = allNotes.where((n) {
      if (n.projectId != widget.folderId) return false;
      if (_searchQuery.isEmpty) return true;
      return n.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          n.content.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface),
          onPressed: () => context.pop(),
        ),
        title: Text(
          folder.name,
          style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: Icon(
              folder.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              color: folder.isPinned ? const Color(0xFFFACC15) : theme.colorScheme.onSurface,
            ),
            tooltip: folder.isPinned ? 'Unpin Notebook' : 'Pin Notebook',
            onPressed: () => ref.read(foldersListProvider.notifier).togglePin(folder.id),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: theme.colorScheme.onSurface),
            color: isDark ? const Color(0xFF26262B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (val) {
              if (val == 'edit') _showEditDialog(folder);
              if (val == 'delete') _showDeleteConfirmation(folder);
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 16, color: theme.colorScheme.onSurface),
                    const SizedBox(width: 10),
                    Text('Edit Notebook', style: TextStyle(color: theme.colorScheme.onSurface)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444)),
                    SizedBox(width: 10),
                    Text('Delete Notebook', style: TextStyle(color: Color(0xFFEF4444))),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Folder Banner Header
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E22) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? Colors.white.withAlpha(15) : const Color(0xFFE2E8F0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark ? Colors.black.withAlpha(50) : Colors.black.withAlpha(10),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  NotebookIllustration(
                    coverImagePath: folder.coverImagePath,
                    colorAccentHex: folder.colorAccent,
                    width: 72,
                    height: 90,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          folder.name,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${folderNotes.length} ${folderNotes.length == 1 ? 'note' : 'notes'} inside',
                          style: TextStyle(
                            color: isDark ? const Color(0xFF9E9EA7) : const Color(0xFF64748B),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.tonalIcon(
                          onPressed: () {
                            context.push('/note/new?folderId=${folder.id}');
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add Note Here', style: TextStyle(fontSize: 12)),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF3B82F6).withAlpha(40),
                            foregroundColor: const Color(0xFF60A5FA),
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Search Bar in Folder
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: SearchBar(
                controller: _searchController,
                hintText: 'Search in this notebook...',
                hintStyle: WidgetStatePropertyAll(
                  TextStyle(
                    color: isDark ? Colors.white.withAlpha(80) : const Color(0xFF94A3B8),
                    fontSize: 13,
                  ),
                ),
                textStyle: WidgetStatePropertyAll(
                  TextStyle(color: theme.colorScheme.onSurface, fontSize: 14),
                ),
                leading: Icon(
                  Icons.search,
                  color: isDark ? const Color(0xFF9E9EA7) : const Color(0xFF64748B),
                ),
                trailing: [
                  if (_searchQuery.isNotEmpty)
                    IconButton(
                      icon: Icon(
                        Icons.clear,
                        color: isDark ? Colors.grey : const Color(0xFF64748B),
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    ),
                ],
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
                elevation: const WidgetStatePropertyAll(0),
                backgroundColor: WidgetStatePropertyAll(
                  isDark ? const Color(0xFF1E1E22) : Colors.white,
                ),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: isDark ? Colors.white.withAlpha(15) : const Color(0xFFE2E8F0),
                    ),
                  ),
                ),
              ),
            ),

            // Notes List / Grid
            Expanded(
              child: folderNotes.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.note_alt_outlined,
                              size: 48,
                              color: isDark ? Colors.white.withAlpha(60) : const Color(0xFF94A3B8),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _searchQuery.isNotEmpty ? 'No matching notes' : 'No notes in this notebook',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Tap "+ Add Note Here" or move existing notes into this notebook.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isDark ? const Color(0xFF9E9EA7) : const Color(0xFF64748B),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: folderNotes.length,
                      itemBuilder: (ctx, idx) {
                        final note = folderNotes[idx];
                        return _buildFolderNoteCard(note);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderNoteCard(Note note) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(12) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withAlpha(40) : Colors.black.withAlpha(10),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/note/${note.id}'),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (note.isPinned) ...[
                            const Icon(Icons.push_pin, size: 14, color: Color(0xFFFACC15)),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              note.title.isNotEmpty ? note.title : 'Untitled Note',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (note.content.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          note.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark ? const Color(0xFF9E9EA7) : const Color(0xFF64748B),
                            fontSize: 13,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_horiz,
                    color: isDark ? const Color(0xFF9E9EA7) : const Color(0xFF64748B),
                    size: 20,
                  ),
                  color: isDark ? const Color(0xFF26262B) : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (val) {
                    if (val == 'remove') {
                      ref.read(foldersListProvider.notifier).removeNoteFromFolder(note.id);
                    } else if (val == 'move') {
                      showDialog(
                        context: context,
                        builder: (_) => MoveToFolderDialog(note: note),
                      );
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'remove',
                      child: Row(
                        children: [
                          Icon(Icons.folder_off_outlined, size: 16, color: Colors.amber),
                          SizedBox(width: 8),
                          Text('Remove from notebook', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'move',
                      child: Row(
                        children: [
                          Icon(Icons.drive_file_move_outlined, size: 16, color: theme.colorScheme.onSurface),
                          const SizedBox(width: 8),
                          Text('Move to another notebook', style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

