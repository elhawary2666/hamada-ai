// lib/features/chat/domain/models/chat_message_model.dart
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class ChatMessageModel {
  final String id;
  final String sessionId;
  final String role;
  final String content;
  final int    timestamp;
  final bool   isError;
  final double tokensPerSec;
  final bool   isBookmarked;

  const ChatMessageModel({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.timestamp,
    this.isError      = false,
    this.tokensPerSec = 0,
    this.isBookmarked = false,
  });

  bool get isUser      => role == 'user';
  bool get isAssistant => role == 'assistant';
  bool get isEmpty     => content.trim().isEmpty;

  factory ChatMessageModel.user({required String content, required String sessionId}) =>
      ChatMessageModel(
        id: _uuid.v4(), sessionId: sessionId, role: 'user',
        content: content, timestamp: DateTime.now().millisecondsSinceEpoch,
      );

  factory ChatMessageModel.assistant({
    required String content, required String sessionId,
    double tokensPerSec = 0, bool isError = false,
  }) => ChatMessageModel(
    id: _uuid.v4(), sessionId: sessionId, role: 'assistant',
    content: content, timestamp: DateTime.now().millisecondsSinceEpoch,
    tokensPerSec: tokensPerSec, isError: isError,
  );

  factory ChatMessageModel.fromMap(Map<String, dynamic> m) => ChatMessageModel(
    id:           m['id']            as String,
    sessionId:    m['session_id']    as String,
    role:         m['role']          as String,
    content:      m['content']       as String,
    timestamp:    m['timestamp']     as int,
    isBookmarked: (m['is_bookmarked'] as int? ?? 0) == 1,
  );

  Map<String, dynamic> toMap() => {
    'id': id, 'session_id': sessionId, 'role': role,
    'content': content, 'timestamp': timestamp,
    'is_bookmarked': isBookmarked ? 1 : 0, 'metadata': '{}',
  };

  ChatMessageModel copyWith({
    String? content, bool? isError,
    double? tokensPerSec, bool? isBookmarked,
  }) => ChatMessageModel(
    id: id, sessionId: sessionId, role: role, timestamp: timestamp,
    content:      content      ?? this.content,
    isError:      isError      ?? this.isError,
    tokensPerSec: tokensPerSec ?? this.tokensPerSec,
    isBookmarked: isBookmarked ?? this.isBookmarked,
  );
}
