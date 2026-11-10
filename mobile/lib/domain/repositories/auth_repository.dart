import '../entities/auth_user.dart';

abstract class AuthRepository {
  Future<AuthUser> register({
    required String email,
    required String password,
    String name = '',
  });

  Future<AuthUser> login({
    required String email,
    required String password,
  });

  Future<AuthUser> googleAuth({
    required String email,
    String? name,
    String? idToken,
    String? googleId,
  });

  Future<String> forgotPassword(String email);

  Future<String> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  });

  Future<AuthUser?> getMe();

  Future<bool> refreshToken();

  Future<void> logout();

  Future<bool> isAuthenticated();

  Future<AuthUser?> getCachedUser();

  Future<void> saveCachedUser(AuthUser user);
}
