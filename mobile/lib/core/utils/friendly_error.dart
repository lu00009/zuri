import 'package:dio/dio.dart';

class FriendlyError {
  /// Checks whether an exception is caused by network issues (timeouts, disconnects, DNS, server cold-starts).
  static bool isNetworkError(dynamic error) {
    if (error == null) return false;

    if (error is DioException) {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionError) {
        return true;
      }
      final statusCode = error.response?.statusCode;
      if (statusCode == 502 || statusCode == 503 || statusCode == 504) {
        return true;
      }
      final errStr = (error.error ?? '').toString().toLowerCase();
      if (errStr.contains('socketexception') ||
          errStr.contains('failed host lookup') ||
          errStr.contains('network is unreachable') ||
          errStr.contains('connection refused') ||
          errStr.contains('os error')) {
        return true;
      }
    }

    final rawStr = error.toString().toLowerCase();
    return rawStr.contains('socketexception') ||
        rawStr.contains('connection refused') ||
        rawStr.contains('unreachable') ||
        rawStr.contains('failed host lookup') ||
        rawStr.contains('connection error') ||
        rawStr.contains('timed out') ||
        rawStr.contains('clientexception') ||
        rawStr.contains('xmlhttprequest error');
  }

  /// Converts any error into a warm, non-technical message suitable for everyday users.
  static String toFriendlyMessage(
    dynamic error, {
    String defaultFallback = 'Unable to complete your request. Please try again in a moment.',
  }) {
    if (isNetworkError(error)) {
      return 'Unable to connect to Zuri right now. Please check your internet connection and try again.';
    }

    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['detail'] != null) {
        return data['detail'].toString();
      }
      if (error.response?.statusCode == 401) {
        return 'Your session has expired. Please log in again.';
      }
      if (error.response?.statusCode == 404) {
        return 'The requested information could not be found.';
      }
    }

    return defaultFallback;
  }
}
