import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pocketbrain/domain/entities/auth_user.dart';
import 'package:pocketbrain/domain/repositories/auth_repository.dart';
import 'package:pocketbrain/presentation/providers/auth_provider.dart';
import 'package:pocketbrain/presentation/screens/auth/forgot_password_screen.dart';

class MockForgotAuthRepository implements AuthRepository {
  bool recoveryResetCalled = false;
  String? lastEmail;
  String? lastRecoveryCode;
  String? lastNewPassword;

  @override
  Future<String> recoveryReset({
    required String email,
    required String recoveryCode,
    required String newPassword,
  }) async {
    recoveryResetCalled = true;
    lastEmail = email;
    lastRecoveryCode = recoveryCode;
    lastNewPassword = newPassword;
    return 'Your password has been successfully reset. Please sign in with your new password.';
  }

  @override
  Future<String> regenerateRecoveryCode() async => 'ABCD-EFGH-JKLM-NPQR';

  @override
  Future<String> forgotPassword(String email) async => 'Recovery ready';

  @override
  Future<String> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async => 'Reset successful';

  @override
  Future<AuthUser> login({required String email, required String password}) async {
    return AuthUser(id: '1', email: email, name: 'Test');
  }

  @override
  Future<RegistrationResult> register({required String email, required String password, String name = ''}) async {
    return RegistrationResult(
      user: AuthUser(id: '1', email: email, name: name),
      recoveryCode: 'ABCD-EFGH-JKLM-NPQR',
    );
  }

  @override
  Future<AuthUser> googleAuth({
    required String idToken,
    String? clientId,
    String? email,
    String? name,
    String? googleId,
  }) async {
    return AuthUser(id: '1', email: email ?? 'g@example.com', name: name ?? '');
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
  testWidgets('ForgotPasswordScreen offline recovery code reset flow and help dialog', (tester) async {
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

    // Initial fields check
    expect(find.text('Account Recovery'), findsOneWidget);
    expect(find.byKey(const Key('forgot_password_email_input')), findsOneWidget);
    expect(find.byKey(const Key('verification_code_input')), findsOneWidget);
    expect(find.byKey(const Key('reset_new_password_input')), findsOneWidget);
    expect(find.byKey(const Key('reset_confirm_password_input')), findsOneWidget);
    expect(find.byKey(const Key('reset_password_submit_button')), findsOneWidget);

    // Test lost recovery code help dialog
    await tester.tap(find.byKey(const Key('lost_recovery_code_help_button')));
    await tester.pumpAndSettle();
    expect(find.text('Lost Recovery Code?'), findsOneWidget);
    expect(find.text('Understood'), findsOneWidget);
    await tester.tap(find.text('Understood'));
    await tester.pumpAndSettle();

    // Fill reset form
    await tester.enterText(find.byKey(const Key('forgot_password_email_input')), 'sarah@example.com');
    await tester.enterText(find.byKey(const Key('verification_code_input')), 'ABCD-EFGH-JKLM-NPQR');
    await tester.enterText(find.byKey(const Key('reset_new_password_input')), 'NewSecurePassword123!');
    await tester.enterText(find.byKey(const Key('reset_confirm_password_input')), 'NewSecurePassword123!');

    await tester.ensureVisible(find.byKey(const Key('reset_password_submit_button')));
    await tester.tap(find.byKey(const Key('reset_password_submit_button')));
    await tester.pumpAndSettle();

    expect(mockRepo.recoveryResetCalled, isTrue);
    expect(mockRepo.lastEmail, 'sarah@example.com');
    expect(mockRepo.lastRecoveryCode, 'ABCD-EFGH-JKLM-NPQR');
    expect(mockRepo.lastNewPassword, 'NewSecurePassword123!');

    // Success dialog
    expect(find.text('Password Reset!'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reset_success_login_button')));
    await tester.pumpAndSettle();

    expect(find.text('Login Screen'), findsOneWidget);
  });
}
