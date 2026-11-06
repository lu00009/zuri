import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class SecureTokenStorage {
  Future<void> saveTokens({required String accessToken, required String refreshToken});
  Future<String?> getAccessToken();
  Future<String?> getRefreshToken();
  Future<void> clearTokens();
  Future<bool> hasTokens();
  Future<void> saveUserData({required String email, String? name, String? userId});
  Future<Map<String, String?>> getUserData();
  Future<void> clearAll();
}

class FlutterSecureTokenStorage implements SecureTokenStorage {
  static const String _accessTokenKey = 'zuri_auth_token';
  static const String _refreshTokenKey = 'zuri_refresh_token';
  static const String _userEmailKey = 'zuri_user_email';
  static const String _userNameKey = 'zuri_user_name';
  static const String _userIdKey = 'zuri_user_id';

  // Legacy PocketBrain keys for seamless backward compatibility
  static const String _legacyAccessTokenKey = 'pocketbrain_auth_token';
  static const String _legacyRefreshTokenKey = 'pocketbrain_refresh_token';
  static const String _legacyUserEmailKey = 'pocketbrain_user_email';
  static const String _legacyUserNameKey = 'pocketbrain_user_name';
  static const String _legacyUserIdKey = 'pocketbrain_user_id';

  final FlutterSecureStorage _storage;

  const FlutterSecureTokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                resetOnError: false,
              ),
              webOptions: WebOptions(
                dbName: 'zuri_secure_storage',
                publicKey: 'zuri_vault_key',
              ),
            );

  @override
  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    if (accessToken.trim().isNotEmpty) {
      await _storage.write(key: _accessTokenKey, value: accessToken.trim());
    }
    if (refreshToken.trim().isNotEmpty) {
      await _storage.write(key: _refreshTokenKey, value: refreshToken.trim());
    }
  }

  @override
  Future<String?> getAccessToken() async {
    final token = await _storage.read(key: _accessTokenKey);
    if (token != null && token.isNotEmpty) return token;
    // Fallback to legacy key if migrating
    final legacy = await _storage.read(key: _legacyAccessTokenKey);
    if (legacy != null && legacy.isNotEmpty) {
      await _storage.write(key: _accessTokenKey, value: legacy);
      return legacy;
    }
    return null;
  }

  @override
  Future<String?> getRefreshToken() async {
    final token = await _storage.read(key: _refreshTokenKey);
    if (token != null && token.isNotEmpty) return token;
    // Fallback to legacy key if migrating
    final legacy = await _storage.read(key: _legacyRefreshTokenKey);
    if (legacy != null && legacy.isNotEmpty) {
      await _storage.write(key: _refreshTokenKey, value: legacy);
      return legacy;
    }
    return null;
  }

  @override
  Future<void> clearTokens() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _legacyAccessTokenKey);
    await _storage.delete(key: _legacyRefreshTokenKey);
  }

  @override
  Future<bool> hasTokens() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  @override
  Future<void> saveUserData({required String email, String? name, String? userId}) async {
    if (email.trim().isNotEmpty) {
      await _storage.write(key: _userEmailKey, value: email.trim());
    }
    if (name != null) {
      await _storage.write(key: _userNameKey, value: name.trim());
    }
    if (userId != null) {
      await _storage.write(key: _userIdKey, value: userId.trim());
    }
  }

  @override
  Future<Map<String, String?>> getUserData() async {
    String? email = await _storage.read(key: _userEmailKey);
    String? name = await _storage.read(key: _userNameKey);
    String? id = await _storage.read(key: _userIdKey);

    // Fallback to legacy keys if migrating
    email ??= await _storage.read(key: _legacyUserEmailKey);
    name ??= await _storage.read(key: _legacyUserNameKey);
    id ??= await _storage.read(key: _legacyUserIdKey);

    return {
      'email': email,
      'name': name,
      'id': id,
    };
  }

  @override
  Future<void> clearAll() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _userEmailKey);
    await _storage.delete(key: _userNameKey);
    await _storage.delete(key: _userIdKey);

    await _storage.delete(key: _legacyAccessTokenKey);
    await _storage.delete(key: _legacyRefreshTokenKey);
    await _storage.delete(key: _legacyUserEmailKey);
    await _storage.delete(key: _legacyUserNameKey);
    await _storage.delete(key: _legacyUserIdKey);
  }
}
