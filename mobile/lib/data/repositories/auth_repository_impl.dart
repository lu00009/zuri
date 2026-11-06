import 'package:dio/dio.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/local/secure_token_storage.dart';
import '../datasources/remote/auth_remote_data_source.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource remoteDataSource;
  final SecureTokenStorage tokenStorage;

  AuthRepositoryImpl({
    required this.remoteDataSource,
    required this.tokenStorage,
  });

  @override
  Future<AuthUser> register({
    required String email,
    required String password,
    String name = '',
  }) async {
    final response = await remoteDataSource.register(
      email: email,
      password: password,
      name: name,
    );
    final user = AuthUser.fromJson(response);
    await saveCachedUser(user);
    return user;
  }

  @override
  Future<AuthUser> login({
    required String email,
    required String password,
  }) async {
    await remoteDataSource.login(
      email: email,
      password: password,
    );
    final profile = await remoteDataSource.getMe();
    final user = AuthUser.fromJson(profile);
    await saveCachedUser(user);
    return user;
  }

  @override
  Future<AuthUser?> getMe() async {
    try {
      final response = await remoteDataSource.getMe();
      final user = AuthUser.fromJson(response);
      await saveCachedUser(user);
      return user;
    } on DioException catch (dioErr) {
      // 401 Unauthorized means access token is expired or invalid
      if (dioErr.response?.statusCode == 401) {
        return null;
      }
      // Rethrow connectivity / timeout / server cold-start errors so session persistence logic can preserve offline session
      rethrow;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> refreshToken() async {
    return remoteDataSource.refreshToken();
  }

  @override
  Future<void> logout() async {
    await remoteDataSource.logout();
    await tokenStorage.clearAll();
  }

  @override
  Future<bool> isAuthenticated() async {
    return tokenStorage.hasTokens();
  }

  @override
  Future<AuthUser?> getCachedUser() async {
    final data = await tokenStorage.getUserData();
    final email = data['email'];
    if (email == null || email.isEmpty) return null;

    return AuthUser(
      id: data['id'] ?? '',
      email: email,
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
