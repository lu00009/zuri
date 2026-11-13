import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleAuthResult {
  final String idToken;
  final String? email;
  final String? displayName;

  GoogleAuthResult({
    required this.idToken,
    this.email,
    this.displayName,
  });
}

class GoogleSignInService {
  // Public Google OAuth Web Client ID (from Google Cloud Console / backend .env)
  static const String defaultClientId =
      '104826039730-l05mam6uqutknbd2bgeceqamtfodngnl.apps.googleusercontent.com';

  // Compile-time environment configuration (--dart-define=GOOGLE_CLIENT_ID=...)
  static const String clientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue: defaultClientId,
  );

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    // Web requires clientId, and serverClientId MUST be null.
    // Android requires serverClientId to request an OpenID Connect idToken from Google Play Services.
    clientId: kIsWeb ? (clientId.isNotEmpty ? clientId : defaultClientId) : null,
    serverClientId: !kIsWeb ? (clientId.isNotEmpty ? clientId : defaultClientId) : null,
    scopes: const ['email', 'profile', 'openid'],
  );

  /// Initiates Google Sign-In flow and returns the verified ID token.
  /// Returns null if the user cancelled the prompt.
  static Future<GoogleAuthResult?> signIn() async {
    try {
      try {
        if (await _googleSignIn.isSignedIn()) {
          await _googleSignIn.signOut();
        }
      } catch (_) {}

      final account = await _googleSignIn.signIn();
      if (account == null) {
        return null; // User cancelled
      }

      final auth = await account.authentication;
      final idToken = auth.idToken;

      if (idToken == null || idToken.isEmpty) {
        throw Exception(
          'Google did not return an ID token. Ensure Google OAuth client ID is configured correctly.',
        );
      }

      return GoogleAuthResult(
        idToken: idToken,
        email: account.email,
        displayName: account.displayName,
      );
    } catch (e) {
      final errStr = e.toString();
      debugPrint('GoogleSignInService error: $errStr');

      // 12501 is Android SIGN_IN_CANCELLED
      if (errStr.contains('popup_closed') ||
          errStr.contains('cancelled') ||
          errStr.contains('canceled') ||
          errStr.contains('sign_in_canceled') ||
          errStr.contains('12501')) {
        return null;
      }
      rethrow;
    }
  }

  static Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }
}

