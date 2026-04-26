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

// ✅ FIX Bug #3: Cache onboarding value — avoid SharedPreferences.getInstance()
// on every navigation event (was called for every tab switch)
bool? _onboardingComplete;

@riverpod
GoRouter appRouter(AppRouterRef ref) => GoRouter(
  initialLocation: AppRoutes.chat,
  redirect: (context, state) async {
    // Only read from disk once; after that use cached value
    _onboardingComplete ??=
        (await SharedPreferences.getInstance()).getBool('onboarding_complete') ?? false;

    if (!_onboardingComplete! && state.matchedLocation != AppRoutes.onboarding) {
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

/// Call this after onboarding completes so the cache stays in sync
void markOnboardingComplete() => _onboardingComplete = true;

/// Call this when resetting the app to force re-check of onboarding state
void resetOnboardingCache() => _onboardingComplete = null;

