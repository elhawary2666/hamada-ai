// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
part of 'chat_provider.dart';

String _$chatRepositoryHash() => r'chatRepository_hash_v1';
final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => chatRepository(ref as ChatRepositoryRef),
  name: r'chatRepositoryProvider',
  dependencies: null,
  allTransitiveDependencies: null,
);
typedef ChatRepositoryRef = ProviderRef<ChatRepository>;

String _$chatNotifierHash() => r'chatNotifier_hash_v1';
final chatNotifierProvider = NotifierProvider<ChatNotifier, ChatState>(
  ChatNotifier.new,
  name: r'chatNotifierProvider',
  dependencies: null,
  allTransitiveDependencies: null,
);
typedef _$ChatNotifier = Notifier<ChatState>;

String _$chatSessionsHash() => r'chatSessions_hash_v1';
final chatSessionsProvider = FutureProvider<List<Map<String, dynamic>>>(
  (ref) => chatSessions(ref as ChatSessionsRef),
  name: r'chatSessionsProvider',
  dependencies: null,
  allTransitiveDependencies: null,
);
typedef ChatSessionsRef = FutureProviderRef<List<Map<String, dynamic>>>;
