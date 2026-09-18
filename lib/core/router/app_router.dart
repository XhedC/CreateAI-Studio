import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/generation/presentation/screens/create_screen.dart';
import '../../features/generation/presentation/screens/generation_detail_screen.dart';
import '../../features/history/presentation/screens/history_screen.dart';
import '../../features/image_generation/presentation/screens/image_generator_screen.dart';
import '../../features/music_generation/presentation/screens/music_generator_screen.dart';
import '../../features/video_generation/presentation/screens/video_generator_screen.dart';
import '../../features/funnel_generation/presentation/screens/funnel_generator_screen.dart';
import '../../features/funnel_generation/presentation/screens/funnel_editor_screen.dart';
import '../../features/funnel_generation/presentation/screens/funnel_preview_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/projects/presentation/screens/project_detail_screen.dart';
import '../../features/projects/presentation/screens/projects_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../widgets/app_shell.dart';
import 'go_router_refresh_stream.dart';
import 'route_paths.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authStateStream = ref.watch(authRepositoryProvider).authStateChanges;

  return GoRouter(
    initialLocation: RoutePaths.splash,
    refreshListenable: GoRouterRefreshStream(authStateStream),
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final isLoading = authState.isLoading && !authState.hasValue;
      final isAuthenticated = authState.value != null;
      final location = state.matchedLocation;

      final isAuthRoute = location == RoutePaths.login ||
          location == RoutePaths.register ||
          location == RoutePaths.forgotPassword;

      if (isLoading) {
        return location == RoutePaths.splash ? null : RoutePaths.splash;
      }
      if (!isAuthenticated) {
        return isAuthRoute ? null : RoutePaths.login;
      }
      if (isAuthenticated && (isAuthRoute || location == RoutePaths.splash)) {
        return RoutePaths.home;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: RoutePaths.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: RoutePaths.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: RoutePaths.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: RoutePaths.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: RoutePaths.home,
              builder: (context, state) => const HomeScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: RoutePaths.create,
              builder: (context, state) => const CreateScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: RoutePaths.history,
              builder: (context, state) => const HistoryScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: RoutePaths.projects,
              builder: (context, state) => const ProjectsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: RoutePaths.profile,
              builder: (context, state) => const ProfileScreen(),
            ),
          ]),
        ],
      ),
      GoRoute(
        path: RoutePaths.createImage,
        builder: (context, state) => const ImageGeneratorScreen(),
      ),
      GoRoute(
        path: RoutePaths.createMusic,
        builder: (context, state) => const MusicGeneratorScreen(),
      ),
      GoRoute(
        path: RoutePaths.createVideo,
        builder: (context, state) => const VideoGeneratorScreen(),
      ),
      GoRoute(
        path: RoutePaths.createFunnel,
        builder: (context, state) => const FunnelGeneratorScreen(),
      ),
      GoRoute(
        path: '/funnels/:id/edit',
        builder: (context, state) => FunnelEditorScreen(
          funnelId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/funnels/:id/preview',
        builder: (context, state) => FunnelPreviewScreen(
          funnelId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/history/:id',
        builder: (context, state) => GenerationDetailScreen(
          generationId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/projects/:id',
        builder: (context, state) => ProjectDetailScreen(
          projectId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: RoutePaths.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: RoutePaths.notifications,
        builder: (context, state) => const NotificationsScreen(),
      ),
    ],
  );
});
