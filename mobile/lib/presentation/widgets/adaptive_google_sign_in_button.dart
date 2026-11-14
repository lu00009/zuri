import 'package:flutter/material.dart';
import 'google_sign_in_button_stub.dart'
    if (dart.library.js_interop) 'google_sign_in_button_web.dart';

class AdaptiveGoogleSignInButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isLoading;
  final Widget fallbackButton;

  const AdaptiveGoogleSignInButton({
    super.key,
    required this.onPressed,
    required this.isLoading,
    required this.fallbackButton,
  });

  @override
  Widget build(BuildContext context) {
    return buildGoogleSignInButton(
      context: context,
      onPressed: onPressed,
      isLoading: isLoading,
      child: fallbackButton,
    );
  }
}

