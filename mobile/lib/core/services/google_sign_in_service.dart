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
  // Compile-time environment configuration (--dart-define=GOOGLE_CLIENT_ID=...)
  static const String clientId = String.fromEnvironment('GOOGLE_CLIENT_ID');

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: clientId.isNotEmpty ? clientId : null,
    scopes: const ['email', 'profile', 'openid'],
  );

  /// Initiates Google Sign-In flow and returns the verified ID token.
  /// Returns null if the user cancelled the prompt.
  static Future<GoogleAuthResult?> signIn() async {
    try {
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

      if (errStr.contains('popup_closed') || errStr.contains('cancelled') || errStr.contains('canceled')) {
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

