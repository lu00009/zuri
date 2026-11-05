import 'dart:io';

import 'package:dio/dio.dart';
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
               baseUrl: baseUrl ?? _getDefaultBaseUrl(),
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

  static String _getDefaultBaseUrl() {
    if (Platform.isAndroid) {
      // Android emulator reaches host machine via 10.0.2.2
      return 'http://10.0.2.2:8000/api/v1';
    }
    // Linux desktop, macOS, Windows
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
