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

  static const FlutterSecureStorage _primaryStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: false,
    ),
    webOptions: WebOptions(
      dbName: 'zuri_secure_storage',
      publicKey: 'FlutterSecureStorage',
    ),
  );

  static const FlutterSecureStorage _vaultStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: false,
    ),
    webOptions: WebOptions(
      dbName: 'zuri_secure_storage',
      publicKey: 'zuri_vault_key',
    ),
  );

  final FlutterSecureStorage _storage;

  const FlutterSecureTokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? _primaryStorage;

  @override
  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    final a = accessToken.trim();
    final r = refreshToken.trim();
    if (a.isNotEmpty) {
      await _storage.write(key: _accessTokenKey, value: a);
      try {
        await _vaultStorage.write(key: _accessTokenKey, value: a);
      } catch (_) {}
    }
    if (r.isNotEmpty) {
      await _storage.write(key: _refreshTokenKey, value: r);
      try {
        await _vaultStorage.write(key: _refreshTokenKey, value: r);
      } catch (_) {}
    }
  }

  @override
  Future<String?> getAccessToken() async {
    try {
      final token = await _storage.read(key: _accessTokenKey);
      if (token != null && token.isNotEmpty) return token;
    } catch (_) {}

    try {
      final vaultToken = await _vaultStorage.read(key: _accessTokenKey);
      if (vaultToken != null && vaultToken.isNotEmpty) {
        await _storage.write(key: _accessTokenKey, value: vaultToken);
        return vaultToken;
      }
    } catch (_) {}

    try {
      final legacy = await _storage.read(key: _legacyAccessTokenKey);
      if (legacy != null && legacy.isNotEmpty) {
        await _storage.write(key: _accessTokenKey, value: legacy);
        return legacy;
      }
    } catch (_) {}

    try {
      final legacyVault = await _vaultStorage.read(key: _legacyAccessTokenKey);
      if (legacyVault != null && legacyVault.isNotEmpty) {
        await _storage.write(key: _accessTokenKey, value: legacyVault);
        return legacyVault;
      }
    } catch (_) {}

    return null;
  }

  @override
  Future<String?> getRefreshToken() async {
    try {
      final token = await _storage.read(key: _refreshTokenKey);
      if (token != null && token.isNotEmpty) return token;
    } catch (_) {}

    try {
      final vaultToken = await _vaultStorage.read(key: _refreshTokenKey);
      if (vaultToken != null && vaultToken.isNotEmpty) {
        await _storage.write(key: _refreshTokenKey, value: vaultToken);
        return vaultToken;
      }
    } catch (_) {}

    try {
      final legacy = await _storage.read(key: _legacyRefreshTokenKey);
      if (legacy != null && legacy.isNotEmpty) {
        await _storage.write(key: _refreshTokenKey, value: legacy);
        return legacy;
      }
    } catch (_) {}

    try {
      final legacyVault = await _vaultStorage.read(key: _legacyRefreshTokenKey);
      if (legacyVault != null && legacyVault.isNotEmpty) {
        await _storage.write(key: _refreshTokenKey, value: legacyVault);
        return legacyVault;
      }
    } catch (_) {}

    return null;
  }

  @override
  Future<void> clearTokens() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _legacyAccessTokenKey);
    await _storage.delete(key: _legacyRefreshTokenKey);

    try {
      await _vaultStorage.delete(key: _accessTokenKey);
      await _vaultStorage.delete(key: _refreshTokenKey);
      await _vaultStorage.delete(key: _legacyAccessTokenKey);
      await _vaultStorage.delete(key: _legacyRefreshTokenKey);
    } catch (_) {}
  }

  @override
  Future<bool> hasTokens() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  @override
  Future<void> saveUserData({required String email, String? name, String? userId}) async {
    final em = email.trim();
    if (em.isNotEmpty) {
      await _storage.write(key: _userEmailKey, value: em);
      try {
        await _vaultStorage.write(key: _userEmailKey, value: em);
      } catch (_) {}
    }
    if (name != null) {
      final nm = name.trim();
      await _storage.write(key: _userNameKey, value: nm);
      try {
        await _vaultStorage.write(key: _userNameKey, value: nm);
      } catch (_) {}
    }
    if (userId != null) {
      final id = userId.trim();
      await _storage.write(key: _userIdKey, value: id);
      try {
        await _vaultStorage.write(key: _userIdKey, value: id);
      } catch (_) {}
    }
  }

  @override
  Future<Map<String, String?>> getUserData() async {
    String? email;
    String? name;
    String? id;

    try {
      email = await _storage.read(key: _userEmailKey);
      name = await _storage.read(key: _userNameKey);
      id = await _storage.read(key: _userIdKey);
    } catch (_) {}

    if (email == null) {
      try {
        email = await _vaultStorage.read(key: _userEmailKey);
        name ??= await _vaultStorage.read(key: _userNameKey);
        id ??= await _vaultStorage.read(key: _userIdKey);
      } catch (_) {}
    }

    if (email == null) {
      try {
        email = await _storage.read(key: _legacyUserEmailKey);
        name ??= await _storage.read(key: _legacyUserNameKey);
        id ??= await _storage.read(key: _legacyUserIdKey);
      } catch (_) {}
    }

    return {
      'email': email,
      'name': name,
      'id': id,
    };
  }

  @override
  Future<void> clearAll() async {
    await clearTokens();
    await _storage.delete(key: _userEmailKey);
    await _storage.delete(key: _userNameKey);
    await _storage.delete(key: _userIdKey);

    await _storage.delete(key: _legacyUserEmailKey);
    await _storage.delete(key: _legacyUserNameKey);
    await _storage.delete(key: _legacyUserIdKey);

    try {
      await _vaultStorage.delete(key: _userEmailKey);
      await _vaultStorage.delete(key: _userNameKey);
      await _vaultStorage.delete(key: _userIdKey);
      await _vaultStorage.delete(key: _legacyUserEmailKey);
      await _vaultStorage.delete(key: _legacyUserNameKey);
      await _vaultStorage.delete(key: _legacyUserIdKey);
    } catch (_) {}
  }
}
