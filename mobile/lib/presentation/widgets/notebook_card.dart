import 'package:flutter/material.dart';
import '../../domain/entities/folder.dart';
import 'notebook_illustration.dart';

class NotebookCard extends StatelessWidget {
  final Folder folder;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onTogglePin;

  const NotebookCard({
    super.key,
    required this.folder,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onTogglePin,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: 156,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(12) : const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withAlpha(60) : Colors.black.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top row: Pin indicator & More options
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (folder.isPinned)
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFACC15).withAlpha(35),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.push_pin,
                          size: 14,
                          color: Color(0xFFFACC15),
                        ),
                      )
                    else
                      const SizedBox(width: 18),
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
                        if (val == 'edit') onEdit?.call();
                        if (val == 'pin') onTogglePin?.call();
                        if (val == 'delete') onDelete?.call();
                      },
                      itemBuilder: (ctx) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 16, color: theme.colorScheme.onSurface),
                              const SizedBox(width: 10),
                              Text('Edit Folder', style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'pin',
                          child: Row(
                            children: [
                              Icon(
                                folder.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                                size: 16,
                                color: theme.colorScheme.onSurface,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                folder.isPinned ? 'Unpin folder' : 'Pin to top',
                                style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(height: 1),
                        PopupMenuItem(
                          value: 'delete',
                          child: const Row(
                            children: [
                              Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444)),
                              SizedBox(width: 10),
                              Text('Delete Folder', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Center Notebook Cover Illustration or Custom Gallery Image
                Center(
                  child: NotebookIllustration(
                    coverImagePath: folder.coverImagePath,
                    colorAccentHex: folder.colorAccent,
                    width: 78,
                    height: 94,
                  ),
                ),
                const SizedBox(height: 8),
                // Folder Title
                Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                // Note Count
                Text(
                  '${folder.noteCount} ${folder.noteCount == 1 ? 'note' : 'notes'}',
                  style: TextStyle(
                    color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
