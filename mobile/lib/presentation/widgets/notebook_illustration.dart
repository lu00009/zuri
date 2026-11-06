import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class NotebookIllustration extends StatelessWidget {
  final String? coverImagePath;
  final Uint8List? coverImageBytes;
  final String? colorAccentHex;
  final double width;
  final double height;

  const NotebookIllustration({
    super.key,
    this.coverImagePath,
    this.coverImageBytes,
    this.colorAccentHex,
    this.width = 100,
    this.height = 125,
  });

  Color _parseAccentColor(String? hex) {
    if (hex == null || hex.isEmpty) return const Color(0xFFEF4444);
    try {
      final clean = hex.replaceAll('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return const Color(0xFFEF4444);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _parseAccentColor(colorAccentHex);
    final hasBytes = coverImageBytes != null && coverImageBytes!.isNotEmpty;
    final hasPath = coverImagePath != null && coverImagePath!.isNotEmpty;

    if (hasBytes || hasPath) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(80),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildCoverImage(),
              // Subtle gradient overlay for depth
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withAlpha(90),
                    ],
                  ),
                ),
              ),
              // Left spine accent bar
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 6,
                child: Container(
                  color: accentColor,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Default 3D Notebook Illustration matching the reference design
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF26262B),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          bottomLeft: Radius.circular(8),
          topRight: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(100),
            blurRadius: 10,
            offset: const Offset(2, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Left Spine Accent (Color Bar)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 14,
            child: Container(
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(80),
                    blurRadius: 3,
                    offset: const Offset(1, 0),
                  ),
                ],
              ),
            ),
          ),
          // Subtle Spine Crease shadow
          Positioned(
            left: 14,
            top: 0,
            bottom: 0,
            width: 3,
            child: Container(
              color: Colors.black.withAlpha(60),
            ),
          ),
          // Notebook Bookmark Ribbon / Tag
          Positioned(
            top: 0,
            right: 18,
            width: 10,
            height: 22,
            child: Container(
              decoration: BoxDecoration(
                color: accentColor.withAlpha(220),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(3),
                  bottomRight: Radius.circular(3),
                ),
              ),
            ),
          ),
          // Notebook Title Debossed Mock Lines
          Positioned(
            left: 28,
            top: height * 0.40,
            right: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 5,
                  width: width * 0.55,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A4A52),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 4,
                  width: width * 0.35,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A4A52),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverImage() {
    // 1. In-memory image bytes (used during gallery selection preview)
    if (coverImageBytes != null && coverImageBytes!.isNotEmpty) {
      return Image.memory(
        coverImageBytes!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildFallback(),
      );
    }

    final path = coverImagePath;
    if (path == null || path.isEmpty) {
      return _buildFallback();
    }

    // 2. Data URI (base64 fallback for offline/direct storage)
    if (path.startsWith('data:image/')) {
      try {
        final commaIdx = path.indexOf(',');
        if (commaIdx != -1) {
          final b64Str = path.substring(commaIdx + 1);
          final bytes = base64Decode(b64Str);
          return Image.memory(
            bytes,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _buildFallback(),
          );
        }
      } catch (_) {}
    }

    // 3. Cloudinary or any Network HTTP/HTTPS / Blob URL
    if (path.startsWith('http://') || path.startsWith('https://') || path.startsWith('blob:')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: const Color(0xFF26262B),
            child: const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3B82F6)),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => _buildFallback(),
      );
    }

    // 4. Local File path (mobile/desktop gallery cache)
    if (!kIsWeb) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          return Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _buildFallback(),
          );
        }
      } catch (_) {}
    }

    return _buildFallback();
  }

  Widget _buildFallback() {
    return Container(
      color: const Color(0xFF2A2A2E),
      child: const Center(
        child: Icon(Icons.image_not_supported, color: Colors.grey, size: 24),
      ),
    );
  }
}
