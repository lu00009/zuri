import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/services/google_sign_in_service.dart';
import '../../core/utils/friendly_error.dart';
import '../../data/datasources/local/app_database.dart';
import '../../data/datasources/local/secure_token_storage.dart';
import '../../data/datasources/remote/api_client.dart';
import '../../data/datasources/remote/auth_remote_data_source.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';
import 'notes_provider.dart';
import 'sync_provider.dart';

enum AuthStatus {
  initial,
  unauthenticated,
  authenticating,
  authenticated,
  refreshing,
  failure,
}

class AuthState {
  final AuthStatus status;
  final AuthUser? user;
  final String? errorMessage;
  final bool isOffline;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.errorMessage,
    this.isOffline = false,
  });

  bool get isAuthenticated =>
      status == AuthStatus.authenticated ||
      (status == AuthStatus.initial && user != null);

  bool get isLoading =>
      status == AuthStatus.authenticating ||
      status == AuthStatus.refreshing;

  AuthState copyWith({
    AuthStatus? status,
    AuthUser? user,
    String? errorMessage,
    bool? isOffline,
    bool clearError = false,
    bool clearUser = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isOffline: isOffline ?? this.isOffline,
    );
  }
}

final secureTokenStorageProvider = Provider<SecureTokenStorage>((ref) {
  return const FlutterSecureTokenStorage();
});

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return AuthRemoteDataSource(apiClient);
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final remote = ref.watch(authRemoteDataSourceProvider);
  final storage = ref.watch(secureTokenStorageProvider);
  return AuthRepositoryImpl(remoteDataSource: remote, tokenStorage: storage);
});

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repository;
  final ApiClient? _apiClient;
  final Ref? _ref;

  AuthNotifier(this._repository, [this._apiClient, this._ref]) : super(const AuthState(status: AuthStatus.initial)) {
    if (_apiClient != null) {
      _apiClient.onSessionExpired = () => logout();
    }
    _setupWebGoogleAuthListener();
    initialize();
  }

  void _setupWebGoogleAuthListener() {
    if (kIsWeb) {
      GoogleSignInService.onCurrentUserChanged.listen((account) async {
        if (account != null && !state.isAuthenticated && state.status != AuthStatus.authenticating) {
          try {
            final auth = await account.authentication;
            final token = auth.idToken ?? auth.accessToken;
            if (token != null && token.isNotEmpty) {
              await loginWithGoogle(
                idToken: token,
                email: account.email,
                name: account.displayName,
                googleId: account.id,
              );
            }
          } catch (e) {
            debugPrint('Web Google auto-auth error: $e');
          }
        }
      });
    }
  }

  Future<void> initialize() async {
    final hasTokens = await _repository.isAuthenticated();
    if (!hasTokens) {
      state = state.copyWith(status: AuthStatus.unauthenticated, clearUser: true);
      return;
    }

    state = state.copyWith(status: AuthStatus.refreshing);

    // Read cached user identity early so UI immediately has user state if offline
    final cachedUser = await _repository.getCachedUser();

    try {
      final user = await _repository.getMe();
      if (user != null) {
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          isOffline: false,
          clearError: true,
        );
        return;
      }

      // Access token was rejected with 401; attempt token refresh
      final refreshed = await _repository.refreshToken();
      if (refreshed) {
        final refreshedUser = await _repository.getMe();
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: refreshedUser ?? cachedUser,
          isOffline: false,
          clearError: true,
        );
      } else {
        // Refresh token itself was rejected or expired
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          clearUser: true,
        );
      }
    } on DioException catch (dioErr) {
      final statusCode = dioErr.response?.statusCode;

      // Only if the server explicitly returned 401 or 403 do we attempt refresh or conclude session is invalid
      if (statusCode == 401 || statusCode == 403) {
        try {
          final refreshed = await _repository.refreshToken();
          if (refreshed) {
            final refreshedUser = await _repository.getMe();
            state = state.copyWith(
              status: AuthStatus.authenticated,
              user: refreshedUser ?? cachedUser,
              isOffline: false,
              clearError: true,
            );
            return;
          }
        } catch (_) {}

        // Both access and refresh tokens failed authentication
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          clearUser: true,
        );
      } else {
        // Any connectivity error, timeout, socket exception, or server waking (502/503/504):
        // PRESERVE SESSION! User remains logged in with offline access to notes and collections.
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: cachedUser,
          isOffline: true,
          clearError: true,
        );
      }
    } catch (_) {
      if (cachedUser != null) {
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: cachedUser,
          isOffline: true,
          clearError: true,
        );
      } else {
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          clearUser: true,
        );
      }
    }
  }

  Future<bool> login({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(
      status: AuthStatus.authenticating,
      clearError: true,
    );

    try {
      final user = await _repository.login(
        email: email.trim(),
        password: password,
      );
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        isOffline: false,
        clearError: true,
      );
      return true;
    } on DioException catch (e) {
      final message = FriendlyError.toFriendlyMessage(
        e,
        defaultFallback: 'Login failed. Please check your credentials.',
      );
      state = state.copyWith(
        status: AuthStatus.failure,
        errorMessage: message,
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.failure,
        errorMessage: FriendlyError.toFriendlyMessage(e),
      );
      return false;
    }
  }

  Future<String?> register({
    required String email,
    required String password,
    String name = '',
  }) async {
    state = state.copyWith(
      status: AuthStatus.authenticating,
      clearError: true,
    );

    try {
      final result = await _repository.register(
        email: email.trim(),
        password: password,
        name: name.trim(),
      );
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: result.user,
        isOffline: false,
        clearError: true,
      );
      return result.recoveryCode;
    } on DioException catch (e) {
      final message = FriendlyError.toFriendlyMessage(
        e,
        defaultFallback: 'Registration failed. Please try again.',
      );
      state = state.copyWith(
        status: AuthStatus.failure,
        errorMessage: message,
      );
      return null;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.failure,
        errorMessage: FriendlyError.toFriendlyMessage(e),
      );
      return null;
    }
  }

  Future<bool> loginWithGoogle({
    String? idToken,
    String? email,
    String? name,
    String? googleId,
  }) async {
    state = state.copyWith(
      status: AuthStatus.authenticating,
      clearError: true,
    );

    try {
      String? token = idToken;
      String? userEmail = email;
      String? userName = name;

      // If no token passed, invoke Google Sign-In SDK
      if (token == null || token.isEmpty) {
        final googleResult = await GoogleSignInService.signIn();
        if (googleResult == null) {
          // User dismissed or cancelled the Google prompt
          state = state.copyWith(status: AuthStatus.unauthenticated);
          return false;
        }
        token = googleResult.idToken;
        userEmail = googleResult.email;
        userName = googleResult.displayName;
      }

      final user = await _repository.googleAuth(
        idToken: token,
        clientId: GoogleSignInService.clientId,
        email: userEmail,
        name: userName,
        googleId: googleId,
      );

      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        isOffline: false,
        clearError: true,
      );
      return true;
    } on DioException catch (e) {
      final message = FriendlyError.toFriendlyMessage(
        e,
        defaultFallback: 'Google authentication failed. Please try again.',
      );
      state = state.copyWith(
        status: AuthStatus.failure,
        errorMessage: message,
      );
      return false;
    } catch (e) {
      final errStr = e.toString();
      final friendly = errStr.contains('People API') || errStr.contains('people.googleapis.com')
          ? FriendlyError.toFriendlyMessage(e)
          : (errStr.contains('sign_in_failed') || errStr.contains('PlatformException'))
              ? 'Google Sign-In is unavailable or cancelled. Please try again or use email sign-in.'
              : FriendlyError.toFriendlyMessage(e);

      state = state.copyWith(
        status: AuthStatus.failure,
        errorMessage: friendly,
      );
      return false;
    }
  }

  Future<String> recoveryReset({
    required String email,
    required String recoveryCode,
    required String newPassword,
  }) async {
    try {
      final message = await _repository.recoveryReset(
        email: email.trim(),
        recoveryCode: recoveryCode.trim(),
        newPassword: newPassword,
      );
      return message;
    } on DioException catch (e) {
      final msg = FriendlyError.toFriendlyMessage(
        e,
        defaultFallback: 'Invalid email address or recovery code.',
      );
      throw Exception(msg);
    } catch (e) {
      throw Exception(FriendlyError.toFriendlyMessage(e));
    }
  }

  Future<String> regenerateRecoveryCode() async {
    try {
      return await _repository.regenerateRecoveryCode();
    } on DioException catch (e) {
      final msg = FriendlyError.toFriendlyMessage(
        e,
        defaultFallback: 'Could not regenerate recovery code.',
      );
      throw Exception(msg);
    } catch (e) {
      throw Exception(FriendlyError.toFriendlyMessage(e));
    }
  }

  Future<String> forgotPassword(String email) async {
    try {
      final message = await _repository.forgotPassword(email.trim());
      return message;
    } on DioException catch (e) {
      final msg = FriendlyError.toFriendlyMessage(
        e,
        defaultFallback: 'Could not send verification code. Please check the email.',
      );
      throw Exception(msg);
    } catch (e) {
      throw Exception(FriendlyError.toFriendlyMessage(e));
    }
  }

  Future<String> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    try {
      final message = await _repository.resetPassword(
        email: email.trim(),
        code: code.trim(),
        newPassword: newPassword,
      );
      return message;
    } on DioException catch (e) {
      final msg = FriendlyError.toFriendlyMessage(
        e,
        defaultFallback: 'Invalid or expired verification code.',
      );
      throw Exception(msg);
    } catch (e) {
      throw Exception(FriendlyError.toFriendlyMessage(e));
    }
  }

  Future<void> logout() async {
    try {
      await _repository.logout();
    } catch (_) {
      // Best-effort logout
    }

    try {
      await AppDatabase.clearAllData();
      const storage = FlutterSecureStorage();
      await storage.delete(key: 'pocketbrain_sync_watermark');
    } catch (_) {
      // Best-effort cleanup
    }

    try {
      final ref = _ref;
      if (ref != null) {
        ref.read(notesListProvider.notifier).clearNotes();
        ref.read(syncProvider.notifier).checkPendingCount();
      }
    } catch (_) {}

    state = state.copyWith(
      status: AuthStatus.unauthenticated,
      clearUser: true,
      clearError: true,
      isOffline: false,
    );
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  final apiClient = ref.watch(apiClientProvider);
  return AuthNotifier(repo, apiClient, ref);
});
