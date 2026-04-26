// lib/features/chat/providers/chat_provider.dart
import 'dart:async';
import 'dart:convert';


import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';


import '../../../core/di/providers.dart';
import '../../../core/services/ai_service.dart';
import '../data/chat_repository.dart';
import '../domain/models/chat_message_model.dart';

part 'chat_provider.g.dart';

// ── Context Window Management ─────────────────────────────────
const _kMaxContextMessages = 20;   // max messages sent to AI
const _kMaxContextTokens   = 6000; // rough token estimate guard

enum ChatStatus { idle, thinking, streaming, error }

class ChatState {
  final List<ChatMessageModel> messages;
  final ChatStatus             status;
  final String                 streamingBuffer;
  final String?                errorMessage;
  final String                 sessionId;
  final double                 tokensPerSec;
  final bool                   isModelReady;
  final List<String>           suggestedReplies;

  const ChatState({
    this.messages         = const [],
    this.status           = ChatStatus.idle,
    this.streamingBuffer  = '',
    this.errorMessage,
    required this.sessionId,
    this.tokensPerSec     = 0,
    this.isModelReady     = false,
    this.suggestedReplies = const [],
  });

  bool get isGenerating =>
      status == ChatStatus.thinking || status == ChatStatus.streaming;

  ChatState copyWith({
    List<ChatMessageModel>? messages,
    ChatStatus?             status,
    String?                 streamingBuffer,
    String?                 errorMessage,
    bool                    clearError = false,
    double?                 tokensPerSec,
    bool?                   isModelReady,
    List<String>?           suggestedReplies,
  }) => ChatState(
    messages:         messages         ?? this.messages,
    status:           status           ?? this.status,
    streamingBuffer:  streamingBuffer  ?? this.streamingBuffer,
    // ✅ FIX Bug #6: Only clear errorMessage when explicitly requested
    errorMessage:     clearError ? null : (errorMessage ?? this.errorMessage),
    sessionId:        sessionId,
    tokensPerSec:     tokensPerSec     ?? this.tokensPerSec,
    isModelReady:     isModelReady     ?? this.isModelReady,
    suggestedReplies: suggestedReplies ?? this.suggestedReplies,
  );
}

@riverpod
ChatRepository chatRepository(ChatRepositoryRef ref) =>
    ChatRepository(db: ref.watch(databaseHelperProvider));

@riverpod
class ChatNotifier extends _$ChatNotifier {
  final _uuid = const Uuid();

  @override
  ChatState build() {
    final sid = _uuid.v4();
    Future.microtask(() => _initSession(sid));
    return ChatState(sessionId: sid);
  }

  Future<void> initAiService() async {
    final ai = ref.read(aiServiceProvider);
    await ai.initialize();
    // Also check aiReadyNotifier in case key was set before this call
    final ready = ai.isReady || aiReadyNotifier.value;
    if (ready && !ai.isReady) await ai.initialize();
    state = state.copyWith(isModelReady: ai.isReady);
  }

  Future<void> refreshReadyState() async {
    final ai = ref.read(aiServiceProvider);
    // Re-initialize to reload key from DB in case it was saved after first init
    await ai.initialize();
    state = state.copyWith(isModelReady: ai.isReady);
  }

  Future<void> _initSession(String sid) async {
    final repo = ref.read(chatRepositoryProvider);
    final msgs = await repo.getSessionMessages(sid);
    if (msgs.isEmpty) {
      _appendAssistant(_welcome);
    } else {
      state = state.copyWith(messages: msgs);
    }
  }

  // ── CONTEXT WINDOW MANAGEMENT ─────────────────────────────

  List<Map<String, dynamic>> _buildContextHistory() {
    final msgs = state.messages
        .where((m) => !m.isEmpty && !m.isError)
        .toList();

    // Take last N messages
    final recent = msgs.length > _kMaxContextMessages
        ? msgs.sublist(msgs.length - _kMaxContextMessages)
        : msgs;

    // Rough token estimation (4 chars ≈ 1 token)
    var totalChars = 0;
    final trimmed  = <ChatMessageModel>[];
    for (final m in recent.reversed) {
      totalChars += m.content.length;
      if (totalChars > _kMaxContextTokens * 4) break;
      trimmed.insert(0, m);
    }

    return trimmed
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();
  }

  // ── SEND ──────────────────────────────────────────────────

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isGenerating) return;

    final ai   = ref.read(aiServiceProvider);
    final repo = ref.read(chatRepositoryProvider);

    // Refresh ready state in case key was saved after init
    if (!state.isModelReady && ai.isReady) {
      state = state.copyWith(isModelReady: true);
    }

    // Clear suggestions when user sends
    state = state.copyWith(suggestedReplies: []);

    final userMsg = ChatMessageModel.user(
        content: trimmed, sessionId: state.sessionId);
    await repo.saveMessage(userMsg);

    final placeholder = ChatMessageModel.assistant(
        content: '', sessionId: state.sessionId);

    state = state.copyWith(
      messages:        [...state.messages, userMsg, placeholder],
      status:          ChatStatus.thinking,
      streamingBuffer: '',
    );

    try {
      final history = _buildContextHistory();

      String buf = '';
      final response = await ai.chat(
        userMessage: trimmed,
        sessionId:   state.sessionId,
        history:     history,
        onToken: (token) {
          buf += token;
          final updated = List<ChatMessageModel>.from(state.messages);
          updated[updated.length - 1] = placeholder.copyWith(content: buf);
          state = state.copyWith(
            messages:        updated,
            status:          ChatStatus.streaming,
            streamingBuffer: buf,
          );
        },
      );

      final finalMsg = placeholder.copyWith(
          content: response.text, tokensPerSec: response.tokensPerSec);
      await repo.saveMessage(finalMsg);

      final finalMsgs = List<ChatMessageModel>.from(state.messages);
      finalMsgs[finalMsgs.length - 1] = finalMsg;

      state = state.copyWith(
        messages:        finalMsgs,
        status:          ChatStatus.idle,
        streamingBuffer: '',
        tokensPerSec:    response.tokensPerSec,
        clearError:      true,
      );

      // Generate suggested replies async
      _generateSuggestions(trimmed, response.text);
      // Parse and execute Function Calling from AI response
      _parseFunctionCallAndExecute(response.text);

    } catch (e) {
      final errMsg = placeholder.copyWith(
        content: e.toString().replaceAll('Exception: ', ''),
        isError: true,
      );
      final msgs = List<ChatMessageModel>.from(state.messages);
      msgs[msgs.length - 1] = errMsg;
      state = state.copyWith(
          messages: msgs, status: ChatStatus.error,
          errorMessage: e.toString());
    }
  }

  // ── SUGGESTED REPLIES ─────────────────────────────────────

  void _generateSuggestions(String userMsg, String aiReply) {
    Future.microtask(() async {
      try {
        final ai = ref.read(aiServiceProvider);
        if (!ai.isReady) return;

        final prompt =
            'بناءً على رد حماده ده:\n"${aiReply.substring(0, aiReply.length.clamp(0, 200))}"\n\n'
            'اقترح 3 ردود قصيرة يمكن يقولها المستخدم (كل رد في سطر، بدون نقاط أو أرقام، '
            'كل رد أقل من 6 كلمات بالعربي المصري فقط)';

        final result = await ai.singleShot(prompt, maxTokens: 60);
        final lines  = result
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty && l.length < 50)
            .take(3)
            .toList();

        if (lines.isNotEmpty) {
          state = state.copyWith(suggestedReplies: lines);
        }
      } catch (_) {}
    });
  }

  // ── SESSION ────────────────────────────────────────────────

  Future<void> startNewSession() async {
    final sid = _uuid.v4();
    state = ChatState(sessionId: sid, isModelReady: state.isModelReady);
    _appendAssistant(_welcome);
  }

  Future<void> loadSession(String sid) async {
    final repo = ref.read(chatRepositoryProvider);
    final msgs = await repo.getSessionMessages(sid);
    state = ChatState(
        sessionId: sid, messages: msgs,
        isModelReady: state.isModelReady);
  }

  void dismissSuggestion(int index) {
    final list = List<String>.from(state.suggestedReplies);
    if (index < list.length) list.removeAt(index);
    state = state.copyWith(suggestedReplies: list);
  }

  void clearError() => state = state.copyWith(
      status: ChatStatus.idle, clearError: true);

  // ✅ FIX Bug #2: Stop button — actually cancels the generating state
  void cancelGeneration() {
    if (!state.isGenerating) return;
    // Remove the empty placeholder bubble that was being filled
    final msgs = List<ChatMessageModel>.from(state.messages);
    if (msgs.isNotEmpty && msgs.last.isEmpty) {
      msgs.removeLast();
    }
    state = state.copyWith(
      messages:        msgs,
      status:          ChatStatus.idle,
      streamingBuffer: '',
      clearError:      true,
    );
  }

  // ── FUNCTION CALLING — JSON Parser & Executor ─────────────

  /// يـparse الـ JSON اللي بيرجعه حماده وينفذ الـ action على الـ DB
  void _parseFunctionCallAndExecute(String aiResponse) {
    Future.microtask(() async {
      try {
        final parsed = _tryParseActionJson(aiResponse);
        if (parsed == null) return; // مش function call — رد عادي

        final action = parsed['action'] as String?;
        final data   = parsed['data']   as Map<String, dynamic>?;
        if (action == null || data == null) return;

        final db  = ref.read(databaseHelperProvider);
        final now = DateTime.now().millisecondsSinceEpoch;
        final id  = _uuid.v4();  // ✅ UUID — no collision risk

        switch (action) {
          case 'add_transaction':
            await _executeAddTransaction(db, data, id, now);
            break;
          case 'add_task':
            await _executeAddTask(db, data, id, now);
            break;
          case 'add_note':
            await _executeAddNote(db, data, id, now);
            break;
          case 'add_appointment':
            await _executeAddAppointment(db, data, id, now);
            break;
        }
      } catch (_) {}
    });
  }

  /// يحاول يـparse الـ JSON — بيرجع null لو مش action
  Map<String, dynamic>? _tryParseActionJson(String raw) {
    try {
      // شيل أي whitespace في الأول أو الآخر
      final trimmed = raw.trim();

      // لازم يبدأ بـ { عشان يكون JSON
      if (!trimmed.startsWith('{')) return null;

      // شيل code fences لو موجودة
      final clean = trimmed
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      final s = clean.indexOf('{');
      final e = clean.lastIndexOf('}');
      if (s == -1 || e <= s) return null;

      final decoded = json.decode(clean.substring(s, e + 1));
      if (decoded is! Map<String, dynamic>) return null;
      if (!decoded.containsKey('action') || !decoded.containsKey('data')) return null;

      return decoded;
    } catch (_) {
      return null;
    }
  }

  Future<void> _executeAddTransaction(
    dynamic db, Map<String, dynamic> data, String id, int now,
  ) async {
    final amount = _toDouble(data['amount']);
    if (amount == null || amount <= 0) return;

    final type     = (data['type'] as String?)?.trim() ?? 'expense';
    final category = (data['category'] as String?)?.trim() ?? 'أخرى';
    final desc     = (data['description'] as String?)?.trim() ?? '';

    // Validate type
    final validType = (type == 'income' || type == 'expense') ? type : 'expense';

    await db.insert('finance_transactions', {
      'id':             id,
      'type':           validType,
      'amount':         amount,
      'currency':       'EGP',
      'category':       category,
      'ai_category':    category,
      'description':    desc,
      'date':           now,
      'is_recurring':   0,
      'recurring_id':   null,
      'payment_method': 'cash',
      'created_at':     now,
    });
  }

  Future<void> _executeAddTask(
    dynamic db, Map<String, dynamic> data, String id, int now,
  ) async {
    final title    = (data['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) return;

    final priority = _normalizePriority(data['priority'] as String?);
    final dueDate  = _parseDueDate(data['due_date'] as String?);

    await db.insert('tasks', {
      'id':          id,
      'title':       title,
      'description': (data['description'] as String?)?.trim() ?? '',
      'due_date':    dueDate,
      'priority':    priority,
      'status':      'pending',
      'created_at':  now,
    });
  }

  Future<void> _executeAddNote(
    dynamic db, Map<String, dynamic> data, String id, int now,
  ) async {
    final content = (data['content'] as String?)?.trim() ?? '';
    if (content.isEmpty) return;

    final title = (data['title'] as String?)?.trim() ?? '';

    await db.insert('user_notes', {
      'id':         id,
      'title':      title,
      'content':    content,
      'tags':       '[]',
      'color':      'default',
      'is_pinned':  0,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> _executeAddAppointment(
    dynamic db, Map<String, dynamic> data, String id, int now,
  ) async {
    final title = (data['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) return;

    final startTimeStr = data['start_time'] as String?;
    int startTime = now;
    if (startTimeStr != null && startTimeStr.isNotEmpty) {
      try {
        startTime = DateTime.parse(startTimeStr).millisecondsSinceEpoch;
      } catch (_) {}
    }

    await db.insert('appointments', {
      'id':          id,
      'title':       title,
      'description': (data['description'] as String?)?.trim() ?? '',
      'start_time':  startTime,
      'end_time':    null,
      'location':    (data['location'] as String?)?.trim() ?? '',
      'created_at':  now,
    });
  }

  // ── HELPERS ───────────────────────────────────────────────

  double? _toDouble(dynamic val) {
    if (val == null) return null;
    if (val is double) return val;
    if (val is int)    return val.toDouble();
    if (val is String) return double.tryParse(val);
    return null;
  }

  String _normalizePriority(String? p) {
    switch (p?.toLowerCase().trim()) {
      case 'high':   case 'عالي':  return 'high';
      case 'low':    case 'منخفض': return 'low';
      default:                     return 'medium';
    }
  }

  int? _parseDueDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    try {
      return DateTime.parse(dateStr).millisecondsSinceEpoch;
    } catch (_) { return null; }
  }

  void _appendAssistant(String text) {
    final msg = ChatMessageModel.assistant(
        content: text, sessionId: state.sessionId);
    state = state.copyWith(messages: [...state.messages, msg]);
  }

  static const _welcome =
      'أهلاً يسطا! 👋\n\n'
      'أنا حماده، مساعدك الشخصي. '
      'كل بياناتك وذاكرتك محفوظة على جهازك فقط — مش بتطلع برة. 🔒\n\n'
      'قولي إيه اللي في دماغك — شغل، فلوس، مهام، أو بس عايز تتكلم!';
}

@riverpod
Future<List<Map<String, dynamic>>> chatSessions(ChatSessionsRef ref) =>
    ref.watch(databaseHelperProvider).getDistinctSessions();
