// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
part of 'ai_service.dart';

String _$aiServiceHash() => r'aiService_hash_v1';

final aiServiceProvider = Provider<AiService>(
  (ref) {
    final svc = aiService(ref as AiServiceRef);
    return svc;
  },
  name: r'aiServiceProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$aiServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef AiServiceRef = ProviderRef<AiService>;

String _$aiInitStatusHash() => r'aiInitStatus_hash_v1';

final aiInitStatusProvider = StreamProvider<AiInitStatus>(
  (ref) => aiInitStatus(ref as AiInitStatusRef),
  name: r'aiInitStatusProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$aiInitStatusHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef AiInitStatusRef = StreamProviderRef<AiInitStatus>;
