// lib/core/services/connectivity_service.dart
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'connectivity_service.g.dart';

enum ConnectivityStatus { online, offline, unknown }

@riverpod
Stream<ConnectivityStatus> connectivityStatus(ConnectivityStatusRef ref) async* {
  final connectivity = Connectivity();

  // ✅ FIX Bug #5: Emit initial state immediately — don't wait for first change
  try {
    final initial = await connectivity.checkConnectivity();
    yield _mapResults(initial);
  } catch (_) {
    yield ConnectivityStatus.unknown;
  }

  // Then stream subsequent changes
  yield* connectivity.onConnectivityChanged.map(_mapResults);
}

ConnectivityStatus _mapResults(List<ConnectivityResult> results) {
  if (results.isEmpty) return ConnectivityStatus.unknown;
  return results.first == ConnectivityResult.none
      ? ConnectivityStatus.offline
      : ConnectivityStatus.online;
}

/// Wrapper — kept for backward compat, just renders child
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Red banner shown at top of screen when device is offline
class ConnectivityBanner extends StatelessWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFF85149),
    child: SafeArea(
      bottom: false,
      child: Container(
        width:   double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, size: 14, color: Colors.white),
            SizedBox(width: 6),
            Text(
              'مفيش إنترنت — حماده مش قادر يرد دلوقتي',
              style: TextStyle(
                color:      Colors.white,
                fontSize:   12,
                fontFamily: 'Cairo',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
