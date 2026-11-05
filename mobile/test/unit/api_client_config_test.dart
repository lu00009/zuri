import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbrain/data/datasources/remote/api_client.dart';

void main() {
  group('ApiClient Base URL Configuration Tests', () {
    test('getDefaultBaseUrl returns a valid URI and does not crash', () {
      final url = ApiClient.getDefaultBaseUrl();
      expect(url, isNotEmpty);
      final uri = Uri.parse(url);
      expect(uri.scheme, anyOf('http', 'https'));
      expect(uri.host, isNotEmpty);
    });

    test('Custom baseUrl passed to ApiClient constructor overrides defaults', () {
      final client = ApiClient(baseUrl: 'https://api.pocketbrain.example.com/api/v1');
      expect(client.dio.options.baseUrl, 'https://api.pocketbrain.example.com/api/v1');
    });

    test('Default baseUrl ends with /api/v1', () {
      final url = ApiClient.getDefaultBaseUrl();
      expect(url.endsWith('/api/v1'), isTrue);
    });

    test('Android emulator target platform resolves to 10.0.2.2 or localhost', () {
      final url = ApiClient.getDefaultBaseUrl();
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        expect(url, 'http://10.0.2.2:8000/api/v1');
      } else {
        expect(url, anyOf('http://localhost:8000/api/v1', 'http://10.0.2.2:8000/api/v1'));
      }
    });
  });
}

