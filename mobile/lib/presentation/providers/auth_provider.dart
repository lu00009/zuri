import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
    initialize();
  }

  Future<void> initialize() async {
    final hasTokens = await _repository.isAuthenticated();
    if (!hasTokens) {
      state = state.copyWith(status: AuthStatus.unauthenticated, clearUser: true);
      return;
    }

    state = state.copyWith(status: AuthStatus.refreshing);

    try {
      final user = await _repository.getMe();
      if (user != null) {
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          isOffline: false,
          clearError: true,
        );
      } else {
        // Access token might be expired; attempt token refresh
        final refreshed = await _repository.refreshToken();
        if (refreshed) {
          final refreshedUser = await _repository.getMe();
          state = state.copyWith(
            status: AuthStatus.authenticated,
            user: refreshedUser,
            isOffline: false,
            clearError: true,
          );
        } else {
          // Token is invalid/revoked; transition to unauthenticated
          state = state.copyWith(
            status: AuthStatus.unauthenticated,
            clearUser: true,
          );
        }
      }
    } on SocketException {
      // Offline network error: allow access if previously authenticated
      final cachedUser = await _repository.getCachedUser();
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: cachedUser,
        isOffline: true,
        clearError: true,
      );
    } on DioException catch (dioErr) {
      if (dioErr.error is SocketException ||
          dioErr.type == DioExceptionType.connectionTimeout ||
          dioErr.type == DioExceptionType.connectionError) {
        // Network offline: retain previous session for offline-first capabilities
        final cachedUser = await _repository.getCachedUser();
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
    } catch (_) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        clearUser: true,
      );
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
      String message = 'Login failed. Please check your credentials.';
      if (e.response?.data is Map && e.response?.data['detail'] != null) {
        message = e.response?.data['detail'].toString() ?? message;
      }
      state = state.copyWith(
        status: AuthStatus.failure,
        errorMessage: message,
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.failure,
        errorMessage: 'An unexpected error occurred: $e',
      );
      return false;
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    String name = '',
  }) async {
    state = state.copyWith(
      status: AuthStatus.authenticating,
      clearError: true,
    );

    try {
      await _repository.register(
        email: email.trim(),
        password: password,
        name: name.trim(),
      );
      // Automatically log in newly registered user
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
      String message = 'Registration failed.';
      if (e.response?.data is Map && e.response?.data['detail'] != null) {
        message = e.response?.data['detail'].toString() ?? message;
      }
      state = state.copyWith(
        status: AuthStatus.failure,
        errorMessage: message,
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.failure,
        errorMessage: 'An unexpected error occurred: $e',
      );
      return false;
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
      if (_ref != null) {
        _ref!.read(notesListProvider.notifier).clearNotes();
        _ref!.read(syncProvider.notifier).checkPendingCount();
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
