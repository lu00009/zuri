import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/note.dart';
import '../providers/folders_provider.dart';

class MoveToFolderDialog extends ConsumerWidget {
  final Note note;

  const MoveToFolderDialog({super.key, required this.note});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersState = ref.watch(foldersListProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isDark ? Colors.white.withAlpha(20) : const Color(0xFFE2E8F0),
        ),
      ),
      title: Text(
        'Move to Notebook',
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: foldersState.folders.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 20.0),
                child: Text(
                  'No notebooks created yet. Create a notebook first to organize your notes.',
                  style: TextStyle(
                    color: isDark ? const Color(0xFF9E9EA7) : const Color(0xFF64748B),
                  ),
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  // Option: Remove from current notebook
                  if (note.projectId != null) ...[
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.folder_off_outlined, color: Colors.amber),
                      title: const Text(
                        'Remove from notebook (keep note)',
                        style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w500),
                      ),
                      onTap: () async {
                        Navigator.of(context).pop();
                        await ref
                            .read(foldersListProvider.notifier)
                            .removeNoteFromFolder(note.id);
                      },
                    ),
                    Divider(color: isDark ? Colors.white24 : const Color(0xFFE2E8F0)),
                  ],
                  ...foldersState.folders.map((folder) {
                    final isCurrent = note.projectId == folder.id;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        isCurrent ? Icons.folder : Icons.folder_outlined,
                        color: isCurrent
                            ? const Color(0xFF3B82F6)
                            : (isDark ? const Color(0xFF9E9EA7) : const Color(0xFF64748B)),
                      ),
                      title: Text(
                        folder.name,
                        style: TextStyle(
                          color: isCurrent ? const Color(0xFF3B82F6) : theme.colorScheme.onSurface,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        '${folder.noteCount} ${folder.noteCount == 1 ? 'note' : 'notes'}',
                        style: TextStyle(
                          color: isDark ? const Color(0xFF9E9EA7) : const Color(0xFF64748B),
                          fontSize: 11,
                        ),
                      ),
                      trailing: isCurrent
                          ? const Icon(Icons.check, color: Color(0xFF3B82F6), size: 18)
                          : null,
                      onTap: isCurrent
                          ? null
                          : () async {
                              Navigator.of(context).pop();
                              await ref
                                  .read(foldersListProvider.notifier)
                                  .moveNoteToFolder(noteId: note.id, folderId: folder.id);
                            },
                    );
                  }),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Close',
            style: TextStyle(
              color: isDark ? Colors.white70 : const Color(0xFF64748B),
            ),
          ),
        ),
      ],
    );
  }
}

