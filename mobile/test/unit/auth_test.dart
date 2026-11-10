import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbrain/data/datasources/local/secure_token_storage.dart';
import 'package:pocketbrain/domain/entities/auth_user.dart';
import 'package:pocketbrain/domain/repositories/auth_repository.dart';
import 'package:pocketbrain/presentation/providers/auth_provider.dart';

class InMemorySecureTokenStorage implements SecureTokenStorage {
  String? _accessToken;
  String? _refreshToken;
  String? _email;
  String? _name;
  String? _userId;

  @override
  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  @override
  Future<String?> getAccessToken() async => _accessToken;

  @override
  Future<String?> getRefreshToken() async => _refreshToken;

  @override
  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
  }

  @override
  Future<bool> hasTokens() async => _accessToken != null && _accessToken!.isNotEmpty;

  @override
  Future<void> saveUserData({required String email, String? name, String? userId}) async {
    _email = email;
    _name = name;
    _userId = userId;
  }

  @override
  Future<Map<String, String?>> getUserData() async {
    return {
      'email': _email,
      'name': _name,
      'id': _userId,
    };
  }

  @override
  Future<void> clearAll() async {
    _accessToken = null;
    _refreshToken = null;
    _email = null;
    _name = null;
    _userId = null;
  }
}

class FakeAuthRepository implements AuthRepository {
  final InMemorySecureTokenStorage tokenStorage;
  bool shouldFailLogin = false;
  bool shouldFailRefresh = false;
  bool isNetworkDown = false;
  AuthUser? currentUser;

  FakeAuthRepository(this.tokenStorage);

  @override
  Future<AuthUser> register({
    required String email,
    required String password,
    String name = '',
  }) async {
    final user = AuthUser(id: 'new-id-123', email: email, name: name);
    currentUser = user;
    return user;
  }

  @override
  Future<AuthUser> login({
    required String email,
    required String password,
  }) async {
    if (shouldFailLogin) {
      throw Exception('Invalid credentials');
    }
    await tokenStorage.saveTokens(
      accessToken: 'access-token-123',
      refreshToken: 'refresh-token-456',
    );
    final user = AuthUser(id: 'user-id-123', email: email, name: 'Alice');
    currentUser = user;
    await saveCachedUser(user);
    return user;
  }

  @override
  Future<AuthUser> googleAuth({
    required String email,
    String? name,
    String? idToken,
    String? googleId,
  }) async {
    await tokenStorage.saveTokens(
      accessToken: 'google-access-token-123',
      refreshToken: 'google-refresh-token-456',
    );
    final user = AuthUser(id: 'google-id-123', email: email, name: name ?? 'Google User');
    currentUser = user;
    await saveCachedUser(user);
    return user;
  }

  @override
  Future<String> forgotPassword(String email) async {
    return 'Verification code sent to $email';
  }

  @override
  Future<String> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    return 'Password reset successfully';
  }

  @override
  Future<AuthUser?> getMe() async {
    if (isNetworkDown) {
      throw Exception('Network unreachable');
    }
    return currentUser;
  }

  @override
  Future<bool> refreshToken() async {
    if (shouldFailRefresh) {
      await tokenStorage.clearTokens();
      return false;
    }
    await tokenStorage.saveTokens(
      accessToken: 'new-access-token-789',
      refreshToken: 'new-refresh-token-012',
    );
    return true;
  }

  @override
  Future<void> logout() async {
    currentUser = null;
    await tokenStorage.clearAll();
  }

  @override
  Future<bool> isAuthenticated() async {
    return tokenStorage.hasTokens();
  }

  @override
  Future<AuthUser?> getCachedUser() async {
    final data = await tokenStorage.getUserData();
    if (data['email'] == null) return null;
    return AuthUser(
      id: data['id'] ?? '',
      email: data['email']!,
      name: data['name'] ?? '',
    );
  }

  @override
  Future<void> saveCachedUser(AuthUser user) async {
    await tokenStorage.saveUserData(
      email: user.email,
      name: user.name,
      userId: user.id,
    );
  }
}

void main() {
  group('SecureTokenStorage tests', () {
    test('saveTokens, getAccessToken, clearTokens', () async {
      final storage = InMemorySecureTokenStorage();
      expect(await storage.hasTokens(), isFalse);

      await storage.saveTokens(accessToken: 'atk-1', refreshToken: 'rtk-1');
      expect(await storage.hasTokens(), isTrue);
      expect(await storage.getAccessToken(), 'atk-1');
      expect(await storage.getRefreshToken(), 'rtk-1');

      await storage.clearTokens();
      expect(await storage.hasTokens(), isFalse);
    });

    test('saveUserData and clearAll', () async {
      final storage = InMemorySecureTokenStorage();
      await storage.saveUserData(email: 'test@example.com', name: 'Tester', userId: 'u1');
      final data = await storage.getUserData();
      expect(data['email'], 'test@example.com');
      expect(data['name'], 'Tester');

      await storage.clearAll();
      final cleared = await storage.getUserData();
      expect(cleared['email'], isNull);
    });
  });

  group('AuthNotifier & State Management tests', () {
    late InMemorySecureTokenStorage tokenStorage;
    late FakeAuthRepository repository;

    setUp(() {
      tokenStorage = InMemorySecureTokenStorage();
      repository = FakeAuthRepository(tokenStorage);
    });

    test('Initializes to unauthenticated when storage has no tokens', () async {
      final notifier = AuthNotifier(repository);
      await notifier.initialize();

      expect(notifier.state.status, AuthStatus.unauthenticated);
      expect(notifier.state.isAuthenticated, isFalse);
    });

    test('Restores session when tokens exist and getMe succeeds', () async {
      await tokenStorage.saveTokens(accessToken: 'valid-token', refreshToken: 'valid-refresh');
      repository.currentUser = const AuthUser(id: 'uid-1', email: 'alice@example.com', name: 'Alice');

      final notifier = AuthNotifier(repository);
      await notifier.initialize();

      expect(notifier.state.status, AuthStatus.authenticated);
      expect(notifier.state.isAuthenticated, isTrue);
      expect(notifier.state.user?.email, 'alice@example.com');
      expect(notifier.state.isOffline, isFalse);
    });

    test('Successful login updates state to authenticated', () async {
      final notifier = AuthNotifier(repository);
      await notifier.initialize();

      final success = await notifier.login(email: 'alice@example.com', password: 'password123');
      expect(success, isTrue);
      expect(notifier.state.status, AuthStatus.authenticated);
      expect(notifier.state.user?.email, 'alice@example.com');
      expect(await tokenStorage.hasTokens(), isTrue);
    });

    test('Failed login transitions to failure state with error message', () async {
      repository.shouldFailLogin = true;
      final notifier = AuthNotifier(repository);
      await notifier.initialize();

      final success = await notifier.login(email: 'alice@example.com', password: 'wrong');
      expect(success, isFalse);
      expect(notifier.state.status, AuthStatus.failure);
      expect(notifier.state.errorMessage, isNotNull);
    });

    test('Successful registration logs in and updates state to authenticated', () async {
      final notifier = AuthNotifier(repository);
      await notifier.initialize();

      final success = await notifier.register(
        name: 'Bob',
        email: 'bob@example.com',
        password: 'password123',
      );
      expect(success, isTrue);
      expect(notifier.state.status, AuthStatus.authenticated);
      expect(notifier.state.user?.email, 'bob@example.com');
    });

    test('Logout clears credentials and sets state to unauthenticated', () async {
      await notifierLogin(repository);
      final notifier = AuthNotifier(repository);
      await notifier.initialize();

      expect(notifier.state.isAuthenticated, isTrue);

      await notifier.logout();
      expect(notifier.state.status, AuthStatus.unauthenticated);
      expect(notifier.state.isAuthenticated, isFalse);
      expect(notifier.state.user, isNull);
      expect(await tokenStorage.hasTokens(), isFalse);
    });

    test('Token refresh on session restoration when access token expired', () async {
      await tokenStorage.saveTokens(accessToken: 'expired-token', refreshToken: 'valid-refresh');
      repository.currentUser = null; // getMe fails first time

      final notifier = AuthNotifier(repository);
      // Mock refresh succeeds and sets currentUser
      repository.shouldFailRefresh = false;
      await notifier.initialize();

      expect(await tokenStorage.getAccessToken(), 'new-access-token-789');
    });

    test('Failed token refresh resets state to unauthenticated', () async {
      await tokenStorage.saveTokens(accessToken: 'expired-token', refreshToken: 'revoked-refresh');
      repository.currentUser = null;
      repository.shouldFailRefresh = true;

      final notifier = AuthNotifier(repository);
      await notifier.initialize();

      expect(notifier.state.status, AuthStatus.unauthenticated);
      expect(notifier.state.isAuthenticated, isFalse);
    });

    test('Temporary network disconnection preserves authenticated offline state and cached user', () async {
      await tokenStorage.saveTokens(accessToken: 'valid-token', refreshToken: 'valid-refresh');
      await tokenStorage.saveUserData(email: 'alice@example.com', name: 'Alice', userId: 'u1');
      repository.isNetworkDown = true;

      final notifier = AuthNotifier(repository);
      await notifier.initialize();

      expect(notifier.state.status, AuthStatus.authenticated);
      expect(notifier.state.isAuthenticated, isTrue);
      expect(notifier.state.isOffline, isTrue);
      expect(notifier.state.user?.email, 'alice@example.com');
    });
  });
}

Future<void> notifierLogin(FakeAuthRepository repo) async {
  await repo.login(email: 'alice@example.com', password: 'password123');
}
