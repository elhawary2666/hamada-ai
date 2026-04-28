// lib/core/services/memory_service.dart
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:logger/logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../di/providers.dart';

part 'memory_service.g.dart';

@riverpod
MemoryService memoryService(MemoryServiceRef ref) =>
    MemoryService(db: ref.watch(databaseHelperProvider));

class MemoryService {
  MemoryService({required this.db});

  final DatabaseHelper db;
  final _uuid = const Uuid();
  final _log  = Logger(printer: PrettyPrinter(methodCount: 0));

  static const int _topK        = 8;
  static const int _embeddingDim = 128;

  // ── SAVE ──────────────────────────────────────────────────

  Future<String> saveMemory({
    required String content,
    required String type,
    int importance = 5,
    String? sourceMsgId,
  }) async {
    if (content.trim().isEmpty) return '';
    final now   = DateTime.now().millisecondsSinceEpoch;
    final id    = _uuid.v4();
    final emb   = _textToSimpleEmbedding(content);
    final bytes = emb.buffer.asUint8List();

    await db.insert(Tables.memories, {
      'id':            id,
      'content':       content.trim(),
      'type':          _validateType(type),
      'importance':    importance.clamp(1, 10),
      'embedding':     bytes,
      'embedding_dim': _embeddingDim,
      'source_msg_id': sourceMsgId,
      'created_at':    now,
      'updated_at':    now,
      'last_accessed': now,
      'access_count':  0,
      'is_active':     1,
      'tags':          '[]',
    });

    _log.d('🧠 Memory saved [$type]: ${content.substring(0, math.min(50, content.length))}');
    return id;
  }

  /// ✅ IMPROVEMENT 3: Update existing similar memory instead of creating duplicate
  /// If a memory with high cosine similarity exists for same type → update it.
  /// Otherwise → create new memory.
  Future<String> updateOrSaveMemory({
    required String content,
    required String type,
    int importance = 5,
    String? sourceMsgId,
    double similarityThreshold = 0.82,
  }) async {
    if (content.trim().isEmpty) return '';

    try {
      // Search for similar existing memories of same type
      final existing = await db.getMemoriesByType(type, limit: 20);
      final queryVec = _textToSimpleEmbedding(content);

      for (final mem in existing) {
        final bytes = mem['embedding'] as Uint8List?;
        if (bytes == null || bytes.length < 4) continue;

        final aligned   = Uint8List(bytes.length)..setAll(0, bytes);
        final storedVec = aligned.buffer.asFloat32List();
        final sim       = _cosineSim(queryVec, storedVec);

        if (sim >= similarityThreshold) {
          // ✅ Found a very similar memory → update it with new content
          final now = DateTime.now().millisecondsSinceEpoch;
          final newEmb   = _textToSimpleEmbedding(content);
          final newBytes = newEmb.buffer.asUint8List();
          await db.update(Tables.memories, {
            'content':       content.trim(),
            'importance':    math.max(importance, (mem['importance'] as int? ?? 5)).clamp(1, 10),
            'embedding':     newBytes,
            'updated_at':    now,
            'last_accessed': now,
            'source_msg_id': sourceMsgId ?? mem['source_msg_id'],
          }, mem['id'] as String);
          _log.d('🧠 Memory updated [$type]: ${content.substring(0, math.min(50, content.length))}');
          return mem['id'] as String;
        }
      }
    } catch (_) {}

    // No similar memory found → create new
    return saveMemory(
      content:     content,
      type:        type,
      importance:  importance,
      sourceMsgId: sourceMsgId,
    );
  }

  // ── RETRIEVE ──────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> retrieveRelevantMemories(
    String query, {int topK = _topK}) async {
    if (query.trim().isEmpty) return [];

    final ftsResults = await db.searchMemoriesFts(query, limit: topK * 3);
    if (ftsResults.isEmpty) return db.getRecentMemories(limit: topK);

    final queryVec = _textToSimpleEmbedding(query);
    final scored   = <_Scored>[];

    for (final row in ftsResults) {
      final bytes = row['embedding'] as Uint8List?;
      double sim  = 0.5;
      if (bytes != null && bytes.length >= 4) {
        // FIX: safe Uint8→Float32 with alignment check
        final aligned = Uint8List(bytes.length)..setAll(0, bytes);
        final storedVec = aligned.buffer.asFloat32List();
        sim = _cosineSim(queryVec, storedVec);
      }
      final imp  = (row['importance'] as int? ?? 5) / 10.0;
      final score = sim * 0.7 + imp * 0.3;
      scored.add(_Scored(row: row, score: score));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    final top = scored.take(topK).map((s) => s.row).toList();
    for (final m in top) db.touchMemory(m['id'] as String).ignore();
    return top;
  }

  Future<List<Map<String, dynamic>>> searchMemories(String query) =>
      db.searchMemoriesFts(query, limit: 20);

  Future<void> softDelete(String id) => db.update(Tables.memories, {
    'is_active': 0, 'updated_at': DateTime.now().millisecondsSinceEpoch,
  }, id);

  Future<int> pruneOldMemories() async {
    final n = await db.pruneOldMemories();
    _log.i('🧹 Pruned $n memories');
    return n;
  }

  Future<String> buildContextBlock(String query) async {
    final mems = await retrieveRelevantMemories(query);
    if (mems.isEmpty) return '';
    final lines = mems.map((m) =>
        '${_emoji(m['type'] as String? ?? 'note')} ${m['content']}');
    return '[ذكريات عن صاحبك]\n${lines.join('\n')}\n[نهاية الذكريات]';
  }

  // ── EMBEDDING ─────────────────────────────────────────────

  Float32List _textToSimpleEmbedding(String text) {
    final vec  = Float32List(_embeddingDim);
    final norm = text.toLowerCase().trim();

    for (int i = 0; i < norm.length - 1; i++) {
      final hash = norm.substring(i, i + 2).hashCode.abs() % _embeddingDim;
      vec[hash] += 1.0;
    }
    for (final c in norm.runes) {
      if (c >= 0x0600 && c <= 0x06FF) vec[c % _embeddingDim] += 0.5;
    }

    double n = 0;
    for (final v in vec) n += v * v;
    n = math.sqrt(n);
    if (n == 0) return vec;
    final r = Float32List(_embeddingDim);
    for (int i = 0; i < vec.length; i++) r[i] = vec[i] / n;
    return r;
  }

  double _cosineSim(Float32List a, Float32List b) {
    final len = math.min(a.length, b.length);
    double dot = 0, na = 0, nb = 0;
    for (int i = 0; i < len; i++) {
      dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i];
    }
    final d = math.sqrt(na) * math.sqrt(nb);
    return d == 0 ? 0 : dot / d;
  }

  String _validateType(String t) {
    const valid = {'fact','preference','goal','event','finance','health','relationship','note'};
    return valid.contains(t) ? t : 'note';
  }

  String _emoji(String t) {
    switch (t) {
      case 'fact':         return '📌';
      case 'preference':   return '❤️';
      case 'goal':         return '🎯';
      case 'event':        return '📅';
      case 'finance':      return '💰';
      case 'health':       return '🏥';
      case 'relationship': return '👥';
      default:             return '📝';
    }
  }
}

class _Scored {
  final Map<String, dynamic> row;
  final double score;
  const _Scored({required this.row, required this.score});
}
