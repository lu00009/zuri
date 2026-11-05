import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/sync_provider.dart';
import '../widgets/note_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notesListProvider);
    final syncState = ref.watch(syncProvider);
    final notifier = ref.read(notesListProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.psychology,
              color: theme.colorScheme.primary,
              size: 26,
            ),
            const SizedBox(width: 8),
            Text(
              state.isArchiveView ? 'Archive' : 'PocketBrain',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          // Memory Recap
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.history_edu_outlined),
            tooltip: 'Memory Recap',
            onPressed: () {
              context.push('/recap');
            },
          ),
          // Ask AI Memory
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Ask PocketBrain AI',
            onPressed: () {
              context.push('/ai');
            },
          ),
          // Archive View Toggle
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              state.isArchiveView ? Icons.notes : Icons.archive_outlined,
            ),
            tooltip: state.isArchiveView
                ? 'View Active Notes'
                : 'View Archived Notes',
            onPressed: () {
              _searchController.clear();
              notifier.toggleArchiveView();
            },
          ),
          // Info Dialog
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About PocketBrain',
            onPressed: () {
              showAboutDialog(
                context: context,
                applicationName: 'PocketBrain',
                applicationVersion: '0.2.0 (Phase 2)',
                applicationLegalese:
                    'Offline-First Personal Knowledge Repository',
                children: const [
                  SizedBox(height: 12),
                  Text(
                    'All notes, tags, and search operations run 100% locally on device using SQLite.',
                  ),
                ],
              );
            },
          ),
          // Account / Profile Dialog
          IconButton(
            visualDensity: VisualDensity.compact,
            key: const Key('home_account_button'),
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'Account',
            onPressed: () {
              _showAccountDialog(context);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search & Offline Badge Header
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Column(
                children: [
                  SearchBar(
                    controller: _searchController,
                    hintText: state.isArchiveView
                        ? 'Search archived notes...'
                        : 'Search notes, ideas, learnings...',
                    leading: const Icon(Icons.search),
                    trailing: [
                      if (_searchController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            notifier.setSearchQuery('');
                          },
                        ),
                    ],
                    onChanged: (val) => notifier.setSearchQuery(val),
                    elevation: const WidgetStatePropertyAll(0),
                    backgroundColor: WidgetStatePropertyAll(
                      theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Sync Status Indicator Bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (syncState.isSyncing || syncState.pendingCount > 0)
                        InkWell(
                          onTap: () => ref.read(syncProvider.notifier).syncNow(),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: Row(
                              children: [
                                if (syncState.isSyncing)
                                  const SizedBox(
                                    width: 10,
                                    height: 10,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
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
                                const SizedBox(width: 6),
                                Text(
                                  syncState.isSyncing
                                      ? 'Syncing...'
                                      : '${syncState.pendingCount} pending sync',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        const SizedBox.shrink(),
                      Text(
                        '${state.notes.length} ${state.notes.length == 1 ? 'note' : 'notes'}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (!state.isArchiveView && state.notes.isNotEmpty)
              InkWell(
                onTap: () => context.push('/recap'),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withAlpha(50),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.colorScheme.primary.withAlpha(40),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Weekly Memory Recap • See what you learned & decided',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 12,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),

            // Horizontal Tag Filter List
            if (state.availableTags.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  itemCount: state.availableTags.length,
                  itemBuilder: (context, index) {
                    final tag = state.availableTags[index];
                    final isSelected = state.selectedTag == tag;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: FilterChip(
                        label: Text('#$tag'),
                        selected: isSelected,
                        onSelected: (_) => notifier.selectTag(tag),
                        visualDensity: VisualDensity.compact,
                        showCheckmark: false,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                    );
                  },
                ),
              ),

            const SizedBox(height: 4),

            // Main Notes List / Empty / Loading / Error States
            Expanded(child: _buildBody(context, state, notifier)),
          ],
        ),
      ),
      floatingActionButton: state.isArchiveView
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/note/new'),
              icon: const Icon(Icons.add),
              label: const Text('New Note'),
            ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    NotesListState state,
    NotesListNotifier notifier,
  ) {
    final theme = Theme.of(context);

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(
                state.errorMessage!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => notifier.loadNotes(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (state.notes.isEmpty) {
      final isSearching =
          state.searchQuery.isNotEmpty || state.selectedTag != null;
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSearching
                    ? Icons.search_off
                    : (state.isArchiveView
                          ? Icons.archive_outlined
                          : Icons.note_add_outlined),
                size: 64,
                color: theme.colorScheme.outline.withAlpha(120),
              ),
              const SizedBox(height: 16),
              Text(
                isSearching
                    ? 'No matching notes found'
                    : (state.isArchiveView
                          ? 'Archive is empty'
                          : 'Your pocket is empty'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isSearching
                    ? 'Try adjusting your search query or tag filter.'
                    : (state.isArchiveView
                          ? 'Archived notes will appear here.'
                          : 'Capture your first note, idea, learning, or project decision.'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              if (!isSearching && !state.isArchiveView) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => context.push('/note/new'),
                  icon: const Icon(Icons.add),
                  label: const Text('Create a note'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => notifier.loadNotes(),
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 88),
        itemCount: state.notes.length,
        itemBuilder: (context, index) {
          final note = state.notes[index];
          return NoteCard(
            note: note,
            onTap: () => context.push('/note/${note.id}'),
            onTogglePin: () => notifier.togglePin(note.id),
            onToggleArchive: () =>
                notifier.setArchived(note.id, !note.isArchived),
            onDelete: () => notifier.deleteNote(note.id),
          );
        },
      ),
    );
  }

  void _showAccountDialog(BuildContext context) {
    final authState = ref.read(authProvider);
    final user = authState.user;
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                (user?.name.isNotEmpty == true
                        ? user!.name[0]
                        : (user?.email.isNotEmpty == true
                              ? user!.email[0]
                              : 'U'))
                    .toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user?.name.isNotEmpty == true
                        ? user!.name
                        : 'PocketBrain User',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    user?.email ?? '',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
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
            if (authState.isOffline)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off, size: 16, color: Colors.amber),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Offline Mode Active. Local notes are saved safely.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const Text(
              'Your notes are stored locally in SQLite and synced to your private PocketBrain cloud account.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Close'),
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
