import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pocketbrain/domain/entities/auth_user.dart';
import 'package:pocketbrain/domain/repositories/auth_repository.dart';
import 'package:pocketbrain/presentation/providers/auth_provider.dart';
import 'package:pocketbrain/presentation/screens/auth/forgot_password_screen.dart';

class MockForgotAuthRepository implements AuthRepository {
  bool forgotCalled = false;
  bool resetCalled = false;
  String? lastForgotEmail;
  String? lastResetCode;

  @override
  Future<String> forgotPassword(String email) async {
    forgotCalled = true;
    lastForgotEmail = email;
    return 'Verification code sent to $email';
  }

  @override
  Future<String> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    resetCalled = true;
    lastResetCode = code;
    return 'Password reset successfully';
  }

  @override
  Future<AuthUser> login({required String email, required String password}) async {
    return AuthUser(id: '1', email: email, name: 'Test');
  }

  @override
  Future<AuthUser> register({required String email, required String password, String name = ''}) async {
    return AuthUser(id: '1', email: email, name: name);
  }

  @override
  Future<AuthUser> googleAuth({required String email, String? name, String? idToken, String? googleId}) async {
    return AuthUser(id: '1', email: email, name: name ?? '');
  }

  @override
  Future<AuthUser?> getMe() async => null;

  @override
  Future<bool> refreshToken() async => false;

  @override
  Future<void> logout() async {}

  @override
  Future<bool> isAuthenticated() async => false;

  @override
  Future<AuthUser?> getCachedUser() async => null;

  @override
  Future<void> saveCachedUser(AuthUser user) async {}
}

void main() {
  testWidgets('ForgotPasswordScreen 2-step verification and reset flow', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockRepo = MockForgotAuthRepository();
    final router = GoRouter(
      initialLocation: '/forgot-password',
      routes: [
        GoRoute(
          path: '/forgot-password',
          builder: (context, state) => const ForgotPasswordScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const Scaffold(body: Text('Login Screen')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(mockRepo),
        ],
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );

    // Initial step 1: Enter email
    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(find.byKey(const Key('forgot_password_email_input')), findsOneWidget);
    expect(find.byKey(const Key('send_verification_code_button')), findsOneWidget);

    // Send code
    await tester.enterText(find.byKey(const Key('forgot_password_email_input')), 'user@gmail.com');
    await tester.tap(find.byKey(const Key('send_verification_code_button')));
    await tester.pumpAndSettle();

    expect(mockRepo.forgotCalled, isTrue);
    expect(mockRepo.lastForgotEmail, 'user@gmail.com');

    // Advanced to step 2: Enter code and new password
    expect(find.text('Check Your Gmail'), findsOneWidget);
    expect(find.byKey(const Key('verification_code_input')), findsOneWidget);
    expect(find.byKey(const Key('reset_new_password_input')), findsOneWidget);
    expect(find.byKey(const Key('reset_confirm_password_input')), findsOneWidget);
    expect(find.byKey(const Key('reset_password_submit_button')), findsOneWidget);

    // Fill reset form
    await tester.enterText(find.byKey(const Key('verification_code_input')), '123456');
    await tester.enterText(find.byKey(const Key('reset_new_password_input')), 'newSecretPassword123');
    await tester.enterText(find.byKey(const Key('reset_confirm_password_input')), 'newSecretPassword123');

    await tester.ensureVisible(find.byKey(const Key('reset_password_submit_button')));
    await tester.tap(find.byKey(const Key('reset_password_submit_button')));
    await tester.pumpAndSettle();

    expect(mockRepo.resetCalled, isTrue);
    expect(mockRepo.lastResetCode, '123456');
    expect(find.text('Password Reset!'), findsOneWidget);
  });
}

