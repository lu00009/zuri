import 'package:dio/dio.dart';

class FriendlyError {
  /// Checks whether an exception is caused by network issues (timeouts, disconnects, DNS, server cold-starts).
  static bool isNetworkError(dynamic error) {
    if (error == null) return false;

    if (error is DioException) {
      if (error.response != null) {
        final statusCode = error.response?.statusCode;
        return statusCode == 502 || statusCode == 503 || statusCode == 504;
      }

      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionError) {
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
        rawStr.contains('network is unreachable') ||
        rawStr.contains('os error') ||
        rawStr.contains('connection error') ||
        rawStr.contains('timed out') ||
        rawStr.contains('xmlhttprequest error');
  }

  /// Converts any error into a warm, non-technical message suitable for everyday users.
  static String toFriendlyMessage(
    dynamic error, {
    String defaultFallback = 'Unable to complete your request. Please try again in a moment.',
  }) {
    if (error == null) return defaultFallback;

    // If the server returned an explicit response (e.g. 400, 401, 404, 422 with detail message),
    // prioritize displaying the server's explanation.
    if (error is DioException && error.response != null) {
      final data = error.response?.data;
      if (data is Map && data['detail'] != null) {
        return data['detail'].toString();
      }
      final statusCode = error.response?.statusCode;
      if (statusCode == 401) {
        return 'Your session has expired. Please log in again.';
      }
      if (statusCode == 404) {
        return 'The requested information could not be found.';
      }
      if (statusCode == 502 || statusCode == 503 || statusCode == 504) {
        return 'Unable to connect to Zuri right now. Please check your internet connection and try again.';
      }
    }

    if (isNetworkError(error)) {
      return 'Unable to connect to Zuri right now. Please check your internet connection and try again.';
    }

    final rawStr = error.toString();
    if (rawStr.contains('People API') || rawStr.contains('people.googleapis.com')) {
      return 'Google People API is not enabled in your Google Cloud Console project. Please enable it in Google Cloud Console or use the official Google button.';
    }

    if (error is Exception) {
      final cleaned = rawStr.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
      if (cleaned.isNotEmpty && !cleaned.toLowerCase().contains('xmlhttprequest') && !cleaned.toLowerCase().contains('socketexception')) {
        return cleaned;
      }
    }

    return defaultFallback;
  }
}
