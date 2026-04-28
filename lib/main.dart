// lib/main.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
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

  // ✅ Init Arabic (and default) date locale for DateFormat('ar') calls
  await initializeDateFormatting('ar', null);
  await initializeDateFormatting('en', null);

  setupErrorHandlers();

  try {
    await SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  } catch (_) {}

  try {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor:          Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
  } catch (_) {}

  // Database — don't crash if fails
  try {
    await DatabaseHelper.instance.database;
  } catch (_) {}

  // Background tasks — non-critical
  try {
    await Workmanager().initialize(workmanagerCallback, isInDebugMode: false);
    await BackgroundService().registerAllTasks();
  } catch (_) {}

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
    try { await ref.read(aiServiceProvider).initialize(); } catch (_) {}
    try { ref.read(recurringServiceProvider).processDueTransactions().ignore(); } catch (_) {}
    try { ref.read(widgetServiceProvider).updateWidget().ignore(); } catch (_) {}
    try { await _checkBiometricLock(); } catch (_) {}
  }

  Future<void> _checkBiometricLock() async {
    final bio = ref.read(biometricServiceProvider);
    if (await bio.isEnabled()) await _tryBiometric();
  }

  void _checkLockOnResume() async {
    try {
      final bio = ref.read(biometricServiceProvider);
      if (await bio.isEnabled()) setState(() => _locked = true);
    } catch (_) {}
  }

  Future<void> _tryBiometric() async {
    try {
      final bio = ref.read(biometricServiceProvider);
      final ok  = await bio.authenticate();
      if (ok) setState(() => _locked = false);
    } catch (_) {
      setState(() => _locked = false);
    }
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
          textDirection: ui.TextDirection.rtl,
          child: Column(children: [
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
