import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';

class CloudinaryService {
  static const String _defaultCloudName = String.fromEnvironment(
    'CLOUDINARY_CLOUD_NAME',
    defaultValue: 'dqykgm9e0',
  );

  static const String _defaultUploadPreset = String.fromEnvironment(
    'CLOUDINARY_UPLOAD_PRESET',
    defaultValue: 'zuri_folders',
  );

  final Dio _dio;
  final String cloudName;
  final String uploadPreset;

  CloudinaryService({
    Dio? dio,
    String? cloudName,
    String? uploadPreset,
  })  : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 20))),
        cloudName = cloudName ?? _defaultCloudName,
        uploadPreset = uploadPreset ?? _defaultUploadPreset;

  /// Uploads image bytes to Cloudinary.
  /// If successful, returns the permanent HTTPS Cloudinary URL (`secure_url`).
  /// If Cloudinary is unreachable, unconfigured, or offline, falls back seamlessly
  /// to a data URI (`data:image/jpeg;base64,...`) so the cover image is always visible and preserved.
  Future<String> uploadImageBytes({
    required Uint8List bytes,
    String? filename,
  }) async {
    final base64Image = base64Encode(bytes);
    final dataUri = 'data:image/jpeg;base64,$base64Image';

    // If cloudName or preset are completely empty, return data URI fallback
    if (cloudName.isEmpty || uploadPreset.isEmpty) {
      return dataUri;
    }

    try {
      final uploadUrl = 'https://api.cloudinary.com/v1_1/$cloudName/image/upload';
      final response = await _dio.post(
        uploadUrl,
        data: {
          'file': dataUri,
          'upload_preset': uploadPreset,
          'folder': 'zuri_folders',
        },
      );

      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final secureUrl = data['secure_url'] as String?;
        if (secureUrl != null && secureUrl.isNotEmpty) {
          return secureUrl;
        }
      }
      return dataUri;
    } catch (_) {
      // In case of any network error, preset mismatch, or offline mode,
      // fallback to the embedded data URI so the cover image remains 100% visible
      return dataUri;
    }
  }
}

