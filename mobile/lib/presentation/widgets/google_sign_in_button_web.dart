import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart' as web_gis;

Widget buildGoogleSignInButton({
  required BuildContext context,
  required VoidCallback onPressed,
  required bool isLoading,
  required Widget child,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return SizedBox(
    height: 48,
    child: Center(
      child: web_gis.renderButton(
        configuration: web_gis.GSIButtonConfiguration(
          type: web_gis.GSIButtonType.standard,
          theme: isDark
              ? web_gis.GSIButtonTheme.filledBlack
              : web_gis.GSIButtonTheme.outline,
          size: web_gis.GSIButtonSize.large,
          text: web_gis.GSIButtonText.continueWith,
          shape: web_gis.GSIButtonShape.rectangular,
          minimumWidth: 320,
        ),
      ),
    ),
  );
}

