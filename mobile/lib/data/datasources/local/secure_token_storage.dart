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
  static const String _accessTokenKey = 'pocketbrain_auth_token';
  static const String _refreshTokenKey = 'pocketbrain_refresh_token';
  static const String _userEmailKey = 'pocketbrain_user_email';
  static const String _userNameKey = 'pocketbrain_user_name';
  static const String _userIdKey = 'pocketbrain_user_id';

  final FlutterSecureStorage _storage;

  const FlutterSecureTokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  @override
  Future<String?> getAccessToken() async {
    return _storage.read(key: _accessTokenKey);
  }

  @override
  Future<String?> getRefreshToken() async {
    return _storage.read(key: _refreshTokenKey);
  }

  @override
  Future<void> clearTokens() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  @override
  Future<bool> hasTokens() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  @override
  Future<void> saveUserData({required String email, String? name, String? userId}) async {
    await _storage.write(key: _userEmailKey, value: email);
    if (name != null) await _storage.write(key: _userNameKey, value: name);
    if (userId != null) await _storage.write(key: _userIdKey, value: userId);
  }

  @override
  Future<Map<String, String?>> getUserData() async {
    final email = await _storage.read(key: _userEmailKey);
    final name = await _storage.read(key: _userNameKey);
    final id = await _storage.read(key: _userIdKey);
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
  }
}
