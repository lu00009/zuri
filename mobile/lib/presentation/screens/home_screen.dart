import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/folder.dart';
import '../../domain/entities/note.dart';
import '../providers/auth_provider.dart';
import '../providers/folders_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/sync_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/create_folder_dialog.dart';
import '../widgets/move_to_folder_dialog.dart';
import '../widgets/notebook_card.dart';
import '../widgets/notebook_illustration.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();
  bool _isSearchVisible = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openAddSheet(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1B1B1F) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black54 : Colors.black12,
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withAlpha(50) : const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  // Option 1: Add Notebook
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF26262B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark ? Colors.white.withAlpha(15) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _showCreateFolderDialog();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const NotebookIllustration(
                                  colorAccentHex: '#EF4444',
                                  width: 58,
                                  height: 74,
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'Add Notebook',
                                  style: TextStyle(
                                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Option 2: Add Note
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF26262B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark ? Colors.white.withAlpha(15) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            context.push('/note/new');
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 58,
                                  height: 74,
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF333338) : const Color(0xFFE2E8F0),
                                    borderRadius: BorderRadius.circular(10),
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: isDark
                                          ? const [Color(0xFF3A3A40), Color(0xFF222226)]
                                          : const [Color(0xFFFFFFFF), Color(0xFFE2E8F0)],
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(10),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      for (int i = 0; i < 4; i++) ...[
                                        Row(
                                          children: [
                                            Container(
                                              width: 4,
                                              height: 4,
                                              decoration: BoxDecoration(
                                                color: isDark ? const Color(0xFF6B7280) : const Color(0xFF94A3B8),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 5),
                                            Expanded(
                                              child: Container(
                                                height: 3,
                                                decoration: BoxDecoration(
                                                  color: isDark ? const Color(0xFF52525B) : const Color(0xFFCBD5E1),
                                                  borderRadius: BorderRadius.circular(2),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (i < 3) const SizedBox(height: 6),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'Add Note',
                                  style: TextStyle(
                                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCreateFolderDialog({Folder? folderToEdit}) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => CreateFolderDialog(folderToEdit: folderToEdit),
    );

    if (result != null) {
      if (folderToEdit != null) {
        await ref.read(foldersListProvider.notifier).updateFolder(
              id: folderToEdit.id,
              name: result['name'] as String?,
              coverImagePath: result['coverImagePath'] as String?,
              clearCoverImage: result['clearCoverImage'] as bool? ?? false,
              colorAccent: result['colorAccent'] as String?,
            );
      } else {
        await ref.read(foldersListProvider.notifier).createFolder(
              name: result['name'] as String,
              coverImagePath: result['coverImagePath'] as String?,
              colorAccent: result['colorAccent'] as String?,
            );
      }
    }
  }

  void _showDeleteFolderDialog(Folder folder) {
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
          'Are you sure you want to delete "${folder.name}"? Notes inside this notebook will not be deleted.',
          style: TextStyle(color: isDark ? const Color(0xFF9E9EA7) : const Color(0xFF64748B)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF64748B)),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(foldersListProvider.notifier).deleteFolder(folder.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notesState = ref.watch(notesListProvider);
    final foldersState = ref.watch(foldersListProvider);
    final syncState = ref.watch(syncProvider);
    final notifier = ref.read(notesListProvider.notifier);

    // Map folder IDs to folder names for display on note cards
    final folderMap = {for (final f in foldersState.folders) f.id: f};
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 16,
        title: Text(
          notesState.isArchiveView ? 'Archive' : 'Zuri',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontSize: 26,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          // Theme Mode Toggle (Always visible, bright & unmistakable)
          IconButton(
            key: const Key('home_theme_toggle_button'),
            icon: Icon(
              isDark ? Icons.light_mode : Icons.dark_mode,
              color: isDark ? const Color(0xFFFBBF24) : const Color(0xFF2563EB),
            ),
            tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            onPressed: () => ref.read(themeModeProvider.notifier).toggleTheme(),
          ),
          // Search Toggle
          IconButton(
            icon: Icon(
              _isSearchVisible ? Icons.search_off : Icons.search,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
            tooltip: 'Search notes',
            onPressed: () {
              setState(() {
                _isSearchVisible = !_isSearchVisible;
                if (!_isSearchVisible) {
                  _searchController.clear();
                  notifier.setSearchQuery('');
                  ref.read(foldersListProvider.notifier).setSearchQuery('');
                }
              });
            },
          ),
          // Ask Zuri AI Shortcut
          IconButton(
            icon: const Icon(Icons.auto_awesome, color: Color(0xFF3B82F6)),
            tooltip: 'Ask Zuri',
            onPressed: () => context.push('/ai'),
          ),
          // Account & More Menu (Includes Recap, Archive, Theme & Sign Out)
          IconButton(
            key: const Key('home_account_button'),
            icon: Icon(
              Icons.account_circle_outlined,
              color: isDark ? Colors.white70 : const Color(0xFF475569),
            ),
            tooltip: 'Account & More',
            onPressed: () => _showAccountDialog(context),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: notesState.isArchiveView
          ? null
          : FloatingActionButton(
              onPressed: () => _openAddSheet(context),
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
              elevation: 6,
              shape: const CircleBorder(),
              child: const Icon(Icons.add, size: 28),
            ),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF3B82F6),
          backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
          onRefresh: () async {
            await Future.wait([
              ref.read(notesListProvider.notifier).loadNotes(),
              ref.read(foldersListProvider.notifier).loadFolders(),
              ref.read(syncProvider.notifier).syncNow(),
            ]);
          },
          child: CustomScrollView(
            slivers: [
              // Search Bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: SearchBar(
                    controller: _searchController,
                    hintText: notesState.isArchiveView
                        ? 'Search archived notes...'
                        : 'Search notes, ideas, learnings...',
                    hintStyle: WidgetStatePropertyAll(
                      TextStyle(
                        color: isDark ? Colors.white.withAlpha(80) : const Color(0xFF94A3B8),
                        fontSize: 14,
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
                      if (_searchController.text.isNotEmpty)
                        IconButton(
                          icon: Icon(
                            Icons.clear,
                            color: isDark ? Colors.grey : const Color(0xFF64748B),
                          ),
                          onPressed: () {
                            _searchController.clear();
                            notifier.setSearchQuery('');
                            ref.read(foldersListProvider.notifier).setSearchQuery('');
                          },
                        ),
                    ],
                    onChanged: (val) {
                      notifier.setSearchQuery(val);
                      ref.read(foldersListProvider.notifier).setSearchQuery(val);
                    },
                    elevation: const WidgetStatePropertyAll(0),
                    backgroundColor: WidgetStatePropertyAll(
                      isDark ? const Color(0xFF1E1E22) : Colors.white,
                    ),
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: isDark ? Colors.white.withAlpha(10) : const Color(0xFFE2E8F0),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Tag Filter Chips
              if (notesState.availableTags.isNotEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 38,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      itemCount: notesState.availableTags.length,
                      itemBuilder: (context, index) {
                        final tag = notesState.availableTags[index];
                        final isSelected = notesState.selectedTag == tag;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: FilterChip(
                            label: Text('#$tag'),
                            labelStyle: TextStyle(
                              fontSize: 12,
                              color: isSelected
                                  ? Colors.white
                                  : (isDark ? const Color(0xFF9E9EA7) : const Color(0xFF64748B)),
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                            selected: isSelected,
                            onSelected: (_) => notifier.selectTag(tag),
                            backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
                            selectedColor: const Color(0xFF3B82F6),
                            checkmarkColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: isSelected
                                    ? const Color(0xFF3B82F6)
                                    : (isDark ? Colors.white.withAlpha(15) : const Color(0xFFE2E8F0)),
                              ),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Sync Status Bar (subtle indicator)
              if (syncState.isSyncing || syncState.pendingCount > 0)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: InkWell(
                      onTap: () => ref.read(syncProvider.notifier).syncNow(),
                      borderRadius: BorderRadius.circular(6),
                      child: Row(
                        children: [
                          if (syncState.isSyncing)
                            const SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3B82F6)),
                            )
                          else
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.amber,
                              ),
                            ),
                          const SizedBox(width: 8),
                          Text(
                            syncState.isSyncing
                                ? 'Updating...'
                                : '${syncState.pendingCount} pending updates',
                            style: const TextStyle(
                              color: Color(0xFF9E9EA7),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // ================= SECTION 1: NOTEBOOKS (FOLDERS) =================
              if (!notesState.isArchiveView) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Notebooks',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.3,
                          ),
                        ),
                        TextButton(
                          onPressed: () => _showCreateFolderDialog(),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF60A5FA),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text(
                            '+ New',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 226,
                    child: foldersState.folders.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E1E22) : Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isDark ? Colors.white.withAlpha(10) : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.create_new_folder_outlined,
                                      color: isDark ? Colors.grey : const Color(0xFF64748B),
                                      size: 36,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Create your first notebook',
                                      style: TextStyle(
                                        color: theme.colorScheme.onSurface,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Organize notes into custom collections',
                                      style: TextStyle(
                                        color: isDark ? const Color(0xFF9E9EA7) : const Color(0xFF64748B),
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    OutlinedButton.icon(
                                      onPressed: () => _showCreateFolderDialog(),
                                      icon: const Icon(Icons.add, size: 16),
                                      label: const Text('Add Notebook', style: TextStyle(fontSize: 12)),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFF3B82F6),
                                        side: const BorderSide(color: Color(0xFF3B82F6)),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: foldersState.folders.length,
                            separatorBuilder: (context, index) => const SizedBox(width: 12),
                            itemBuilder: (ctx, idx) {
                              final folder = foldersState.folders[idx];
                              return NotebookCard(
                                folder: folder,
                                onTap: () => context.push('/folder/${folder.id}'),
                                onEdit: () => _showCreateFolderDialog(folderToEdit: folder),
                                onDelete: () => _showDeleteFolderDialog(folder),
                                onTogglePin: () =>
                                    ref.read(foldersListProvider.notifier).togglePin(folder.id),
                              );
                            },
                          ),
                  ),
                ),
              ],

              // ================= SECTION 2: NOTES =================
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        notesState.isArchiveView ? 'Archived Notes' : 'Notes',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        '${notesState.notes.length} ${notesState.notes.length == 1 ? 'note' : 'notes'}',
                        style: TextStyle(
                          color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF64748B),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Empty Notes State
              if (notesState.notes.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.notes,
                            size: 48,
                            color: isDark ? Colors.white.withAlpha(40) : const Color(0xFF94A3B8),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            notesState.isArchiveView ? 'Archive is empty' : 'No notes yet',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            notesState.isArchiveView
                                ? 'Archived notes will appear here.'
                                : 'Capture your first idea, project note, or learning.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isDark ? const Color(0xFF9E9EA7) : const Color(0xFF64748B),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: () => context.push('/note/new'),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add Note'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF3B82F6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                // Grid of Notes matching the reference layout
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.82,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final note = notesState.notes[index];
                        final folder = note.projectId != null ? folderMap[note.projectId] : null;
                        return _buildModernNoteCard(note, folder);
                      },
                      childCount: notesState.notes.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernNoteCard(Note note, Folder? folder) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(12) : const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withAlpha(40) : Colors.black.withAlpha(8),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => context.push('/note/${note.id}'),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Pin Indicator & Context Menu
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (note.isPinned)
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFACC15).withAlpha(35),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.push_pin,
                          size: 13,
                          color: Color(0xFFFACC15),
                        ),
                      )
                    else
                      const SizedBox(width: 16),
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_horiz,
                        size: 20,
                        color: isDark ? const Color(0xFF9E9EA7) : const Color(0xFF64748B),
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: isDark ? const Color(0xFF26262B) : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isDark ? Colors.white.withAlpha(20) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      onSelected: (val) {
                        if (val == 'move') {
                          showDialog(
                            context: context,
                            builder: (_) => MoveToFolderDialog(note: note),
                          );
                        } else if (val == 'pin') {
                          ref.read(notesListProvider.notifier).togglePin(note.id);
                        } else if (val == 'archive') {
                          ref
                              .read(notesListProvider.notifier)
                              .setArchived(note.id, !note.isArchived);
                        } else if (val == 'delete') {
                          ref.read(notesListProvider.notifier).deleteNote(note.id);
                        }
                      },
                      itemBuilder: (ctx) => [
                        PopupMenuItem(
                          value: 'move',
                          child: Row(
                            children: [
                              Icon(Icons.drive_file_move_outlined, size: 16, color: theme.colorScheme.onSurface),
                              const SizedBox(width: 10),
                              Text('Move to Notebook', style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'pin',
                          child: Row(
                            children: [
                              Icon(
                                note.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                                size: 16,
                                color: theme.colorScheme.onSurface,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                note.isPinned ? 'Unpin note' : 'Pin to top',
                                style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'archive',
                          child: Row(
                            children: [
                              Icon(
                                note.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
                                size: 16,
                                color: theme.colorScheme.onSurface,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                note.isArchived ? 'Unarchive' : 'Archive',
                                style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(height: 1),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444)),
                              SizedBox(width: 10),
                              Text('Delete', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Note Title
                Text(
                  note.title.isNotEmpty ? note.title : 'Untitled Note',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),
                // Note Preview lines
                Expanded(
                  child: Text(
                    note.content.isNotEmpty ? note.content : 'No content',
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? const Color(0xFF9E9EA7) : const Color(0xFF64748B),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
                // Bottom row: Notebook Tag badge if assigned
                if (folder != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2E2E34) : const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.book_outlined,
                          size: 10,
                          color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            folder.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // Note Tags
                if (note.tags.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: note.tags.map((tag) {
                      return Text(
                        '#$tag',
                        style: TextStyle(
                          color: isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAccountDialog(BuildContext context) {
    final authState = ref.read(authProvider);
    final user = authState.user;
    final notesState = ref.read(notesListProvider);
    final notifier = ref.read(notesListProvider.notifier);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFF3B82F6).withAlpha(40),
              child: const Icon(Icons.person, color: Color(0xFF60A5FA)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user?.name.isNotEmpty == true ? user!.name : 'Zuri User',
                    style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    user?.email ?? '',
                    style: TextStyle(color: isDark ? const Color(0xFF9E9EA7) : const Color(0xFF64748B), fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Theme Mode row inside dialog
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF26262B) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        isDark ? Icons.dark_mode : Icons.light_mode,
                        size: 20,
                        color: isDark ? const Color(0xFFFBBF24) : const Color(0xFF2563EB),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isDark ? 'Dark Theme' : 'Light Theme',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  Switch(
                    value: isDark,
                    activeThumbColor: const Color(0xFF3B82F6),
                    onChanged: (_) {
                      ref.read(themeModeProvider.notifier).toggleTheme();
                    },
                  ),
                ],
              ),
            ),
            // Quick Navigation: Memory Recap
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.history_edu_outlined, color: theme.colorScheme.primary),
              title: Text(
                'Memory Recap',
                style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                'Review past insights and daily summaries',
                style: TextStyle(color: isDark ? const Color(0xFF9E9EA7) : const Color(0xFF64748B), fontSize: 11),
              ),
              onTap: () {
                Navigator.of(dialogCtx).pop();
                context.push('/recap');
              },
            ),
            // Quick Navigation: Archive Toggle
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                notesState.isArchiveView ? Icons.notes : Icons.archive_outlined,
                color: theme.colorScheme.primary,
              ),
              title: Text(
                notesState.isArchiveView ? 'View Active Notes' : 'View Archived Notes',
                style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w500),
              ),
              onTap: () {
                Navigator.of(dialogCtx).pop();
                _searchController.clear();
                notifier.toggleArchiveView();
              },
            ),
            const Divider(height: 16),
            if (authState.isOffline)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off, size: 16, color: Colors.amber),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Offline Mode Active. Local notes are saved safely.',
                        style: TextStyle(fontSize: 12, color: Colors.amber, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              'Your notes are saved directly on your device and safely synced to your private Zuri account.',
              style: TextStyle(color: isDark ? const Color(0xFF9E9EA7) : const Color(0xFF64748B), fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text('Close', style: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF64748B))),
          ),
          FilledButton.tonalIcon(
            key: const Key('account_logout_button'),
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sign Out'),
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              await ref.read(authProvider.notifier).logout();
            },
          ),
        ],
      ),
    );
  }
}
