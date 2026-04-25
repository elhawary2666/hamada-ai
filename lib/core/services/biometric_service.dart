// lib/core/services/biometric_service.dart
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'biometric_service.g.dart';

@riverpod
BiometricService biometricService(BiometricServiceRef ref) => BiometricService();

class BiometricService {
  final _auth = LocalAuthentication();
  static const _kEnabled = 'biometric_enabled';

  Future<bool> isAvailable() async {
    try {
      return await _auth.canCheckBiometrics && await _auth.isDeviceSupported();
    } catch (_) { return false; }
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabled) ?? false;
  }

  Future<void> setEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, v);
  }

  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'افتح حماده AI',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth:    true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }

  Future<List<BiometricType>> getAvailableBiometrics() async {
    try { return await _auth.getAvailableBiometrics(); }
    catch (_) { return []; }
  }

  String biometricName(List<BiometricType> types) {
    if (types.contains(BiometricType.face))        return 'Face ID';
    if (types.contains(BiometricType.fingerprint)) return 'بصمة الإصبع';
    return 'القفل البيومتري';
  }
}
