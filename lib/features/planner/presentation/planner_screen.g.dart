// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
part of 'planner_screen.dart';

String _$tasksNotifierHash() => r'tasksNotifier_hash_v1';

final tasksNotifierProvider = AsyncNotifierProvider<TasksNotifier,
    Map<String, List<Map<String, dynamic>>>>(
  TasksNotifier.new,
  name: r'tasksNotifierProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$tasksNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$TasksNotifier =
    AsyncNotifier<Map<String, List<Map<String, dynamic>>>>;

String _$appointmentsHash() => r'appointments_hash_v1';

final appointmentsProvider =
    FutureProvider<List<Map<String, dynamic>>>(
  (ref) => appointments(ref as AppointmentsRef),
  name: r'appointmentsProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$appointmentsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef AppointmentsRef = FutureProviderRef<List<Map<String, dynamic>>>;
