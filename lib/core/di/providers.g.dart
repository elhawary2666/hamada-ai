// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, unused_import

part of 'providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$databaseHelperHash() => r'databaseHelper_hash_v1';

final databaseHelperProvider = Provider<DatabaseHelper>(
  (ref) {
    ref.keepAlive(); // Never dispose — singleton database
    return databaseHelper(ref as DatabaseHelperRef);
  },
  name: r'databaseHelperProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$databaseHelperHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef DatabaseHelperRef = ProviderRef<DatabaseHelper>;
