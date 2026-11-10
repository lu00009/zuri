import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../providers/sync_provider.dart';
import 'google_logo.dart';

Future<void> showGoogleSignInDialog(BuildContext context, WidgetRef ref) async {
  final emailController = TextEditingController();
  final nameController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  bool isSubmitting = false;
  String? localError;

  await showDialog(
    context: context,
    barrierDismissible: !isSubmitting,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          final theme = Theme.of(context);

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const GoogleLogoWidget(size: 26),
                const SizedBox(width: 12),
                Text(
                  'Sign in with Google',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Connect your Google Account to automatically sync your Zuri notes and memories.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (localError != null) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            localError!,
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      TextFormField(
                        key: const Key('google_auth_email_input'),
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: 'Google Email',
                          hintText: 'name@gmail.com',
                          prefixIcon: const Icon(Icons.email_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surface,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your Google email';
                          }
                          if (!value.contains('@') || !value.contains('.')) {
                            return 'Please enter a valid email address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        key: const Key('google_auth_name_input'),
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: 'Display Name (Optional)',
                          hintText: 'Your name',
                          prefixIcon: const Icon(Icons.person_outline),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('google_auth_confirm_button'),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setState(() {
                          isSubmitting = true;
                          localError = null;
                        });

                        final success = await ref.read(authProvider.notifier).loginWithGoogle(
                              email: emailController.text.trim(),
                              name: nameController.text.trim(),
                            );

                        if (success) {
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                          ref.read(syncProvider.notifier).syncNow();
                          if (context.mounted) {
                            context.go('/');
                          }
                        } else {
                          setState(() {
                            isSubmitting = false;
                            localError = ref.read(authProvider).errorMessage ?? 'Google Sign-In failed';
                          });
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Continue'),
              ),
            ],
          );
        },
      );
    },
  );
}
