import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/datasources/remote/ai_remote_data_source.dart';
import '../../domain/entities/note.dart';
import '../providers/ai_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/sync_provider.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final String? noteId;

  const NoteEditorScreen({super.key, this.noteId});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _projectController = TextEditingController();
  final _tagInputController = TextEditingController();

  List<String> _tags = [];
  bool _isPinned = false;
  bool _isArchived = false;
  bool _isLoading = true;
  bool _isSaving = false;
  Note? _existingNote;

  @override
  void initState() {
    super.initState();
    _loadNoteData();
  }

  Future<void> _loadNoteData() async {
    if (widget.noteId != null) {
      final repo = ref.read(notesRepositoryProvider);
      final note = await repo.getNoteById(widget.noteId!);
      if (note != null && mounted) {
        _existingNote = note;
        _titleController.text = note.title;
        _contentController.text = note.content;
        _projectController.text = note.projectId ?? '';
        _tags = List.from(note.tags);
        _isPinned = note.isPinned;
        _isArchived = note.isArchived;
      }
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _projectController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  void _addTag(String rawTag) {
    final clean = rawTag.trim().toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '');
    if (clean.isNotEmpty && !_tags.contains(clean)) {
      setState(() {
        _tags.add(clean);
        _tagInputController.clear();
      });
    }
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
  }

  Future<void> _saveAndExit() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    final project = _projectController.text.trim();

    // If both title and content are empty, discard quietly or prompt
    if (title.isEmpty && content.isEmpty) {
      if (mounted) context.pop();
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final repo = ref.read(notesRepositoryProvider);
    final now = DateTime.now();

    final Note noteToSave;
    if (_existingNote != null) {
      noteToSave = _existingNote!.copyWith(
        title: title,
        content: content,
        tags: _tags,
        projectId: project.isEmpty ? null : project,
        isPinned: _isPinned,
        isArchived: _isArchived,
        updatedAt: now,
      );
    } else {
      noteToSave = Note.create(
        title: title,
        content: content,
        tags: _tags,
        projectId: project.isEmpty ? null : project,
        isPinned: _isPinned,
      );
    }

    await repo.saveNote(noteToSave);
    await ref.read(notesListProvider.notifier).loadNotes();
    ref.read(syncProvider.notifier).syncNow();
    ref.invalidate(relatedMemoriesProvider(noteToSave.id));

    if (mounted) {
      context.pop();
    }
  }

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Note?'),
        content: const Text('Are you sure you want to delete this note? It can be retrieved from sync history if needed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && widget.noteId != null) {
      await ref.read(notesListProvider.notifier).deleteNote(widget.noteId!);
      ref.read(syncProvider.notifier).syncNow();
      ref.invalidate(relatedMemoriesProvider(widget.noteId!));
      if (mounted) {
        context.pop();
      }
    }
  }

  void _showRelatedMemoriesSheet(BuildContext context) {
    if (widget.noteId == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Consumer(
        builder: (context, ref, _) {
          final relatedAsync =
              ref.watch(relatedMemoriesProvider(widget.noteId!));
          return SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.hub_outlined,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Related Memories',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(),
                  relatedAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (err, _) => Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Center(
                        child: Text(
                          'Could not load related memories: $err',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                    data: (memories) {
                      if (memories.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Center(
                            child: Text(
                              'No related memories found for this note yet.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        );
                      }
                      return Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: memories.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, idx) {
                            final item = memories[idx];
                            return _buildRelatedMemoryCard(context, item);
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRelatedMemoryCard(BuildContext context, RelatedMemory item) {
    final matchPercent = (item.similarity * 100).toInt();
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.pop(context);
          context.push('/note/${item.noteId}');
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.article_outlined, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withAlpha(20),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$matchPercent% match',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (item.explanation.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.withAlpha(25),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lightbulb_outline,
                          size: 13, color: Colors.amber[800]),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item.explanation,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.amber[900],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (item.excerpt.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  item.excerpt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.noteId == null ? 'New Note' : 'Edit Note',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              color: _isPinned ? theme.colorScheme.primary : null,
            ),
            tooltip: _isPinned ? 'Unpin Note' : 'Pin Note',
            onPressed: () {
              setState(() {
                _isPinned = !_isPinned;
              });
            },
          ),
          if (widget.noteId != null) ...[
            IconButton(
              icon: const Icon(Icons.hub_outlined),
              tooltip: 'Related Memories',
              onPressed: () => _showRelatedMemoriesSheet(context),
            ),
            IconButton(
              icon: Icon(
                _isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
              ),
              tooltip: _isArchived ? 'Unarchive' : 'Archive',
              onPressed: () {
                setState(() {
                  _isArchived = !_isArchived;
                  if (_isArchived) _isPinned = false;
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Delete Note',
              onPressed: _confirmDelete,
            ),
          ],
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            tooltip: 'Save Note',
            onPressed: _isSaving ? null : _saveAndExit,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
          child: Column(
            children: [
              // Title Input
              TextField(
                controller: _titleController,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  hintText: 'Note Title',
                  hintStyle: TextStyle(
                    color: theme.colorScheme.outline.withAlpha(150),
                  ),
                  border: InputBorder.none,
                ),
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
              ),
              const Divider(height: 16),
              // Metadata Row: Project & Tags
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _projectController,
                      style: theme.textTheme.bodyMedium,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.folder_outlined, size: 18),
                        hintText: 'Project (optional)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _tagInputController,
                      style: theme.textTheme.bodyMedium,
                      onSubmitted: _addTag,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.tag, size: 18),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.add, size: 18),
                          onPressed: () => _addTag(_tagInputController.text),
                        ),
                        hintText: 'Add tag...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
              if (_tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _tags.map((tag) {
                      return Chip(
                        label: Text('#$tag'),
                        labelStyle: const TextStyle(fontSize: 12),
                        deleteIcon: const Icon(Icons.close, size: 14),
                        onDeleted: () => _removeTag(tag),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      );
                    }).toList(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              // Main Markdown / Content Editor
              Expanded(
                child: TextField(
                  controller: _contentController,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                  decoration: InputDecoration(
                    hintText: 'Type your notes, thoughts, links, or learnings...',
                    hintStyle: TextStyle(
                      color: theme.colorScheme.outline.withAlpha(120),
                    ),
                    border: InputBorder.none,
                  ),
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                ),
              ),
              if (widget.noteId != null)
                Consumer(
                  builder: (context, ref, _) {
                    final relatedAsync =
                        ref.watch(relatedMemoriesProvider(widget.noteId!));
                    return relatedAsync.maybeWhen(
                      data: (memories) {
                        if (memories.isEmpty) return const SizedBox.shrink();
                        return InkWell(
                          onTap: () => _showRelatedMemoriesSheet(context),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            margin: const EdgeInsets.only(top: 8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer
                                  .withAlpha(45),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: theme.colorScheme.primary.withAlpha(50),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.hub_outlined,
                                    size: 18, color: theme.colorScheme.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${memories.length} Related ${memories.length == 1 ? 'Memory' : 'Memories'} Discovered',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                                Text(
                                  'View all',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.arrow_forward_ios,
                                    size: 11, color: theme.colorScheme.primary),
                              ],
                            ),
                          ),
                        );
                      },
                      orElse: () => const SizedBox.shrink(),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
