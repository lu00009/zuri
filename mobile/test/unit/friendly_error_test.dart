import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbrain/core/utils/friendly_error.dart';

void main() {
  group('FriendlyError Tests', () {
    test('isNetworkError detects DioException network timeouts and connection errors', () {
      final timeoutErr = DioException(
        requestOptions: RequestOptions(path: '/test'),
        type: DioExceptionType.connectionTimeout,
      );
      expect(FriendlyError.isNetworkError(timeoutErr), isTrue);

      final connErr = DioException(
        requestOptions: RequestOptions(path: '/test'),
        type: DioExceptionType.connectionError,
      );
      expect(FriendlyError.isNetworkError(connErr), isTrue);

      final serverUnavailableErr = DioException(
        requestOptions: RequestOptions(path: '/test'),
        response: Response(
          requestOptions: RequestOptions(path: '/test'),
          statusCode: 503,
        ),
      );
      expect(FriendlyError.isNetworkError(serverUnavailableErr), isTrue);
    });

    test('isNetworkError detects raw socket and connection strings', () {
      expect(FriendlyError.isNetworkError('SocketException: OS Error: Connection refused'), isTrue);
      expect(FriendlyError.isNetworkError('Failed host lookup: pocketbrain-8cp6.onrender.com'), isTrue);
      expect(FriendlyError.isNetworkError('ClientException with SocketException'), isTrue);
      expect(FriendlyError.isNetworkError('XMLHttpRequest error'), isTrue);
      expect(FriendlyError.isNetworkError('Network is unreachable'), isTrue);
    });

    test('toFriendlyMessage returns friendly message for network errors', () {
      final err = 'SocketException: Failed host lookup';
      final msg = FriendlyError.toFriendlyMessage(err);
      expect(msg, 'Unable to connect to Zuri right now. Please check your internet connection and try again.');
    });

    test('toFriendlyMessage parses detail from Dio error when available', () {
      final dioErr = DioException(
        requestOptions: RequestOptions(path: '/test'),
        response: Response(
          requestOptions: RequestOptions(path: '/test'),
          statusCode: 400,
          data: {'detail': 'Invalid email format'},
        ),
      );
      expect(FriendlyError.toFriendlyMessage(dioErr), 'Invalid email format');
    });

    test('toFriendlyMessage returns friendly session expired message on 401', () {
      final dioErr = DioException(
        requestOptions: RequestOptions(path: '/test'),
        response: Response(
          requestOptions: RequestOptions(path: '/test'),
          statusCode: 401,
        ),
      );
      expect(FriendlyError.toFriendlyMessage(dioErr), 'Your session has expired. Please log in again.');
    });
  });
}
