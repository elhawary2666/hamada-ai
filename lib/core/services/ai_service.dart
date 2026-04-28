// lib/core/services/ai_service.dart
import 'package:flutter/foundation.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:logger/logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../constants/prompt_constants.dart';
import '../database/database_helper.dart';
import '../di/providers.dart';
import 'memory_service.dart';

part 'ai_service.g.dart';

final aiReadyNotifier = ValueNotifier<bool>(false);

const _groqUrl = 'https://api.groq.com/openai/v1/chat/completions';
const _model   = 'llama-3.3-70b-versatile';
const _kApiKey = 'groq_api_key';

class _RateLimiter {
  static const _minGapMs     = 500;
  static const _maxPerMinute = 25;
  final _timestamps = <int>[];
  int _lastMs = 0;

  bool canSend() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastMs < _minGapMs) return false;
    final cutoff = now - 60000;
    _timestamps.removeWhere((t) => t < cutoff);
    return _timestamps.length < _maxPerMinute;
  }

  void record() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastMs = now;
    _timestamps.add(now);
  }

  int get remainingThisMinute {
    final now    = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - 60000;
    _timestamps.removeWhere((t) => t < cutoff);
    return _maxPerMinute - _timestamps.length;
  }
}

enum AiInitState { notStarted, loading, ready, error }

class AiInitStatus {
  final AiInitState state;
  final double      progress;
  final String      message;
  final String?     errorMsg;
  const AiInitStatus({
    required this.state,
    this.progress = 1.0,
    this.message  = '',
    this.errorMsg,
  });
}

class HamadaResponse {
  final String text;
  final double tokensPerSec;
  final int    totalTokens;
  const HamadaResponse({
    required this.text,
    required this.tokensPerSec,
    required this.totalTokens,
  });
}

@riverpod
AiService aiService(AiServiceRef ref) {
  final svc = AiService(
    db:            ref.watch(databaseHelperProvider),
    memoryService: ref.watch(memoryServiceProvider),
  );
  return svc;
}

@riverpod
Stream<AiInitStatus> aiInitStatus(AiInitStatusRef ref) =>
    Stream.value(const AiInitStatus(
      state:    AiInitState.ready,
      progress: 1.0,
      message:  'حماده جاهز يخدمك 🔒',
    ));

class AiService {
  AiService({required this.db, required this.memoryService});

  final DatabaseHelper db;
  final MemoryService  memoryService;

  final _log = Logger(printer: PrettyPrinter(methodCount: 0));
  final _rl  = _RateLimiter();

  bool   _ready  = false;
  String _apiKey = '';

  bool   get isReady           => _ready;
  String get activeModelName   => 'Llama 3.3 70B';
  String get activeBackendName => 'Groq (مجاني)';
  int    get remainingRequests => _rl.remainingThisMinute;

  Future<void> initialize() async {
    try {
      final sqlDb = await db.database;
      await sqlDb.execute(
        'CREATE TABLE IF NOT EXISTS app_settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)'
      );
      final rows = await sqlDb.query(
        'app_settings', where: 'key = ?', whereArgs: [_kApiKey]
      );
      if (rows.isNotEmpty) {
        final k = (rows.first['value'] as String?)?.trim() ?? '';
        if (k.isNotEmpty) {
          _apiKey = k;
          _ready  = true;
          aiReadyNotifier.value = true;
          _log.i('API key loaded: ${k.length}chars');
        }
      }
    } catch (e) {
      _log.w('Init error: $e');
    }
  }

  Future<bool> hasApiKey() async {
    try {
      final sqlDb = await db.database;
      final rows  = await sqlDb.query(
        'app_settings', where: 'key = ?', whereArgs: [_kApiKey]
      );
      return rows.isNotEmpty &&
             ((rows.first['value'] as String?)?.trim().isNotEmpty ?? false);
    } catch (_) { return false; }
  }


  Future<bool> setApiKey(String key) async {
    if (key.isEmpty || !key.startsWith('gsk_') || key.length < 20) return false;
    try {
      final sqlDb = await db.database;
      await sqlDb.insert(
        'app_settings',
        {'key': _kApiKey, 'value': key},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      _apiKey = key;
      _ready  = true;
      aiReadyNotifier.value = true;
      _log.i('API key saved');
      return true;
    } catch (e) {
      _log.w('setApiKey error: $e');
      return false;
    }
  }

  Future<void> clearApiKey() async {
    try {
      final sqlDb = await db.database;
      await sqlDb.delete('app_settings', where: 'key = ?', whereArgs: [_kApiKey]);
    } catch (_) {}
    _apiKey = '';
    _ready  = false;
    aiReadyNotifier.value = false;
  }

  Future<HamadaResponse> chat({
    required String userMessage,
    required String sessionId,
    required List<Map<String, dynamic>> history,
    void Function(String token)? onToken,
  }) async {
    if (_apiKey.isEmpty || !_ready) await initialize();
    if (_apiKey.isEmpty || !_ready) {
      throw Exception('API key مش متضبط — روح الإعدادات وضيف الـ Key 🔑');
    }
    _checkRateLimit();

    // ✅ Layer 1C: improved memory retrieval via Groq re-ranking
    final memories = await _retrieveMemoriesWithGroq(userMessage);
    final notes    = await _getRecentNotes();
    final today    = await _getTodayContext();

    // ✅ Feature 8: Emergency mode check
    final isEmergency = await _isEmergencyMode();

    final systemPrompt = PromptConstants.buildPromptWithMemory(
      systemPrompt:     isEmergency
          ? PromptConstants.HAMADA_EMERGENCY_PROMPT
          : PromptConstants.HAMADA_SYSTEM_PROMPT,
      relevantMemories: memories.map((m) => m['content'] as String).toList(),
      recentNotes:      notes,
      todayContext:     today,
      userMessage:      userMessage,
    );

    final recent = history.length > 12
        ? history.sublist(history.length - 12)
        : history;

    final messages = [
      {'role': 'system',    'content': systemPrompt},
      ...recent.map((m) => {'role': m['role'], 'content': m['content']}),
      {'role': 'user',      'content': userMessage},
    ];

    final sw = Stopwatch()..start();
    try {
      _rl.record();
      final httpResponse = await http.post(
        Uri.parse(_groqUrl),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type':  'application/json',
        },
        body: jsonEncode({
          'model':       _model,
          'messages':    messages,
          'stream':      false,
          'max_tokens':  1024,
          'temperature': isEmergency ? 0.4 : 0.7,
          'top_p':       0.9,
        }),
      ).timeout(const Duration(seconds: 30));

      if (httpResponse.statusCode == 401) {
        throw Exception('API key غلط — روح الإعدادات وعدّله 🔑');
      }
      if (httpResponse.statusCode == 429) {
        throw Exception('وصلت للحد اليومي المجاني — جرّب بكرة 🌙');
      }
      if (httpResponse.statusCode != 200) {
        throw Exception('خطأ (${httpResponse.statusCode}) — جرّب تاني');
      }

      final data = jsonDecode(utf8.decode(httpResponse.bodyBytes));
      final text = (data['choices']?[0]?['message']?['content'] as String? ?? '').trim();
      final tok  = (data['usage']?['total_tokens'] as int?) ?? 0;

      if (text.isNotEmpty) onToken?.call(text);

      sw.stop();
      final tps = sw.elapsedMilliseconds > 0
          ? tok / (sw.elapsedMilliseconds / 1000)
          : 0.0;

      _extractMemoriesAsync(userMessage, text, sessionId: sessionId);
      return HamadaResponse(text: text, tokensPerSec: tps, totalTokens: tok);

    } on Exception catch (e) {
      _log.e('HTTP error', error: e);
      final msg = e.toString();
      if (msg.contains('TimeoutException') || msg.contains('timed out')) {
        throw Exception('انقطع النت أو الاتصال بطيء — جرّب تاني 📶');
      }
      if (msg.contains('🔑') || msg.contains('🌙') || msg.contains('خطأ (')) rethrow;
      throw Exception('مشكلة في الاتصال — تأكد من النت وجرّب تاني 📶');
    }
  }

  // ✅ Layer 1C: Memory re-ranking via Groq
  Future<List<Map<String, dynamic>>> _retrieveMemoriesWithGroq(String query) async {
    final ftsResults = await memoryService.retrieveRelevantMemories(query, topK: 15);
    if (ftsResults.isEmpty) return [];
    // ✅ FIX: always keep ftsResults as fallback — never return empty if FTS had results
    if (ftsResults.length <= 5 || !_ready) return ftsResults.take(5).toList();

    try {
      final memorySummary = ftsResults.asMap().entries
          .map((e) => '${e.key}: ${e.value['content']}')
          .join('\n');
      final prompt =
          'من الذكريات دي، اختار أرقام أكتر 5 ذكريات لها علاقة بالسؤال ده: "$query"\n'
          'الذكريات:\n$memorySummary\n'
          'ارجع الأرقام بس مفصولة بفاصلة مثال: 0,2,4,7,11';

      final result = await _singleShot(prompt, maxTokens: 30, temperature: 0.1);
      final indices = result
          .replaceAll(RegExp(r'[^\d,]'), '')
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .where((i) => i != null && i < ftsResults.length)
          .map((i) => i!)
          .toList();

      // ✅ FIX: if Groq returned nothing useful, fall back to FTS top-5
      if (indices.isEmpty) return ftsResults.take(5).toList();
      return indices.map((i) => ftsResults[i]).toList();
    } catch (_) {
      // ✅ FIX: on any error, return FTS results (never empty)
      return ftsResults.take(5).toList();
    }
  }

  // ✅ Feature 8: Emergency mode
  Future<bool> _isEmergencyMode() async {
    try {
      final now     = DateTime.now();
      final summary = await db.getMonthSummary(now.year, now.month);
      final balance = (summary['income'] ?? 0) - (summary['expense'] ?? 0);
      // threshold = 500 EGP default
      return balance < 500;
    } catch (_) { return false; }
  }

  Future<String> analyzeFinances({required int year, required int month}) async {
    if (!_ready) return 'مفيش API key — روح الإعدادات وضيف الـ Key عشان أحلل ماليتك 🔑';
    try {
      final summary = await db.getMonthSummary(year, month);
      final cats    = await db.getCategoryTotals(year, month);
      final goals   = await db.getFinancialGoals(activeOnly: false);
      final debt    = await db.getDebtSummary();

      final income  = summary['income']  ?? 0.0;
      final expense = summary['expense'] ?? 0.0;
      final net     = income - expense;

      // ✅ Feature 2: Budget warnings in analysis
      final budgets     = await db.getBudgets(year, month);
      final budgetLines = <String>[];
      for (final b in budgets) {
        final spent = cats[b['category']] ?? 0.0;
        final limit = b['limit_amount'] as double;
        final pct   = limit > 0 ? (spent / limit * 100) : 0.0;
        if (pct >= 80) {
          budgetLines.add(
              '⚠️ ميزانية ${b['category']}: ${pct.toStringAsFixed(0)}% '
              '(${spent.toStringAsFixed(0)} من ${limit.toStringAsFixed(0)} ج.م)');
        }
      }

      final catLines = cats.entries
          .take(8)
          .map((e) {
            final pct = income > 0 ? (e.value / income * 100).toStringAsFixed(1) : '0';
            return '• ${e.key}: ${e.value.toStringAsFixed(0)} ج.م ($pct% من الدخل)';
          })
          .join('\n');

      final goalsLines = goals.isEmpty
          ? 'لا توجد أهداف مالية'
          : goals.map((g) {
              final pct = (g['target_amount'] as num) > 0
                  ? ((g['current_amount'] as num) / (g['target_amount'] as num) * 100).toStringAsFixed(0)
                  : '0';
              return '• ${g['title']}: ${g['current_amount']} / ${g['target_amount']} ج.م ($pct%)';
            }).join('\n');

      final financeData =
          'الدخل: ${income.toStringAsFixed(0)} ج.م\n'
          'المصروف: ${expense.toStringAsFixed(0)} ج.م\n'
          'الصافي: ${net.toStringAsFixed(0)} ج.م\n'
          '${debt != null ? 'ديون: ${debt['owe']} ج.م مستحق عليك | ${debt['owed']} ج.م مستحق لك\n' : ''}'
          '${budgetLines.isEmpty ? '' : '\nتحذيرات الميزانية:\n${budgetLines.join('\n')}\n'}'
          '\nتوزيع المصروفات:\n$catLines';

      final prompt = PromptConstants.FINANCE_ANALYSIS_PROMPT
          .replaceAll('{finance_data}', financeData)
          .replaceAll('{goals_data}',   goalsLines);

      return await _singleShot(prompt, maxTokens: 600, temperature: 0.6);
    } catch (e) {
      return 'حصل خطأ في التحليل: $e';
    }
  }

  // ✅ IMPROVEMENT 1: Summarize old conversation messages for context compression
  Future<String> summarizeConversation(List<Map<String, dynamic>> messages) async {
    if (!_ready || messages.isEmpty) return '';
    try {
      final convo = messages
          .map((m) => '${m['role'] == 'user' ? 'المستخدم' : 'حماده'}: ${m['content']}')
          .join('\n');
      final prompt =
          'لخّص المحادثة دي في نقاط مهمة (بالعربي المصري، أقل من 10 سطور):\n\n$convo\n\n'
          'اذكر: المعلومات الشخصية، القرارات المهمة، المواضيع اللي اتناقشت. مفيش تحيات أو مقدمات.';
      return await _singleShot(prompt, maxTokens: 300, temperature: 0.3);
    } catch (_) { return ''; }
  }

  // ✅ Feature 3: Improved weekly report
  Future<String> generateWeeklyReport() async {
    if (!_ready) return 'مفيش API key';
    try {
      final now       = DateTime.now();
      final weekStart = now.subtract(const Duration(days: 7));
      final txs       = await db.getTransactionsByDateRange(
          weekStart.millisecondsSinceEpoch, now.millisecondsSinceEpoch);

      double income = 0, expense = 0;
      final catMap = <String, double>{};
      for (final t in txs) {
        final amount = (t['amount'] as num).toDouble();
        if (t['type'] == 'income') {
          income += amount;
        } else {
          expense += amount;
          final cat = t['category'] as String;
          catMap[cat] = (catMap[cat] ?? 0) + amount;
        }
      }

      final topCats = catMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topCatStr = topCats.take(3)
          .map((e) => '${e.key}: ${e.value.toStringAsFixed(0)} ج.م')
          .join(' | ');

      final weekData =
          'دخل الأسبوع: ${income.toStringAsFixed(0)} ج.م\n'
          'مصروف الأسبوع: ${expense.toStringAsFixed(0)} ج.م\n'
          'صافي: ${(income - expense).toStringAsFixed(0)} ج.م\n'
          'أكبر مصروفات: $topCatStr\n'
          'عدد المعاملات: ${txs.length}';

      final prompt =
          'أنت حماده. اكتب تقرير أسبوعي مالي ممتع بالعربي المصري.\n'
          'البيانات: $weekData\n'
          'اللهجة: دافية، واضحة، فيها نصيحة واحدة عملية.\n'
          'الطول: 4-5 جمل بحد أقصى.';

      return await _singleShot(prompt, maxTokens: 250, temperature: 0.7);
    } catch (e) {
      return 'مش قادر أعمل تقرير دلوقتي: $e';
    }
  }

  // ✅ Feature 5: Financial prediction
  Future<String> predictNextMonthFinance() async {
    if (!_ready) return '';
    try {
      final now = DateTime.now();
      final last3 = <Map<String, double>>[];
      for (int i = 1; i <= 3; i++) {
        final d = DateTime(now.year, now.month - i + 1);
        last3.add(await db.getMonthSummary(d.year, d.month));
      }

      final expenses = last3.map((m) => m['expense'] ?? 0.0).toList();
      final avg      = expenses.reduce((a, b) => a + b) / 3;
      final trend    = (expenses[0] - expenses[2]) / 2;
      final predicted = (avg + trend).clamp(0.0, double.infinity);

      final histStr = last3.asMap().entries
          .map((e) => 'شهر -${e.key + 1}: مصروف ${(e.value['expense'] ?? 0).toStringAsFixed(0)} ج.م')
          .join(', ');

      final prompt =
          'أنت حماده. بناءً على مصروفات الـ3 شهور الأخيرة: $histStr، '
          'التنبؤ للشهر الجاي: ${predicted.toStringAsFixed(0)} جنيه. '
          'علّق في جملتين بالعربي المصري.';

      return await _singleShot(prompt, maxTokens: 120, temperature: 0.7);
    } catch (_) { return ''; }
  }

  Future<String> getGoalComment({
    required String goalName,
    required double target,
    required double current,
    required int?   deadlineMs,
  }) async {
    if (!_ready) return '';
    try {
      final daysLeft = deadlineMs != null
          ? DateTime.fromMillisecondsSinceEpoch(deadlineMs)
              .difference(DateTime.now()).inDays
          : -1;
      final pct    = target > 0 ? (current / target * 100).toStringAsFixed(0) : '0';
      final prompt = PromptConstants.GOAL_PROGRESS_PROMPT
          .replaceAll('{goal_name}', goalName)
          .replaceAll('{target}',    target.toStringAsFixed(0))
          .replaceAll('{current}',   current.toStringAsFixed(0))
          .replaceAll('{percent}',   pct)
          .replaceAll('{days_left}', daysLeft >= 0 ? '$daysLeft' : 'غير محدد');
      return await _singleShot(prompt, maxTokens: 80, temperature: 0.8);
    } catch (_) { return ''; }
  }

  Future<String> getWidgetMessage() async {
    if (!_ready) return 'حماده في انتظارك';
    try {
      final hour   = DateTime.now().hour;
      final timeAr = hour < 12 ? 'الصبح' : (hour < 17 ? 'الضهر' : 'المسا');
      final task   = await db.getTopTodayTask();
      final sum    = await db.getMonthSummary(DateTime.now().year, DateTime.now().month);
      final bal    = ((sum['income'] ?? 0) - (sum['expense'] ?? 0)).toStringAsFixed(0);
      final prompt = PromptConstants.WIDGET_MESSAGE_PROMPT
          .replaceAll('{time_of_day}', timeAr)
          .replaceAll('{top_task}',    task?['title'] as String? ?? 'لا مهام')
          .replaceAll('{balance}',     bal);
      return await _singleShot(prompt, maxTokens: 30, temperature: 0.9);
    } catch (_) { return 'يلا نعمل يوم تمام!'; }
  }

  Future<String> classifyFinanceTransaction({
    required String description,
    required double amount,
  }) async {
    if (!_ready) return 'غير ذلك';
    try {
      final prompt = PromptConstants.FINANCE_CATEGORY_PROMPT
          .replaceAll('{description}', description)
          .replaceAll('{amount}',      amount.toStringAsFixed(2));
      return await _singleShot(prompt, maxTokens: 10, temperature: 0.1);
    } catch (_) { return 'غير ذلك'; }
  }

  Future<String> generateMorningGreeting({
    required List<String> todayTasks,
    required List<String> todayAppointments,
  }) async {
    if (!_ready) return '🌅 صباح الخير! يلا نعمل يوم تمام 💪';
    try {
      final prompt = PromptConstants.MORNING_GREETING_PROMPT
          .replaceAll('{tasks}',        todayTasks.join(' • '))
          .replaceAll('{appointments}', todayAppointments.join(' • '));
      return await _singleShot(prompt, maxTokens: 150);
    } catch (_) { return '🌅 صباح الخير! يلا نعمل يوم تمام 💪'; }
  }

  Future<String> generateEveningSummary({
    required List<String> pendingTasks,
  }) async {
    if (!_ready) return '🌙 مساء الخير! إيه أخبار يومك؟';
    try {
      final prompt = PromptConstants.EVENING_SUMMARY_PROMPT
          .replaceAll('{tasks}', pendingTasks.join(' • '));
      return await _singleShot(prompt, maxTokens: 150);
    } catch (_) { return '🌙 مساء الخير! إيه أخبار يومك؟'; }
  }

  Future<List<Map<String, dynamic>>> extractMemoriesFromConversation(
      String userMsg, String reply) async {
    if (!_ready) return [];
    try {
      final prompt = PromptConstants.MEMORY_EXTRACT_PROMPT
          .replaceAll('{conversation}', 'المستخدم: $userMsg\nحماده: $reply');
      final result = await _singleShot(prompt, maxTokens: 500, temperature: 0.1);
      return _parseJsonList(result).cast<Map<String, dynamic>>();
    } catch (_) { return []; }
  }

  Future<String> singleShot(String prompt,
      {int maxTokens = 200, double temperature = 0.7}) =>
      _singleShot(prompt, maxTokens: maxTokens, temperature: temperature);

  Future<String> _singleShot(String prompt, {
    int maxTokens = 200, double temperature = 0.3,
  }) async {
    _rl.record();
    final httpResponse = await http.post(
      Uri.parse(_groqUrl),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type':  'application/json',
      },
      body: jsonEncode({
        'model':       _model,
        'messages':    [{'role': 'user', 'content': prompt}],
        'max_tokens':  maxTokens,
        'temperature': temperature,
        'stream':      false,
      }),
    ).timeout(const Duration(seconds: 20));
    if (httpResponse.statusCode != 200) return '';
    final data = jsonDecode(utf8.decode(httpResponse.bodyBytes));
    return (data['choices']?[0]?['message']?['content'] as String?)?.trim() ?? '';
  }

  Future<List<String>> _getRecentNotes() async {
    try {
      final notes = await db.getAllNotes(limit: 5);
      return notes.map((n) {
        final c = n['content'] as String;
        return (n['title'] as String?) ?? c.substring(0, c.length.clamp(0, 60));
      }).toList();
    } catch (_) { return []; }
  }

  Future<String> _getTodayContext() async {
    try {
      final now   = DateTime.now();
      final parts = <String>[];

      // Balance — monthly + cumulative total
      try {
        final summary = await db.getMonthSummary(now.year, now.month);
        final income  = summary['income']  ?? 0.0;
        final expense = summary['expense'] ?? 0.0;
        final netMonth = income - expense;
        final sign    = netMonth >= 0 ? '+' : '';
        parts.add('رصيد الشهر الحالي: $sign${netMonth.toStringAsFixed(0)} ج.م'
            ' (دخل: ${income.toStringAsFixed(0)} | مصروف: ${expense.toStringAsFixed(0)})');

        // ✅ FIX C: also calculate all-time cumulative balance
        try {
          final sqlDb   = await db.database;
          final allRows = await sqlDb.rawQuery(
            "SELECT type, COALESCE(SUM(amount),0) as t FROM finance_transactions GROUP BY type"
          );
          double totalIncome = 0, totalExpense = 0;
          for (final r in allRows) {
            final t   = r['t'] as num? ?? 0;
            if (r['type'] == 'income')  totalIncome  = t.toDouble();
            if (r['type'] == 'expense') totalExpense = t.toDouble();
          }
          final cumBalance = totalIncome - totalExpense;
          final cumSign = cumBalance >= 0 ? '+' : '';
          parts.add('الرصيد الإجمالي (كل الوقت): $cumSign${cumBalance.toStringAsFixed(0)} ج.م');
        } catch (_) {}
      } catch (_) {}

      // ✅ Feature 2: Budget warnings in daily context
      try {
        final budgets  = await db.getBudgets(now.year, now.month);
        final catTotals = await db.getCategoryTotals(now.year, now.month);
        for (final b in budgets) {
          final spent = catTotals[b['category']] ?? 0.0;
          final limit = (b['limit_amount'] as num).toDouble();
          final pct   = limit > 0 ? (spent / limit * 100) : 0.0;
          if (pct >= 80) {
            parts.add('⚠️ ميزانية ${b['category']}: ${pct.toStringAsFixed(0)}%'
                ' (${spent.toStringAsFixed(0)} من ${limit.toStringAsFixed(0)} ج.م)');
          }
        }
      } catch (_) {}

      // Overdue tasks
      try {
        final overdue = await db.getOverdueTasks();
        if (overdue.isNotEmpty) {
          final titles = overdue.take(3).map((t) => t['title'] as String).join(' · ');
          parts.add('مهام متأخرة (${overdue.length}): $titles');
        }
      } catch (_) {}

      // Today tasks
      try {
        final tasks = await db.getTodayTasks();
        if (tasks.isNotEmpty) {
          final titles = tasks.take(3).map((t) => t['title'] as String).join(' · ');
          parts.add('مهام اليوم: $titles');
        }
      } catch (_) {}

      // Upcoming appointments
      try {
        final appts = await db.getUpcomingAppointments(withinDays: 2);
        if (appts.isNotEmpty) {
          final titles = appts.take(3).map((a) {
            final ts = a['start_time'] as int?;
            final timeStr = ts != null
                ? '${DateTime.fromMillisecondsSinceEpoch(ts).hour}:'
                  '${DateTime.fromMillisecondsSinceEpoch(ts).minute.toString().padLeft(2,'0')}'
                : '';
            return '${a['title']}${timeStr.isNotEmpty ? " ($timeStr)" : ""}';
          }).join(' · ');
          parts.add('مواعيد قريبة: $titles');
        }
      } catch (_) {}

      // ✅ Feature 4: Upcoming birthdays
      try {
        final upcoming = await db.getUpcomingBirthdays(withinDays: 3);
        if (upcoming.isNotEmpty) {
          final names = upcoming.map((r) {
            final days = r['days_until'] as int;
            return days == 0
                ? '${r['name']} (اليوم 🎂)'
                : '${r['name']} (بعد $days يوم)';
          }).join(', ');
          parts.add('🎂 أعياد ميلاد قريبة: $names');
        }
      } catch (_) {}

      return parts.isEmpty ? '' : parts.join('\n');
    } catch (_) { return ''; }
  }

  void _extractMemoriesAsync(String user, String reply, {required String sessionId}) {
    Future.microtask(() async {
      try {
        final extracted = await extractMemoriesFromConversation(user, reply);
        for (final m in extracted) {
          final content = (m['content'] as String?)?.trim() ?? '';
          if (content.isEmpty) continue;
          // ✅ IMPROVEMENT 3: update similar memory instead of duplicate
          await memoryService.updateOrSaveMemory(
            content:     content,
            type:        m['type']        as String? ?? 'note',
            importance:  (m['importance'] as num?)?.toInt() ?? 5,
            sourceMsgId: sessionId,
          );
        }
      } catch (_) {}
    });
  }

  List<dynamic> _parseJsonList(String raw) {
    try {
      final clean = raw.replaceAll('```json', '').replaceAll('```', '').trim();
      final s = clean.indexOf('[');
      final e = clean.lastIndexOf(']');
      if (s == -1 || e <= s) return [];
      final decoded = jsonDecode(clean.substring(s, e + 1));
      return decoded is List ? decoded : [];
    } catch (_) { return []; }
  }

  void _checkRateLimit() {
    if (!_rl.canSend()) {
      throw Exception('انت بتبعت رسايل بسرعة كبيرة — استنى ثانية 🐢');
    }
  }

  Future<void> dispose() async {}
}
