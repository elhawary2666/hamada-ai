// lib/features/chat/data/chat_repository.dart
import '../../../core/database/database_helper.dart';
import '../domain/models/chat_message_model.dart';

class ChatRepository {
  ChatRepository({required this.db});
  final DatabaseHelper db;

  Future<void> saveMessage(ChatMessageModel msg) async =>
      db.insert('messages', msg.toMap());

  Future<List<ChatMessageModel>> getSessionMessages(
      String sessionId, {int limit = 60}) async {
    final rows = await db.getSessionMessages(sessionId, limit: limit);
    return rows.map(ChatMessageModel.fromMap).toList();
  }

  Future<List<Map<String, dynamic>>> getSessions() => db.getDistinctSessions();

  Future<void> deleteSession(String sessionId) async {
    final rawDb = await db.database;
    await rawDb.delete('messages', where: 'session_id = ?', whereArgs: [sessionId]);
  }
}
