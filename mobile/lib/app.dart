import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'presentation/providers/auth_provider.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/screens/ai_memory_screen.dart';
import 'presentation/screens/auth/forgot_password_screen.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/auth/register_screen.dart';
import 'presentation/screens/folder_detail_screen.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/memory_recap_screen.dart';
import 'presentation/screens/note_editor_screen.dart';

class AuthRouterListenable extends ChangeNotifier {
  final Ref _ref;

  AuthRouterListenable(this._ref) {
    _ref.listen<AuthState>(authProvider, (previous, next) {
      notifyListeners();
    });
  }
}

final authRouterListenableProvider = Provider<AuthRouterListenable>((ref) {
  return AuthRouterListenable(ref);
});

final routerProvider = Provider<GoRouter>((ref) {
  final refreshListenable = ref.watch(authRouterListenableProvider);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final isAuth = auth.isAuthenticated;
      final location = state.matchedLocation;
      final isAuthRoute = location == '/login' ||
          location == '/register' ||
          location == '/forgot-password';

      // While initializing, don't force redirect yet
      if (auth.status == AuthStatus.initial || auth.status == AuthStatus.refreshing) {
        return null;
      }

      // If user is unauthenticated and tries to access protected route, redirect to /login
      if (!isAuth && !isAuthRoute) {
        return '/login';
      }

      // If user is authenticated and is on an auth route, redirect to home /
      if (isAuth && isAuthRoute) {
        return '/';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
        routes: [
          GoRoute(
            path: 'note/new',
            builder: (context, state) => NoteEditorScreen(
              initialFolderId: state.uri.queryParameters['folderId'],
            ),
          ),
          GoRoute(
            path: 'note/:id',
            builder: (context, state) {
              final noteId = state.pathParameters['id'];
              return NoteEditorScreen(noteId: noteId);
            },
          ),
          GoRoute(
            path: 'folder/:id',
            builder: (context, state) {
              final folderId = state.pathParameters['id'] ?? '';
              return FolderDetailScreen(folderId: folderId);
            },
          ),
          GoRoute(
            path: 'ai',
            builder: (context, state) => const AiMemoryScreen(),
          ),
          GoRoute(
            path: 'recap',
            builder: (context, state) => const MemoryRecapScreen(),
          ),
        ],
      ),
    ],
  );
});

typedef ZuriApp = PocketBrainApp;

class PocketBrainApp extends ConsumerWidget {
  const PocketBrainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Zuri',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ).copyWith(
          surface: Colors.white,
          onSurface: const Color(0xFF0F172A),
          onSurfaceVariant: const Color(0xFF64748B),
          surfaceContainerHighest: const Color(0xFFF1F5F9),
          outlineVariant: const Color(0xFFE2E8F0),
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: Color(0xFFF8FAFC),
          foregroundColor: Color(0xFF0F172A),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          brightness: Brightness.dark,
        ).copyWith(
          surface: const Color(0xFF1E1E22),
          onSurface: Colors.white,
          onSurfaceVariant: const Color(0xFF9E9EA7),
          surfaceContainerHighest: const Color(0xFF2A2A2E),
          outlineVariant: const Color(0xFF2A2A2E),
        ),
        scaffoldBackgroundColor: const Color(0xFF121214),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: Color(0xFF121214),
          foregroundColor: Colors.white,
        ),
      ),
      themeMode: themeMode,
    );
  }
}
