// lib/features/chat/providers/chat_provider.dart
import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/di/providers.dart';
import '../../finance/providers/finance_provider.dart';
import '../../planner/presentation/planner_screen.dart';
import '../../notes/presentation/notes_screen.dart';
import '../../habits/presentation/habits_screen.dart';
import '../../../core/services/ai_service.dart';
import '../../../core/services/self_heal_service.dart';
import '../../../core/services/pattern_service.dart';
import '../data/chat_repository.dart';
import '../domain/models/chat_message_model.dart';

part 'chat_provider.g.dart';

const _kMaxContextMessages = 20;
const _kMaxContextTokens   = 6000;

enum ChatStatus { idle, thinking, streaming, error }

// ✅ IMPROVEMENT 2: Pending action awaiting user confirmation
class PendingAction {
  final String              action;
  final Map<String, dynamic> data;
  final String              preview; // human-readable description
  const PendingAction({required this.action, required this.data, required this.preview});
}

class ChatState {
  final List<ChatMessageModel> messages;
  final ChatStatus             status;
  final String                 streamingBuffer;
  final String?                errorMessage;
  final String                 sessionId;
  final double                 tokensPerSec;
  final bool                   isModelReady;
  final List<String>           suggestedReplies;
  final PendingAction?         pendingAction;
  final String?                conversationSummary;
  final UserMood               currentMood;
  final List<PatternInsight>   insights;

  const ChatState({
    this.messages              = const [],
    this.status                = ChatStatus.idle,
    this.streamingBuffer       = '',
    this.errorMessage,
    required this.sessionId,
    this.tokensPerSec          = 0,
    this.isModelReady          = false,
    this.suggestedReplies      = const [],
    this.pendingAction,
    this.conversationSummary,
    this.currentMood           = UserMood.neutral,
    this.insights              = const [],
  });

  bool get isGenerating =>
      status == ChatStatus.thinking || status == ChatStatus.streaming;

  ChatState copyWith({
    List<ChatMessageModel>? messages,
    ChatStatus?             status,
    String?                 streamingBuffer,
    String?                 errorMessage,
    bool                    clearError        = false,
    double?                 tokensPerSec,
    bool?                   isModelReady,
    List<String>?           suggestedReplies,
    PendingAction?          pendingAction,
    bool                    clearPending      = false,
    String?                 conversationSummary,
    UserMood?               currentMood,
    List<PatternInsight>?   insights,
  }) => ChatState(
    messages:            messages            ?? this.messages,
    status:              status              ?? this.status,
    streamingBuffer:     streamingBuffer     ?? this.streamingBuffer,
    errorMessage:        clearError ? null   : (errorMessage ?? this.errorMessage),
    sessionId:           sessionId,
    tokensPerSec:        tokensPerSec        ?? this.tokensPerSec,
    isModelReady:        isModelReady        ?? this.isModelReady,
    suggestedReplies:    suggestedReplies    ?? this.suggestedReplies,
    pendingAction:       clearPending ? null : (pendingAction ?? this.pendingAction),
    conversationSummary: conversationSummary ?? this.conversationSummary,
    currentMood:         currentMood         ?? this.currentMood,
    insights:            insights            ?? this.insights,
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
    final ready = ai.isReady || aiReadyNotifier.value;
    if (ready && !ai.isReady) await ai.initialize();
    state = state.copyWith(isModelReady: ai.isReady);
  }

  Future<void> refreshReadyState() async {
    final ai = ref.read(aiServiceProvider);
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
    // Run self-heal + pattern analysis in background
    Future.microtask(() async {
      try {
        final healer = ref.read(selfHealServiceProvider);
        await healer.runHealthCheck();
        final patterns = ref.read(patternServiceProvider);
        final insights = await patterns.analyzePatterns();
        if (insights.isNotEmpty) {
          state = state.copyWith(insights: insights);
        }
      } catch (_) {}
    });
  }

  // ✅ IMPROVEMENT 1: Context with summary of old messages
  List<Map<String, dynamic>> _buildContextHistory() {
    final msgs = state.messages
        .where((m) => !m.isEmpty && !m.isError)
        .toList();

    // Keep last 15 messages in full
    const kRecent = 15;
    final recent = msgs.length > kRecent ? msgs.sublist(msgs.length - kRecent) : msgs;
    final history = recent.map((m) => {'role': m.role, 'content': m.content}).toList();

    // Prepend summary of older messages if available
    if (state.conversationSummary != null && msgs.length > kRecent) {
      history.insert(0, {
        'role':    'system',
        'content': '[ملخص المحادثة السابقة]\n${state.conversationSummary}\n[نهاية الملخص]',
      });
    }
    return history;
  }

  // ✅ OPTIMIZED: Local summarization — no API call needed
  // Just takes the first 5 user messages as a brief context summary
  void _maybeSummarize() {
    final msgs = state.messages.where((m) => !m.isEmpty && !m.isError).toList();
    if (msgs.length < 25 || state.conversationSummary != null) return;
    // Build a simple local summary from first user messages (no API call)
    final oldUserMsgs = msgs
        .where((m) => m.role == 'user')
        .take(8)
        .map((m) => m.content.length > 80 ? m.content.substring(0, 80) : m.content)
        .toList();
    if (oldUserMsgs.isEmpty) return;
    final summary = 'محادثات سابقة تضمنت: ${oldUserMsgs.join(' | ')}';
    state = state.copyWith(conversationSummary: summary);
  }


  // ═══════════════════════════════════════════════════════
  // MATH INTERCEPTOR — solves arithmetic before AI sees it
  // Handles: اخصم/اطرح/زود/اضف/اضرب/اقسم + numbers
  // Returns null if no math found, or the enriched message
  // ═══════════════════════════════════════════════════════
  static final _numPattern = RegExp(r'[\d,\.]+');

  String? _tryResolveMath(String msg) {
    try {
      final normalized = msg
          .replaceAll('٠','0').replaceAll('١','1').replaceAll('٢','2')
          .replaceAll('٣','3').replaceAll('٤','4').replaceAll('٥','5')
          .replaceAll('٦','6').replaceAll('٧','7').replaceAll('٨','8')
          .replaceAll('٩','9').replaceAll(',', '');

      final nums = _numPattern.allMatches(normalized)
          .map((m) => double.tryParse(m.group(0) ?? ''))
          .where((n) => n != null)
          .cast<double>()
          .toList();

      if (nums.length < 2) return null;
      final a = nums[0];
      final b = nums[1];
      double? result;
      final lower = normalized;

      // ✅ FIX: "اخصم/اطرح X من Y" → Y - X  (reverse order when 'من' present)
      if (_hasAny(lower, ['اخصم','اطرح','طرح','ناقص'])) {
        result = lower.contains('من') ? b - a : a - b;
      }
      else if (_hasAny(lower, ['اضف','اجمع','زود','جمع','زيادة'])) {
        result = a + b;
      }
      // ✅ FIX: removed 'في' — too common as preposition in Arabic
      else if (_hasAny(lower, ['اضرب','ضرب'])) {
        result = a * b;
      }
      else if (_hasAny(lower, ['اقسم','قسمة','قسّم'])) {
        if (b == 0) return null;
        result = a / b;
      }
      else if (_hasAny(lower, ['بالمية','بالمئة','%'])) {
        result = (a * b) / 100;
      }

      if (result == null) return null;

      final formatted = (result == result.truncateToDouble())
          ? result.toInt().toString()
          : result.toStringAsFixed(2);

      return '$msg\n[نتيجة الحساب: $formatted]';
    } catch (_) {
      return null;
    }
  }

  bool _hasAny(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isGenerating) return;

    final ai   = ref.read(aiServiceProvider);
    final repo = ref.read(chatRepositoryProvider);

    if (!state.isModelReady && ai.isReady) {
      state = state.copyWith(isModelReady: true);
    }
    state = state.copyWith(suggestedReplies: []);

    // Mood detection
    final mood  = ai.detectMood(trimmed);
    state = state.copyWith(currentMood: mood);

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
      // ✅ MATH INTERCEPTOR: resolve arithmetic before sending to LLM
      final mathEnriched = _tryResolveMath(trimmed);
      final aiMessage = mathEnriched ?? trimmed;

      String buf = '';
      final response = await ai.chat(
        userMessage: aiMessage,
        sessionId:   state.sessionId,
        history:     history,
        onToken: (token) {
          buf += token;
          final displayText = buf.startsWith('{') ? '...جاري التنفيذ' : buf;
          final updated = List<ChatMessageModel>.from(state.messages);
          updated[updated.length - 1] = placeholder.copyWith(content: displayText);
          state = state.copyWith(
            messages:        updated,
            status:          ChatStatus.streaming,
            streamingBuffer: buf,
          );
        },
      );

      final displayText = _extractUserMessage(response.text);
      final finalMsg    = placeholder.copyWith(
          content: displayText, tokensPerSec: response.tokensPerSec);
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

      _maybeSummarize();
      _maybeShareInsight();
      _parseFunctionCallAndExecute(response.text, trimmed);

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

  void _generateSuggestions(String userMsg, String aiReply) {
    Future.microtask(() async {
      try {
        // ai already declared above
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

  Future<void> startNewSession() async {
    final sid = _uuid.v4();
    state = ChatState(sessionId: sid, isModelReady: state.isModelReady);
    _appendAssistant(_welcome);
  }

  Future<void> loadSession(String sid) async {
    final repo = ref.read(chatRepositoryProvider);
    final msgs = await repo.getSessionMessages(sid);
    state = ChatState(
        sessionId: sid, messages: msgs, isModelReady: state.isModelReady);
  }

  void dismissSuggestion(int index) {
    final list = List<String>.from(state.suggestedReplies);
    if (index < list.length) list.removeAt(index);
    state = state.copyWith(suggestedReplies: list);
  }

  void clearError() => state = state.copyWith(
      status: ChatStatus.idle, clearError: true);

  void cancelGeneration() {
    if (!state.isGenerating) return;
    final msgs = List<ChatMessageModel>.from(state.messages);
    if (msgs.isNotEmpty && msgs.last.isEmpty) msgs.removeLast();
    state = state.copyWith(
      messages:        msgs,
      status:          ChatStatus.idle,
      streamingBuffer: '',
      clearError:      true,
    );
  }

  // ── FUNCTION CALLING — Layer 1A: Retry Logic ──────────────

  // Keywords that indicate the user is asking for an action
  static const _commandKeywords = [
    'صرفت','دفعت','اشتريت','استلمت','مرتب','راتب','دخل','اكتب','سجل',
    'احفظ','ملاحظة','فكرة','مهمة','عندي','محتاج','فاكرني','موعد','اجتماع',
    'حجز','عادة','ابدأ','هعمل','ذكرني','ميزانية','حد أقصى','قسّم','الحساب',
    'صاحبي','فلان','بيحب','عنده',
    'دين','مديون','قرض','خليت','ادفعله','هيدفعلي','باقي','تقسيط',
  ];

  bool _looksLikeCommand(String msg) {
    final lower = msg.toLowerCase();
    return _commandKeywords.any((k) => lower.contains(k));
  }

  void _parseFunctionCallAndExecute(String aiResponse, String originalUserMsg) {
    Future.microtask(() async {
      try {
        var parsed = _tryParseActionJson(aiResponse);

        // Retry ONLY if message looks like a command
        if (parsed == null && _looksLikeCommand(originalUserMsg)) {
          parsed = await _retryFunctionCall(originalUserMsg, aiResponse);
        }
        if (parsed == null) return;

        final db  = ref.read(databaseHelperProvider);
        final now = DateTime.now().millisecondsSinceEpoch;

        // ✅ FIX A: support both single action AND actions array
        // e.g. {"actions":[{...},{...}],"message":"..."} for multiple transactions
        final actionsRaw = parsed['actions'];
        if (actionsRaw is List && actionsRaw.isNotEmpty) {
          // Multiple actions in one message
          for (final item in actionsRaw) {
            if (item is! Map<String, dynamic>) continue;
            final action = item['action'] as String?;
            final data   = item['data']   as Map<String, dynamic>?;
            if (action == null || data == null) continue;
            await _dispatchAction(action, data, db, _uuid.v4(), now);
          }
          return;
        }

        // Single action (original format)
        final action = parsed['action'] as String?;
        final data   = parsed['data']   as Map<String, dynamic>?;
        if (action == null || data == null) return;
        await _dispatchAction(action, data, db, _uuid.v4(), now);

      } catch (e) {
        // Show error in chat so user knows something went wrong
        _appendAssistant('⚠️ حصل خطأ في حفظ البيانات — جرّب تاني: $e');
      }
    });
  }

  Future<void> _dispatchAction(
    String action,
    Map<String, dynamic> data,
    dynamic db,
    String id,
    int now,
  ) async {
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
      case 'log_habit':
        await _executeLogHabit(db, data, id, now);
        break;
      case 'add_habit':
        await _executeAddHabit(db, data, id, now);
        break;
      case 'set_budget':
        await _executeSetBudget(db, data, id, now);
        break;
      case 'add_relationship_note':
        await _executeAddRelationshipNote(db, data, id, now);
        break;
      case 'split_bill':
        await _executeSplitBill(db, data, id, now);
        break;
      case 'add_debt':
        await _executeAddDebt(db, data, id, now);
        break;
    }
  }

  /// ✅ Layer 1A: retry with a strict JSON-only prompt
  Future<Map<String, dynamic>?> _retryFunctionCall(
      String userMsg, String badResponse) async {
    try {
      final ai = ref.read(aiServiceProvider);
      if (!ai.isReady) return null;

      final retryPrompt =
          'الرد السابق كان غلط. المستخدم قال: "$userMsg"\n'
          'الرد السابق كان: "$badResponse"\n'
          'لو في طلب تنفيذ (إضافة معاملة/مهمة/ملاحظة/موعد/عادة/ميزانية)، '
          'ارجع JSON فقط بالشكل ده:\n'
          '{"action":"...","data":{...},"message":"..."}\n'
          'لو مفيش طلب تنفيذ، ارجع: null';

      final result = await ai.singleShot(retryPrompt, maxTokens: 300);
      if (result.trim() == 'null' || result.trim().isEmpty) return null;
      return _tryParseActionJson(result);
    } catch (_) {
      return null;
    }
  }

  // ✅ UNIFIED PARSER: handles new {"reply":..., "action":..., "memories":[...]} format
  Map<String, dynamic>? _tryParseActionJson(String raw) {
    try {
      final clean = raw.replaceAll('```json', '').replaceAll('```', '');
      final start = clean.indexOf('{');
      if (start == -1) return null;
      final end = clean.lastIndexOf('}');
      if (end <= start) return null;

      final decoded = json.decode(clean.substring(start, end + 1));
      if (decoded is! Map<String, dynamic>) return null;

      // Accept if it has action, actions, OR reply (unified format)
      final hasAction  = decoded.containsKey('action')  && decoded.containsKey('data');
      final hasActions = decoded.containsKey('actions') && decoded['actions'] is List;
      final hasReply   = decoded.containsKey('reply');

      if (!hasAction && !hasActions && !hasReply) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }

  String _extractUserMessage(String raw) {
    final parsed = _tryParseActionJson(raw);
    if (parsed == null) return raw;
    // ✅ NEW: read from 'reply' field (unified format)
    final reply = parsed['reply'] as String?;
    if (reply != null && reply.trim().isNotEmpty) return reply.trim();
    // Fallback for old 'message' field
    final msg = parsed['message'] as String?;
    if (msg != null && msg.trim().isNotEmpty) return msg.trim();
    // Last resort: action-based default
    final action = parsed['action'] as String?;
    switch (action) {
      case 'add_transaction':       return 'تمام، سجلت المعاملة ✅';
      case 'add_task':              return 'حطيت المهمة في قايمتك ✅';
      case 'add_note':              return 'سجلت الملاحظة ✅';
      case 'add_appointment':       return 'حجزت الموعد ✅';
      case 'log_habit':             return 'سجلت العادة ✅';
      case 'add_habit':             return 'أضفت عادة جديدة ✅';
      case 'set_budget':            return 'ضبطت الميزانية ✅';
      case 'add_relationship_note': return 'حفظت الملاحظة ✅';
      case 'split_bill':            return 'قسّمت الحساب ✅';
      case 'add_debt':              return 'سجلت الدين ✅';
      default:                      return raw; // show raw if no structured format
    }
  }

  // ── EXECUTORS ─────────────────────────────────────────────

  static const _kConfirmThreshold = 500.0; // ج.م — منطقي أكتر للسوق المصري

  Future<void> _executeAddTransaction(
      dynamic db, Map<String, dynamic> data, String id, int now) async {
    final amount = _toDouble(data['amount'])?.abs();
    if (amount == null || amount <= 0) return;
    final rawType  = (data['type'] as String?)?.trim().toLowerCase() ?? 'expense';
    final category = (data['category'] as String?)?.trim() ?? 'أخرى';
    final desc     = (data['description'] as String?)?.trim() ?? '';

    String validType;
    if (rawType == 'income' || rawType == 'دخل' || rawType == 'مرتب' || rawType == 'راتب') {
      validType = 'income';
    } else {
      validType = 'expense';
    }

    // ✅ IMPROVEMENT 2: confirm before saving large transactions
    if (amount >= _kConfirmThreshold && validType == 'expense') {
      final typeAr = validType == 'income' ? 'دخل' : 'مصروف';
      final preview = '$typeAr ${amount.toStringAsFixed(0)} ج.م — $category'
          '${desc.isNotEmpty ? " ($desc)" : ""}';
      state = state.copyWith(
        pendingAction: PendingAction(
          action:  'add_transaction',
          data:    {'amount': amount, 'type': validType, 'category': category,
                    'description': desc, 'id': id, 'now': now},
          preview: preview,
        ),
      );
      return; // wait for user to confirm
    }

    await _saveTransaction(db, id, validType, amount, category, desc, now);
  }

  Future<void> _saveTransaction(dynamic db, String id, String type,
      double amount, String category, String desc, int now) async {
    await db.insert('finance_transactions', {
      'id': id, 'type': type, 'amount': amount, 'currency': 'EGP',
      'category': category, 'ai_category': category, 'description': desc,
      'date': now, 'is_recurring': 0, 'recurring_id': null,
      'payment_method': 'cash', 'created_at': now,
    });
    // Self-heal: verify write succeeded silently
    Future.microtask(() async {
      try {
        final healer = ref.read(selfHealServiceProvider);
        final ok = await healer.verifyTransactionWrite(id);
        if (!ok) _appendAssistant('⚠️ مش عارف أتأكد من الحفظ — افتح شاشة الحسابات للتأكد');
      } catch (_) {}
    });
    ref.invalidate(financeNotifierProvider);
  }

  /// ✅ IMPROVEMENT 2: User confirmed the pending action
  Future<void> confirmPendingAction() async {
    final pending = state.pendingAction;
    if (pending == null) return;
    state = state.copyWith(clearPending: true);

    final db   = ref.read(databaseHelperProvider);
    final data = pending.data;

    if (pending.action == 'add_transaction') {
      await _saveTransaction(
        db,
        data['id']          as String,
        data['type']        as String,
        (data['amount']     as num).toDouble(),
        data['category']    as String,
        data['description'] as String? ?? '',
        data['now']         as int,
      );
      // Show confirmation in chat
      _appendAssistant('تمام، سجلت ${pending.preview} ✅ والكلام ده بيني وبينك 🔒');
    }
  }

  /// ✅ IMPROVEMENT 2: User rejected the pending action
  void rejectPendingAction() {
    state = state.copyWith(clearPending: true);
    _appendAssistant('تمام، ما سجلتش حاجة 👍');
  }

  Future<void> _executeAddTask(
      dynamic db, Map<String, dynamic> data, String id, int now) async {
    final title = (data['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) return;
    final priority = _normalizePriority(data['priority'] as String?);
    final dueDate  = _parseDueDate(data['due_date'] as String?);
    await db.insert('tasks', {
      'id': id, 'title': title,
      'description': (data['description'] as String?)?.trim() ?? '',
      'due_date': dueDate, 'priority': priority,
      'status': 'pending', 'created_at': now,
    });
    // ✅ Layer 1B
    ref.invalidate(tasksNotifierProvider);
  }

  Future<void> _executeAddNote(
      dynamic db, Map<String, dynamic> data, String id, int now) async {
    final content = (data['content'] as String?)?.trim() ?? '';
    if (content.isEmpty) return;
    final title = (data['title'] as String?)?.trim() ?? '';
    await db.insert('user_notes', {
      'id': id, 'title': title.isEmpty ? null : title, 'content': content,
      'tags': '[]', 'color': 'default', 'is_pinned': 0,
      'created_at': now, 'updated_at': now,
    });
    // ✅ Layer 1B
    ref.invalidate(notesNotifierProvider);
  }

  Future<void> _executeAddAppointment(
      dynamic db, Map<String, dynamic> data, String id, int now) async {
    final title = (data['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) return;
    final startTimeStr = data['start_time'] as String?;
    int startTime = now;
    if (startTimeStr != null && startTimeStr.isNotEmpty) {
      try { startTime = DateTime.parse(startTimeStr).millisecondsSinceEpoch; } catch (_) {}
    }
    await db.insert('appointments', {
      'id': id, 'title': title,
      'description': (data['description'] as String?)?.trim() ?? '',
      'start_time': startTime, 'end_time': null,
      'location': (data['location'] as String?)?.trim() ?? '',
      'created_at': now,
    });
    // ✅ Layer 1B
    ref.invalidate(appointmentsProvider);
  }

  Future<void> _executeLogHabit(
      dynamic db, Map<String, dynamic> data, String id, int now) async {
    final name = (data['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return;
    // Find or create habit
    var habit = await db.getHabitByName(name);
    String habitId;
    if (habit == null) {
      habitId = _uuid.v4();
      await db.insert('habits', {
        'id': habitId, 'name': name, 'icon': data['icon'] as String? ?? '⭐',
        'frequency': 'daily', 'target_days': 7, 'created_at': now,
      });
    } else {
      habitId = habit['id'] as String;
    }
    final today = _dateStr(DateTime.now());
    await db.logHabit(habitId, today, id, now);
    ref.invalidate(habitsNotifierProvider);
  }

  Future<void> _executeAddHabit(
      dynamic db, Map<String, dynamic> data, String id, int now) async {
    final name = (data['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return;
    await db.insert('habits', {
      'id': id, 'name': name,
      'icon': data['icon'] as String? ?? '⭐',
      'frequency': data['frequency'] as String? ?? 'daily',
      'target_days': (data['target_days'] as num?)?.toInt() ?? 7,
      'created_at': now,
    });
    ref.invalidate(habitsNotifierProvider);
  }

  Future<void> _executeSetBudget(
      dynamic db, Map<String, dynamic> data, String id, int now) async {
    final category = (data['category'] as String?)?.trim() ?? '';
    final amount   = _toDouble(data['amount']);
    if (category.isEmpty || amount == null || amount <= 0) return;
    final d = DateTime.now();
    await db.setBudget(category, amount, d.year, d.month);
    ref.invalidate(financeNotifierProvider);
  }

  Future<void> _executeAddRelationshipNote(
      dynamic db, Map<String, dynamic> data, String id, int now) async {
    final name = (data['name'] as String?)?.trim() ?? '';
    final note = (data['note'] as String?)?.trim() ?? '';
    if (name.isEmpty || note.isEmpty) return;
    // Find or create relationship
    var rel = await db.getRelationshipByName(name);
    if (rel == null) {
      await db.insert('relationships', {
        'id': id, 'name': name,
        'relation': data['relation'] as String? ?? '',
        'notes': '[]', 'birthday': null, 'last_contact': now,
        'created_at': now,
      });
      await db.addNoteToRelationship(id, note);
    } else {
      await db.addNoteToRelationship(rel['id'] as String, note);
    }
  }

  Future<void> _executeAddDebt(
      dynamic db, Map<String, dynamic> data, String id, int now) async {
    final name      = (data['name']      as String?)?.trim() ?? '';
    final amount    = _toDouble(data['amount']);
    final direction = (data['direction'] as String?)?.trim() ?? 'owe';
    if (name.isEmpty || amount == null || amount <= 0) return;
    final validDir = (direction == 'owe' || direction == 'owed') ? direction : 'owe';
    await db.insert('debts', {
      'id':         id,
      'name':       name,
      'amount':     amount,
      'direction':  validDir,
      'notes':      (data['notes'] as String?)?.trim() ?? '',
      'due_date':   null,
      'is_paid':    0,
      'created_at': now,
    });
    ref.invalidate(financeNotifierProvider);
  }

  Future<void> _executeSplitBill(
      dynamic db, Map<String, dynamic> data, String id, int now) async {
    final title  = (data['title'] as String?)?.trim() ?? 'حساب';
    final total  = _toDouble(data['total']);
    if (total == null || total <= 0) return;
    final people = (data['people'] as List<dynamic>?)
        ?.map((p) => p.toString())
        .toList() ?? [];
    if (people.isEmpty) return;
    final perPerson = total / people.length;
    // ✅ FIX: use jsonEncode for safe serialization — handles names with quotes/backslashes
    final payersList = people.map((p) => {
      'name':   p,
      'amount': double.parse(perPerson.toStringAsFixed(2)),
      'paid':   false,
    }).toList();
    await db.insert('bill_splits', {
      'id': id, 'title': title, 'total_amount': total,
      'payers': json.encode(payersList), 'created_at': now,
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
    try { return DateTime.parse(dateStr).millisecondsSinceEpoch; } catch (_) { return null; }
  }

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  void _appendAssistant(String text) {
    final msg = ChatMessageModel.assistant(
        content: text, sessionId: state.sessionId);
    state = state.copyWith(messages: [...state.messages, msg]);
  }

    // Proactively show insights after AI response
  void _maybeShareInsight() {
    final insights = state.insights;
    if (insights.isEmpty) return;
    final msgCount = state.messages.where((m) => m.role == 'user').length;
    // Share insight: after 3rd message, then every 10 user messages
    final shouldShare = msgCount == 3 || (msgCount > 3 && msgCount % 10 == 0);
    if (!shouldShare) return;
    final insight = insights.first;
    Future.delayed(const Duration(milliseconds: 1200), () {
      _appendAssistant('💡 لاحظت حاجة: ${insight.message}');
      state = state.copyWith(insights: insights.skip(1).toList());
    });
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
