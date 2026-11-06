import 'dart:async';
import 'package:dio/dio.dart';
import '../local/secure_token_storage.dart';

class AuthInterceptor extends QueuedInterceptor {
  final Dio dio;
  final SecureTokenStorage tokenStorage;
  final void Function()? onSessionExpired;

  Completer<String?>? _refreshCompleter;

  AuthInterceptor({
    required this.dio,
    required this.tokenStorage,
    this.onSessionExpired,
  });

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Avoid attaching Bearer token to public auth endpoints if already set or unnecessary
    final path = options.path;
    final isAuthPublic = path.contains('/auth/login') ||
        path.contains('/auth/register') ||
        path.contains('/auth/refresh');

    if (!isAuthPublic && !options.headers.containsKey('Authorization')) {
      final token = await tokenStorage.getAccessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }

    return handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    final requestOptions = err.requestOptions;

    // Check if 401 Unauthorized
    if (response?.statusCode != 401) {
      return handler.next(err);
    }

    // Do not attempt refresh on auth endpoints or already retried requests
    final path = requestOptions.path;
    final isAuthEndpoint = path.contains('/auth/login') ||
        path.contains('/auth/register') ||
        path.contains('/auth/refresh');

    final isAlreadyRetried = requestOptions.extra['retried'] == true;

    if (isAuthEndpoint || isAlreadyRetried) {
      if (path.contains('/auth/refresh')) {
        await tokenStorage.clearTokens();
        onSessionExpired?.call();
      }
      return handler.next(err);
    }

    // Single-flight refresh token mutex
    String? newAccessToken;
    if (_refreshCompleter != null) {
      newAccessToken = await _refreshCompleter!.future;
    } else {
      _refreshCompleter = Completer<String?>();
      try {
        final refreshToken = await tokenStorage.getRefreshToken();
        if (refreshToken == null || refreshToken.isEmpty) {
          await tokenStorage.clearTokens();
          onSessionExpired?.call();
          _refreshCompleter!.complete(null);
          return handler.next(err);
        }

        // Dedicated Dio request for refresh to avoid interceptor recursion
        final refreshDio = Dio(
          BaseOptions(
            baseUrl: dio.options.baseUrl,
            headers: {'Content-Type': 'application/json'},
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15),
          ),
        );

        final refreshResponse = await refreshDio.post(
          '/auth/refresh',
          data: {'refresh_token': refreshToken},
        );

        if (refreshResponse.statusCode == 200) {
          final data = refreshResponse.data as Map<String, dynamic>;
          final access = data['access_token'] as String;
          final refresh = data['refresh_token'] as String;

          await tokenStorage.saveTokens(
            accessToken: access,
            refreshToken: refresh,
          );

          newAccessToken = access;
          _refreshCompleter!.complete(access);
        } else {
          // Explicit non-200 authentication failure
          if (refreshResponse.statusCode == 401 || refreshResponse.statusCode == 403) {
            await tokenStorage.clearTokens();
            onSessionExpired?.call();
          }
          _refreshCompleter!.complete(null);
        }
      } on DioException catch (dioErr) {
        // ONLY clear credentials if the backend explicitly rejected the refresh token as invalid/revoked
        final statusCode = dioErr.response?.statusCode;
        if (statusCode == 401 || statusCode == 403) {
          await tokenStorage.clearTokens();
          onSessionExpired?.call();
        }
        // For network timeouts, connection drops, or temporary 502/503 server cold-starts:
        // NEVER clear credentials! Preserve offline session and saved tokens.
        _refreshCompleter!.complete(null);
      } catch (_) {
        _refreshCompleter!.complete(null);
      } finally {
        _refreshCompleter = null;
      }
    }

    if (newAccessToken != null && newAccessToken.isNotEmpty) {
      requestOptions.headers['Authorization'] = 'Bearer $newAccessToken';
      requestOptions.extra['retried'] = true;

      try {
        final response = await dio.fetch(requestOptions);
        return handler.resolve(response);
      } on DioException catch (retryError) {
        return handler.next(retryError);
      }
    }

    return handler.next(err);
  }
}
