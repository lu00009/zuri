import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbrain/data/datasources/local/secure_token_storage.dart';
import 'package:pocketbrain/data/datasources/remote/auth_interceptor.dart';

class TestTokenStorage implements SecureTokenStorage {
  String? accessToken;
  String? refreshToken;

  TestTokenStorage({this.accessToken, this.refreshToken});

  @override
  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }

  @override
  Future<String?> getAccessToken() async => accessToken;

  @override
  Future<String?> getRefreshToken() async => refreshToken;

  @override
  Future<void> clearTokens() async {
    accessToken = null;
    refreshToken = null;
  }

  @override
  Future<bool> hasTokens() async => accessToken != null && accessToken!.isNotEmpty;

  @override
  Future<void> saveUserData({required String email, String? name, String? userId}) async {}

  @override
  Future<Map<String, String?>> getUserData() async => {};

  @override
  Future<void> clearAll() async => clearTokens();
}

class TestRequestHandler extends RequestInterceptorHandler {
  RequestOptions? passedOptions;
  @override
  void next(RequestOptions requestOptions) {
    passedOptions = requestOptions;
  }
}

class TestErrorHandler extends ErrorInterceptorHandler {
  DioException? passedError;
  @override
  void next(DioException err) {
    passedError = err;
  }
}

void main() {
  group('AuthInterceptor Tests', () {
    test('Attaches Bearer token to protected requests', () async {
      final storage = TestTokenStorage(accessToken: 'my-jwt-token');
      final dio = Dio();
      final interceptor = AuthInterceptor(dio: dio, tokenStorage: storage);

      final options = RequestOptions(path: '/notes');
      final handler = TestRequestHandler();

      await interceptor.onRequest(options, handler);

      expect(options.headers['Authorization'], 'Bearer my-jwt-token');
      expect(handler.passedOptions, isNotNull);
    });

    test('Does not attach Bearer token to public auth endpoints', () async {
      final storage = TestTokenStorage(accessToken: 'my-jwt-token');
      final dio = Dio();
      final interceptor = AuthInterceptor(dio: dio, tokenStorage: storage);

      final loginOptions = RequestOptions(path: '/auth/login');
      final handler = TestRequestHandler();

      await interceptor.onRequest(loginOptions, handler);

      expect(loginOptions.headers.containsKey('Authorization'), isFalse);
    });

    test('Does not retry requests that were already retried', () async {
      final storage = TestTokenStorage(accessToken: 'jwt-1', refreshToken: 'ref-1');
      final dio = Dio();
      bool sessionExpiredCalled = false;
      final interceptor = AuthInterceptor(
        dio: dio,
        tokenStorage: storage,
        onSessionExpired: () => sessionExpiredCalled = true,
      );

      final reqOptions = RequestOptions(
        path: '/notes',
        extra: {'retried': true},
      );
      final error = DioException(
        requestOptions: reqOptions,
        response: Response(statusCode: 401, requestOptions: reqOptions),
      );

      final handler = TestErrorHandler();
      await interceptor.onError(error, handler);

      expect(sessionExpiredCalled, isFalse);
      expect(handler.passedError, equals(error));
    });

    test('401 on /auth/refresh clears tokens and invokes onSessionExpired', () async {
      final storage = TestTokenStorage(accessToken: 'jwt-1', refreshToken: 'ref-1');
      final dio = Dio();
      bool sessionExpiredCalled = false;
      final interceptor = AuthInterceptor(
        dio: dio,
        tokenStorage: storage,
        onSessionExpired: () => sessionExpiredCalled = true,
      );

      final reqOptions = RequestOptions(path: '/auth/refresh');
      final error = DioException(
        requestOptions: reqOptions,
        response: Response(statusCode: 401, requestOptions: reqOptions),
      );

      final handler = TestErrorHandler();
      await interceptor.onError(error, handler);

      expect(sessionExpiredCalled, isTrue);
      expect(await storage.hasTokens(), isFalse);
    });
  });
}
