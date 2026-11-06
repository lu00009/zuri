import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../local/secure_token_storage.dart';
import 'auth_interceptor.dart';

class ApiClient {
  final Dio dio;
  final SecureTokenStorage tokenStorage;
  void Function()? onSessionExpired;

  ApiClient({
    Dio? customDio,
    SecureTokenStorage? customTokenStorage,
    FlutterSecureStorage? customStorage,
    String? baseUrl,
    this.onSessionExpired,
  }) : tokenStorage =
            customTokenStorage ??
            FlutterSecureTokenStorage(
              customStorage ?? const FlutterSecureStorage(),
            ),
        dio =
            customDio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl ?? getDefaultBaseUrl(),
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 10),
                headers: {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
              ),
            ) {
    _setupInterceptors();
  }

  /// Resolves the default base API URL with the following precedence:
  /// 1. Compile-time environment variable injection (`--dart-define=API_BASE_URL=...`).
  /// 2. If Flutter Web in release mode: requires `API_BASE_URL` (never silently defaults to localhost in production).
  /// 3. If Flutter Web in debug mode: defaults to `http://localhost:8000/api/v1`.
  /// 4. If Android (emulator): defaults to `http://10.0.2.2:8000/api/v1`.
  /// 5. Desktop (Linux, macOS, Windows) and iOS local development: defaults to `http://localhost:8000/api/v1`.
  static String getDefaultBaseUrl() {
    const envBaseUrl = String.fromEnvironment('API_BASE_URL');
    if (envBaseUrl.isNotEmpty) {
      return envBaseUrl;
    }

    if (kIsWeb) {
      return 'http://localhost:8000/api/v1';
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      // Android emulator reaches host machine via 10.0.2.2
      return 'http://10.0.2.2:8000/api/v1';
    }

    // Linux desktop, macOS, Windows, iOS local development
    return 'http://localhost:8000/api/v1';
  }

  void _setupInterceptors() {
    dio.interceptors.add(
      AuthInterceptor(
        dio: dio,
        tokenStorage: tokenStorage,
        onSessionExpired: () => onSessionExpired?.call(),
      ),
    );
  }

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await tokenStorage.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  Future<String?> getAccessToken() async {
    return tokenStorage.getAccessToken();
  }

  Future<String?> getRefreshToken() async {
    return tokenStorage.getRefreshToken();
  }

  Future<void> clearTokens() async {
    await tokenStorage.clearTokens();
  }

  Future<bool> hasTokens() async {
    return tokenStorage.hasTokens();
  }
}


