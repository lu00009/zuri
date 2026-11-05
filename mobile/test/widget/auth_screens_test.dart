import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pocketbrain/domain/entities/auth_user.dart';
import 'package:pocketbrain/domain/repositories/auth_repository.dart';
import 'package:pocketbrain/presentation/providers/auth_provider.dart';
import 'package:pocketbrain/presentation/screens/auth/login_screen.dart';
import 'package:pocketbrain/presentation/screens/auth/register_screen.dart';

class MockAuthRepository implements AuthRepository {
  bool loginCalled = false;
  bool registerCalled = false;

  @override
  Future<AuthUser> register({
    required String email,
    required String password,
    String name = '',
  }) async {
    registerCalled = true;
    return AuthUser(id: 'u1', email: email, name: name);
  }

  @override
  Future<AuthUser> login({
    required String email,
    required String password,
  }) async {
    loginCalled = true;
    return AuthUser(id: 'u1', email: email, name: 'Alice');
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
  group('LoginScreen Widget Tests', () {
    testWidgets('Displays all elements and validates email format and password length', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockRepo = MockAuthRepository();
      final router = GoRouter(
        initialLocation: '/login',
        routes: [
          GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
          GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
          GoRoute(path: '/', builder: (context, state) => const Scaffold(body: Text('Home Screen'))),
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

      // Verify initial UI elements
      expect(find.text('Welcome to PocketBrain'), findsOneWidget);
      expect(find.byKey(const Key('login_email_input')), findsOneWidget);
      expect(find.byKey(const Key('login_password_input')), findsOneWidget);
      expect(find.byKey(const Key('login_submit_button')), findsOneWidget);
      expect(find.byKey(const Key('login_go_to_register_button')), findsOneWidget);

      // Tap Sign In with empty fields -> shows validation errors
      await tester.ensureVisible(find.byKey(const Key('login_submit_button')));
      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your email address'), findsOneWidget);
      expect(find.text('Please enter your password'), findsOneWidget);

      // Enter invalid email and short password
      await tester.enterText(find.byKey(const Key('login_email_input')), 'notanemail');
      await tester.enterText(find.byKey(const Key('login_password_input')), '123');
      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid email address'), findsOneWidget);
      expect(find.text('Password must be at least 6 characters'), findsOneWidget);
      expect(mockRepo.loginCalled, isFalse);

      // Enter valid credentials
      await tester.enterText(find.byKey(const Key('login_email_input')), 'user@example.com');
      await tester.enterText(find.byKey(const Key('login_password_input')), 'validpassword123');
      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pumpAndSettle();

      expect(mockRepo.loginCalled, isTrue);
      expect(find.text('Home Screen'), findsOneWidget);
    });
  });

  group('RegisterScreen Widget Tests', () {
    testWidgets('Displays all registration fields and validates matching passwords', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockRepo = MockAuthRepository();
      final router = GoRouter(
        initialLocation: '/register',
        routes: [
          GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
          GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
          GoRoute(path: '/', builder: (context, state) => const Scaffold(body: Text('Home Screen'))),
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

      expect(find.text('Create Your Account'), findsOneWidget);
      expect(find.byKey(const Key('register_name_input')), findsOneWidget);
      expect(find.byKey(const Key('register_email_input')), findsOneWidget);
      expect(find.byKey(const Key('register_password_input')), findsOneWidget);
      expect(find.byKey(const Key('register_confirm_password_input')), findsOneWidget);
      expect(find.byKey(const Key('register_submit_button')), findsOneWidget);

      // Tap register with empty fields
      await tester.ensureVisible(find.byKey(const Key('register_submit_button')));
      await tester.tap(find.byKey(const Key('register_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your name'), findsOneWidget);
      expect(find.text('Please enter your email'), findsOneWidget);
      expect(find.text('Please enter a password'), findsOneWidget);

      // Fill mismatched passwords
      await tester.enterText(find.byKey(const Key('register_name_input')), 'Alice Smith');
      await tester.enterText(find.byKey(const Key('register_email_input')), 'alice@example.com');
      await tester.enterText(find.byKey(const Key('register_password_input')), 'password123');
      await tester.enterText(find.byKey(const Key('register_confirm_password_input')), 'differentpassword');
      await tester.ensureVisible(find.byKey(const Key('register_submit_button')));
      await tester.tap(find.byKey(const Key('register_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(mockRepo.registerCalled, isFalse);

      // Fix confirm password
      await tester.enterText(find.byKey(const Key('register_confirm_password_input')), 'password123');
      await tester.ensureVisible(find.byKey(const Key('register_submit_button')));
      await tester.tap(find.byKey(const Key('register_submit_button')));
      await tester.pumpAndSettle();

      expect(mockRepo.registerCalled, isTrue);
      expect(find.text('Home Screen'), findsOneWidget);
    });
  });
}
