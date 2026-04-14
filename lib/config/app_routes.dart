import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/splash_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/profile/profile_form_screen.dart';
import '../screens/welfare/welfare_list_screen.dart';
import '../screens/welfare/welfare_detail_screen.dart';

import '../screens/application/application_list_screen.dart';
import '../screens/application/application_detail_screen.dart';

GoRouter createRouter(BuildContext context) {
  final authProvider = Provider.of<AuthProvider>(context, listen: false);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final isLoggedIn = authProvider.isLoggedIn;
      final isAuthRoute =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/signup';
      final isSplash = state.matchedLocation == '/splash';

      if (isSplash) return null;
      if (!isLoggedIn && !isAuthRoute) return '/login';
      if (isLoggedIn && isAuthRoute) return '/home';
      return null;
    },
    refreshListenable: authProvider,
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/signup',
        builder: (_, __) => const SignupScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (_, __) => const HomeScreen(),
      ),
      GoRoute(
        path: '/profile/new',
        builder: (_, __) => const ProfileFormScreen(),
      ),
      GoRoute(
        path: '/profile/edit/:id',
        builder: (_, state) => ProfileFormScreen(
          profileId: state.pathParameters['id'],
        ),
      ),
      GoRoute(
        path: '/welfare',
        builder: (_, __) => const WelfareListScreen(),
      ),
      GoRoute(
        path: '/welfare/:id',
        builder: (_, state) => WelfareDetailScreen(
          serviceId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/application',
        builder: (_, __) => const ApplicationListScreen(),
      ),
      GoRoute(
        path: '/application/:id',
        builder: (_, state) => ApplicationDetailScreen(
          serviceId: state.pathParameters['id']!,
        ),
      ),
    ],
  );
}
