import 'api_client.dart';

class AuthRemoteDataSource {
  final ApiClient _apiClient;

  AuthRemoteDataSource(this._apiClient);

  ApiClient get apiClient => _apiClient;

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    String name = '',
  }) async {
    final response = await _apiClient.dio.post(
      '/auth/register',
      data: {
        'email': email,
        'name': name,
        'password': password,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await _apiClient.dio.post(
      '/auth/login',
      data: {
        'email': email,
        'password': password,
      },
    );

    final data = response.data as Map<String, dynamic>;
    final accessToken = data['access_token'] as String;
    final refreshToken = data['refresh_token'] as String;

    await _apiClient.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );

    return data;
  }

  Future<Map<String, dynamic>> getMe() async {
    final response = await _apiClient.dio.get('/auth/me');
    return response.data as Map<String, dynamic>;
  }

  Future<bool> refreshToken() async {
    final refresh = await _apiClient.getRefreshToken();
    if (refresh == null || refresh.isEmpty) return false;

    try {
      final response = await _apiClient.dio.post(
        '/auth/refresh',
        data: {'refresh_token': refresh},
      );
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        await _apiClient.saveTokens(
          accessToken: data['access_token'] as String,
          refreshToken: data['refresh_token'] as String,
        );
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> logout() async {
    try {
      final refreshToken = await _apiClient.getRefreshToken();
      await _apiClient.dio.post(
        '/auth/logout',
        data: {'refresh_token': refreshToken},
      );
    } catch (_) {
      // Best-effort remote revocation; always clear locally
    } finally {
      await _apiClient.clearTokens();
    }
  }

  Future<Map<String, dynamic>> forgotPassword(String email) async {
    final response = await _apiClient.dio.post(
      '/auth/forgot-password',
      data: {'email': email.trim()},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final response = await _apiClient.dio.post(
      '/auth/reset-password',
      data: {
        'email': email.trim(),
        'code': code.trim(),
        'new_password': newPassword,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> googleAuth({
    required String email,
    String? name,
    String? idToken,
    String? googleId,
  }) async {
    final payload = <String, dynamic>{
      'email': email.trim(),
    };
    if (name != null && name.isNotEmpty) {
      payload['name'] = name.trim();
    }
    if (idToken != null) {
      payload['id_token'] = idToken;
    }
    if (googleId != null) {
      payload['google_id'] = googleId;
    }

    final response = await _apiClient.dio.post(
      '/auth/google',
      data: payload,
    );
    final data = response.data as Map<String, dynamic>;
    final accessToken = data['access_token'] as String;
    final refreshToken = data['refresh_token'] as String;

    await _apiClient.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    return data;
  }

  Future<bool> isAuthenticated() async {
    final token = await _apiClient.getAccessToken();
    return token != null && token.isNotEmpty;
  }
}
