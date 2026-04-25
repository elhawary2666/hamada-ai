// lib/core/router/app_router.dart

import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/chat/presentation/chat_screen.dart';
import '../../features/finance/presentation/finance_screen.dart';
import '../../features/notes/presentation/notes_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/planner/presentation/planner_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../shell/main_shell.dart';

part 'app_router.g.dart';

abstract class AppRoutes {
  static const onboarding = '/onboarding';
  static const chat       = '/';
  static const notes      = '/notes';
  static const finance    = '/finance';
  static const planner    = '/planner';
  static const settings   = '/settings';
}

@riverpod
GoRouter appRouter(AppRouterRef ref) => GoRouter(
  initialLocation: AppRoutes.chat,
  redirect: (context, state) async {
    final prefs     = await SharedPreferences.getInstance();
    final onboarded = prefs.getBool('onboarding_complete') ?? false;
    if (!onboarded && state.matchedLocation != AppRoutes.onboarding) {
      return AppRoutes.onboarding;
    }
    return null;
  },
  routes: [
    GoRoute(
      path:    AppRoutes.onboarding,
      builder: (_, __) => const OnboardingScreen(),
    ),
    ShellRoute(
      builder: (ctx, state, child) => MainShell(child: child),
      routes: [
        GoRoute(path: AppRoutes.chat,     builder: (_, __) => const ChatScreen()),
        GoRoute(path: AppRoutes.notes,    builder: (_, __) => const NotesScreen()),
        GoRoute(path: AppRoutes.finance,  builder: (_, __) => const FinanceScreen()),
        GoRoute(path: AppRoutes.planner,  builder: (_, __) => const PlannerScreen()),
        GoRoute(path: AppRoutes.settings, builder: (_, __) => const SettingsScreen()),
      ],
    ),
  ],
);
