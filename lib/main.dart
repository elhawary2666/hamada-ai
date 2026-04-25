// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'core/database/database_helper.dart';

import 'core/router/app_router.dart';
import 'core/services/ai_service.dart';
import 'core/services/background_service.dart';
import 'core/services/biometric_service.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/recurring_service.dart';
import 'core/services/widget_service.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/error_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Setup global error handlers FIRST
  setupErrorHandlers();

  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor:          Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  await DatabaseHelper.instance.database;

  await Workmanager().initialize(workmanagerCallback, isInDebugMode: false);
  await BackgroundService().registerAllTasks();

  runApp(const ProviderScope(child: HamadaApp()));
}

class HamadaApp extends ConsumerStatefulWidget {
  const HamadaApp({super.key});
  @override
  ConsumerState<HamadaApp> createState() => _HamadaAppState();
}

class _HamadaAppState extends ConsumerState<HamadaApp>
    with WidgetsBindingObserver {

  bool _locked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      ref.read(widgetServiceProvider).updateWidget().ignore();
      _checkLockOnResume();
    }
    if (state == AppLifecycleState.resumed && _locked) {
      _tryBiometric();
    }
  }

  Future<void> _startup() async {
    await ref.read(aiServiceProvider).initialize();
    ref.read(recurringServiceProvider).processDueTransactions().ignore();
    ref.read(widgetServiceProvider).updateWidget().ignore();
    await _checkBiometricLock();
  }

  Future<void> _checkBiometricLock() async {
    final bio = ref.read(biometricServiceProvider);
    if (await bio.isEnabled()) await _tryBiometric();
  }

  void _checkLockOnResume() async {
    final bio = ref.read(biometricServiceProvider);
    if (await bio.isEnabled()) setState(() => _locked = true);
  }

  Future<void> _tryBiometric() async {
    final bio = ref.read(biometricServiceProvider);
    final ok  = await bio.authenticate();
    if (ok) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    final router       = ref.watch(appRouterProvider);
    final connectivity = ref.watch(connectivityStatusProvider);

    if (_locked) return _LockScreen(onUnlock: _tryBiometric);

    return ErrorBoundary(
      child: MaterialApp.router(
        title:                      'حماده AI',
        debugShowCheckedModeBanner: false,
        theme:                      AppTheme.dark,
        routerConfig:               router,
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: Column(children: [
            // Offline banner
            connectivity.whenOrNull(
              data: (s) => s == ConnectivityStatus.offline
                  ? const ConnectivityBanner()
                  : null,
            ) ?? const SizedBox.shrink(),
            Expanded(child: child ?? const SizedBox.shrink()),
          ]),
        ),
      ),
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 80, height: 80,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFF4F8EF7), Color(0xFF1A4DB5)],
            ),
          ),
          child: const Center(
            child: Text('ح',
                style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold,
                    color: Colors.white, fontFamily: 'Cairo')),
          ),
        ),
        const SizedBox(height: 24),
        const Text('حماده AI',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                color: Color(0xFFCDD9E5), fontFamily: 'Cairo')),
        const SizedBox(height: 8),
        const Text('محتاج تأكيد هويتك عشان تدخل',
            style: TextStyle(fontSize: 13, color: Color(0xFF768390),
                fontFamily: 'Cairo')),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F8EF7),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14)),
          icon:  const Icon(Icons.fingerprint, color: Colors.white, size: 22),
          label: const Text('فتح التطبيق',
              style: TextStyle(color: Colors.white, fontFamily: 'Cairo',
                  fontSize: 15)),
          onPressed: onUnlock,
        ),
      ])),
    ),
  );
}
