import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/datasources/remote/cloudinary_service.dart';
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
  Uint8List? _selectedImageBytes;
  bool _removedExistingImage = false;
  String _selectedColor = '#EF4444';
  bool _isPickingImage = false;
  bool _isUploadingToCloudinary = false;

  static const List<String> _colorPresets = [
    '#EF4444', // Red
    '#3B82F6', // Blue
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
        final bytes = await picked.readAsBytes();
        setState(() {
          _selectedImageBytes = bytes;
          _selectedImagePath = 'data:image/jpeg;base64,${base64Encode(bytes)}';
          _removedExistingImage = false;
          _isUploadingToCloudinary = true;
        });

        // Upload to Cloudinary
        try {
          final cloudinaryUrl = await CloudinaryService().uploadImageBytes(
            bytes: bytes,
            filename: picked.name,
          );
          if (mounted) {
            setState(() {
              _selectedImagePath = cloudinaryUrl;
              _isUploadingToCloudinary = false;
            });
          }
        } catch (_) {
          if (mounted) {
            setState(() => _isUploadingToCloudinary = false);
          }
        }
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
      _selectedImageBytes = null;
      _removedExistingImage = true;
      _isUploadingToCloudinary = false;
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
                        coverImageBytes: _selectedImageBytes,
                        colorAccentHex: _selectedColor,
                        width: 100,
                        height: 125,
                      ),
                      if ((_selectedImagePath != null && _selectedImagePath!.isNotEmpty) ||
                          (_selectedImageBytes != null && _selectedImageBytes!.isNotEmpty))
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

                // Cloudinary status or image picker button
                Center(
                  child: Column(
                    children: [
                      TextButton.icon(
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
                      if (_isUploadingToCloudinary) ...[
                        const SizedBox(height: 4),
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF3B82F6)),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Optimizing & uploading to Cloudinary...',
                              style: TextStyle(fontSize: 11, color: Color(0xFF3B82F6)),
                            ),
                          ],
                        ),
                      ],
                    ],
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
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
                const SizedBox(height: 20),

                // Color Accents
                Text(
                  'Spine Color Accent',
                  style: TextStyle(
                    color: isDark ? const Color(0xFF9E9EA7) : const Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: _colorPresets.map((hex) {
                    final clean = hex.replaceAll('#', '');
                    final color = Color(int.parse('FF$clean', radix: 16));
                    final isSelected = _selectedColor == hex;

                    return GestureDetector(
                      onTap: () => setState(() => _selectedColor = hex),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(color: Colors.white, width: 2.5)
                              : null,
                          boxShadow: [
                            if (isSelected)
                              BoxShadow(
                                color: color.withAlpha(120),
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
