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
  yield* connectivity.onConnectivityChanged.map((results) {
    if (results.isEmpty) return ConnectivityStatus.unknown;
    final result = results.first;
    return result == ConnectivityResult.none
        ? ConnectivityStatus.offline
        : ConnectivityStatus.online;
  });
}

/// Banner widget shown at top of screen when offline
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Mixin to add offline-aware behavior
class ConnectivityBanner extends StatelessWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF85149),
      child: SafeArea(
        bottom: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 14, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                'مفيش إنترنت — حماده مش قادر يرد دلوقتي',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontFamily: 'Cairo',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
