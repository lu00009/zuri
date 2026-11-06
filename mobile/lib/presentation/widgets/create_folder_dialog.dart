import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../domain/entities/folder.dart';
import 'notebook_illustration.dart';

class CreateFolderDialog extends StatefulWidget {
  final Folder? folderToEdit;

  const CreateFolderDialog({super.key, this.folderToEdit});

  @override
  State<CreateFolderDialog> createState() => _CreateFolderDialogState();
}

class _CreateFolderDialogState extends State<CreateFolderDialog> {
  final _nameController = TextEditingController();
  String? _selectedImagePath;
  bool _removedExistingImage = false;
  String _selectedColor = '#EF4444';
  bool _isPickingImage = false;

  static const List<String> _colorPresets = [
    '#EF4444', // Red (like YouTube Ideas in screenshot)
    '#3B82F6', // Blue (like User Research in screenshot)
    '#8B5CF6', // Purple
    '#F59E0B', // Amber
    '#10B981', // Emerald
    '#EC4899', // Pink
  ];

  @override
  void initState() {
    super.initState();
    if (widget.folderToEdit != null) {
      _nameController.text = widget.folderToEdit!.name;
      _selectedImagePath = widget.folderToEdit!.coverImagePath;
      _selectedColor = widget.folderToEdit!.colorAccent ?? '#EF4444';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    setState(() => _isPickingImage = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (picked != null) {
        setState(() {
          _selectedImagePath = picked.path;
          _removedExistingImage = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load image: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImagePath = null;
      _removedExistingImage = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isEditing = widget.folderToEdit != null;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: isDark ? Colors.white.withAlpha(20) : const Color(0xFFE2E8F0),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isEditing ? 'Edit Notebook' : 'New Notebook',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: isDark ? Colors.grey : const Color(0xFF64748B),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Preview of Cover
                Center(
                  child: Stack(
                    alignment: Alignment.topRight,
                    children: [
                      NotebookIllustration(
                        coverImagePath: _selectedImagePath,
                        colorAccentHex: _selectedColor,
                        width: 100,
                        height: 125,
                      ),
                      if (_selectedImagePath != null && _selectedImagePath!.isNotEmpty)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: InkWell(
                            onTap: _removeImage,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.redAccent,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Image picker action button
                Center(
                  child: TextButton.icon(
                    onPressed: _isPickingImage ? null : _pickImage,
                    icon: _isPickingImage
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3B82F6)),
                          )
                        : const Icon(Icons.photo_library_outlined, size: 18),
                    label: Text(
                      _selectedImagePath != null ? 'Change Cover Image' : 'Choose Cover from Gallery',
                      style: const TextStyle(fontSize: 13),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF3B82F6),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Folder Name TextField
                TextField(
                  controller: _nameController,
                  autofocus: !isEditing,
                  style: TextStyle(color: theme.colorScheme.onSurface),
                  decoration: InputDecoration(
                    labelText: 'Notebook Name',
                    labelStyle: TextStyle(
                      color: isDark ? const Color(0xFF9E9EA7) : const Color(0xFF64748B),
                    ),
                    hintText: 'e.g. YouTube Ideas, Travel, Work',
                    hintStyle: TextStyle(
                      color: isDark ? Colors.white.withAlpha(60) : const Color(0xFF94A3B8),
                    ),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF26262B) : const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isDark ? Colors.white.withAlpha(20) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Color Accent Selection
                Text(
                  'Spine Color Accent',
                  style: TextStyle(
                    color: isDark ? const Color(0xFF9E9EA7) : const Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: _colorPresets.map((hex) {
                    final color = Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
                    final isSelected = _selectedColor.toUpperCase() == hex.toUpperCase();
                    return GestureDetector(
                      onTap: () => setState(() => _selectedColor = hex),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? (isDark ? Colors.white : const Color(0xFF0F172A))
                                : Colors.transparent,
                            width: 2.5,
                          ),
                          boxShadow: [
                            if (isSelected)
                              BoxShadow(
                                color: color.withAlpha(150),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                          ],
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, size: 18, color: Colors.white)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? Colors.white70 : const Color(0xFF64748B),
                          side: BorderSide(
                            color: isDark ? Colors.white.withAlpha(30) : const Color(0xFFCBD5E1),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          final name = _nameController.text.trim();
                          if (name.isEmpty) return;

                          Navigator.of(context).pop({
                            'name': name,
                            'coverImagePath': _selectedImagePath,
                            'clearCoverImage': _removedExistingImage,
                            'colorAccent': _selectedColor,
                          });
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(isEditing ? 'Save' : 'Create'),
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
