import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class NotebookIllustration extends StatelessWidget {
  final String? coverImagePath;
  final String? colorAccentHex;
  final double width;
  final double height;

  const NotebookIllustration({
    super.key,
    this.coverImagePath,
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
    final hasImage = coverImagePath != null && coverImagePath!.isNotEmpty;

    if (hasImage) {
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
              _buildCoverImage(coverImagePath!),
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
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF333338),
            Color(0xFF202024),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Left spine bar
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: width * 0.14,
            child: Container(
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    accentColor,
                    Color.alphaBlend(Colors.black.withAlpha(50), accentColor),
                  ],
                ),
              ),
            ),
          ),
          // Notebook debossed content lines
          Positioned(
            left: width * 0.28,
            right: width * 0.16,
            top: height * 0.32,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 4,
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

  Widget _buildCoverImage(String path) {
    if (kIsWeb) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildFallback(),
      );
    }
    final file = File(path);
    if (!file.existsSync()) {
      return _buildFallback();
    }
    return Image.file(
      file,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _buildFallback(),
    );
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
