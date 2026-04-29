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

// ─── User mood enum ───────────────────────────────────────
enum UserMood { neutral, stressed, happy, sad, tired }

final aiReadyNotifier = ValueNotifier<bool>(false);

// ─── Gemini 2.0 Flash ─────────────────────────────────────────
const _geminiUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';
const _kApiKey   = 'gemini_api_key';

class _RateLimiter {
  static const _minGapMs     = 300;
  static const _maxPerMinute = 55; // Gemini free: 60/min
  final _timestamps = <int>[];
  int   _lastMs     = 0;

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
    final now = DateTime.now().millisecondsSinceEpoch;
    _timestamps.removeWhere((t) => t < now - 60000);
    return _maxPerMinute - _timestamps.length;
  }
}

enum AiInitState { notStarted, loading, ready, error }

class AiInitStatus {
  final AiInitState state;
  final double      progress;
  final String      message;
  final String?     errorMsg;
  const AiInitStatus({required this.state, this.progress = 1.0,
      this.message = '', this.errorMsg});
}

class HamadaResponse {
  final String text;
  final double tokensPerSec;
  final int    totalTokens;
  const HamadaResponse({required this.text,
      required this.tokensPerSec, required this.totalTokens});
}

@riverpod
AiService aiService(AiServiceRef ref) => AiService(
  db:            ref.watch(databaseHelperProvider),
  memoryService: ref.watch(memoryServiceProvider),
);

@riverpod
Stream<AiInitStatus> aiInitStatus(AiInitStatusRef ref) =>
    Stream.value(const AiInitStatus(
      state: AiInitState.ready, progress: 1.0,
      message: 'حماده جاهز يخدمك 🔒',
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
  String get activeModelName   => 'Gemini 2.0 Flash';
  String get activeBackendName => 'Google AI (مجاني)';
  int    get remainingRequests => _rl.remainingThisMinute;

  // ─── INIT ─────────────────────────────────────────────────

  Future<void> initialize() async {
    try {
      final sqlDb = await db.database;
      await sqlDb.execute(
        'CREATE TABLE IF NOT EXISTS app_settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)'
      );
      final rows = await sqlDb.query('app_settings',
          where: 'key = ?', whereArgs: [_kApiKey]);
      if (rows.isNotEmpty) {
        final k = (rows.first['value'] as String?)?.trim() ?? '';
        if (k.isNotEmpty) {
          _apiKey = k;
          _ready  = true;
          aiReadyNotifier.value = true;
          _log.i('Gemini key loaded: ${k.length} chars');
        }
      }
    } catch (e) { _log.w('Init error: $e'); }
  }

  Future<bool> hasApiKey() async {
    try {
      final sqlDb = await db.database;
      final rows  = await sqlDb.query('app_settings',
          where: 'key = ?', whereArgs: [_kApiKey]);
      return rows.isNotEmpty &&
          ((rows.first['value'] as String?)?.trim().isNotEmpty ?? false);
    } catch (_) { return false; }
  }

  Future<bool> setApiKey(String key) async {
    if (key.isEmpty || key.length < 20) return false;
    try {
      final sqlDb = await db.database;
      await sqlDb.insert('app_settings', {'key': _kApiKey, 'value': key},
          conflictAlgorithm: ConflictAlgorithm.replace);
      _apiKey = key;
      _ready  = true;
      aiReadyNotifier.value = true;
      return true;
    } catch (_) { return false; }
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

  // ─── PERSONALITY LEVEL ────────────────────────────────────
  // Based on total message count — personality evolves naturally

  Future<int> getPersonalityLevel() async {
    try {
      final count = await db.getTotalMessageCount();
      if (count < 50)   return 1; // رسمي نوعاً
      if (count < 150)  return 2; // عامية أكتر
      if (count < 400)  return 3; // صاحب قديم
      return 4;                   // يكمل جملك ويعرف أسلوبك
    } catch (_) { return 1; }
  }

  // ─── MOOD DETECTION ───────────────────────────────────────

  UserMood detectMood(String text) {
    final t = text.toLowerCase();
    final stressed = ['تعبت','ضغط','زهقت','مش قادر','صعب','مشكلة','خايف','قلقان','ضيقان'];
    final happy    = ['مبسوط','سعيد','تمام','عظيم','حلو','روعة','ممتاز','كويس'];
    final sad      = ['حزين','زعلان','مش كويس','وحيد','وحشني','فاتني'];
    final tired    = ['تعبان','نايم','عيان','مريض','خلصت','مرهق'];
    if (stressed.any((k) => t.contains(k))) return UserMood.stressed;
    if (sad.any((k)      => t.contains(k))) return UserMood.sad;
    if (tired.any((k)    => t.contains(k))) return UserMood.tired;
    if (happy.any((k)    => t.contains(k))) return UserMood.happy;
    return UserMood.neutral;
  }

  // ─── MAIN CHAT ────────────────────────────────────────────

  Future<HamadaResponse> chat({
    required String userMessage,
    required String sessionId,
    required List<Map<String, dynamic>> history,
    void Function(String token)? onToken,
  }) async {
    if (_apiKey.isEmpty || !_ready) await initialize();
    if (_apiKey.isEmpty || !_ready) {
      throw Exception('محتاج Gemini API key — روح الإعدادات 🔑');
    }
    _checkRateLimit();

    final memories   = await _retrieveMemories(userMessage);
    final notes      = await _getRecentNotes();
    final today      = await _getTodayContext();
    final isEmergency = await _isEmergencyMode();
    final level      = await getPersonalityLevel();
    final mood       = detectMood(userMessage);

    final systemPrompt = PromptConstants.buildPromptWithMemory(
      systemPrompt:     isEmergency
          ? PromptConstants.HAMADA_EMERGENCY_PROMPT
          : PromptConstants.buildPersonalityPrompt(level),
      relevantMemories: memories.map((m) => m['content'] as String).toList(),
      recentNotes:      notes,
      todayContext:     today,
      userMessage:      userMessage,
      mood:             mood,
    );

    // Build Gemini-format contents array
    final contents = <Map<String,dynamic>>[];
    for (final h in history.take(16)) {
      contents.add({
        'role':  h['role'] == 'user' ? 'user' : 'model',
        'parts': [{'text': h['content'] as String}],
      });
    }
    contents.add({'role': 'user', 'parts': [{'text': userMessage}]});

    final sw = Stopwatch()..start();
    try {
      _rl.record();
      final httpResponse = await http.post(
        Uri.parse('$_geminiUrl?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'system_instruction': {'parts': [{'text': systemPrompt}]},
          'contents': contents,
          'generationConfig': {
            'maxOutputTokens':  1200,
            'temperature':      isEmergency ? 0.4 : _tempForMood(mood),
            'topP':             0.9,
            'responseMimeType': 'application/json',
          },
        }),
      ).timeout(const Duration(seconds: 30));

      _handleHttpError(httpResponse.statusCode);

      final data  = jsonDecode(utf8.decode(httpResponse.bodyBytes));
      final raw   = (data['candidates']?[0]?['content']?['parts']?[0]?['text']
          as String? ?? '').trim();
      final usage = data['usageMetadata'];
      final tok   = ((usage?['totalTokenCount'] as int?) ?? 0);

      if (raw.isNotEmpty) onToken?.call(raw);
      sw.stop();
      final tps = sw.elapsedMilliseconds > 0 ? tok / (sw.elapsedMilliseconds / 1000) : 0.0;

      _saveMemoriesFromResponse(raw, sessionId: sessionId);
      return HamadaResponse(text: raw, tokensPerSec: tps, totalTokens: tok);

    } on Exception catch (e) {
      final msg = e.toString();
      if (msg.contains('TimeoutException') || msg.contains('timed out')) {
        throw Exception('الاتصال بطيء — جرّب تاني 📶');
      }
      if (msg.contains('🔑') || msg.contains('حد يومي') || msg.contains('خطأ (')) rethrow;
      throw Exception('مشكلة في الاتصال — تأكد من النت 📶');
    }
  }

  double _tempForMood(UserMood mood) {
    switch (mood) {
      case UserMood.stressed: return 0.5; // أكتر تركيز لما المستخدم في ضغط
      case UserMood.sad:      return 0.5;
      case UserMood.happy:    return 0.9; // أكتر إبداع لما مبسوط
      default:                return 0.7;
    }
  }

  void _handleHttpError(int code) {
    switch (code) {
      case 400: throw Exception('طلب غلط — تأكد من الـ key وجرّب تاني');
      case 403: throw Exception('API key غلط أو انتهت صلاحيته — روح الإعدادات 🔑');
      case 429: throw Exception('وصلت للحد اليومي المجاني — جرّب بكرة 🌙');
      case 200: return;
      default:  throw Exception('خطأ ($code) — جرّب تاني');
    }
  }

  // ─── MEMORIES ─────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _retrieveMemories(String query) =>
      memoryService.retrieveRelevantMemories(query, topK: 5);

  void _saveMemoriesFromResponse(String raw, {required String sessionId}) {
    Future.microtask(() async {
      try {
        final parsed   = parseUnifiedResponse(raw);
        final memories = parsed['memories'];
        if (memories is! List || memories.isEmpty) return;
        for (final m in memories) {
          if (m is! Map<String, dynamic>) continue;
          final content = (m['content'] as String?)?.trim() ?? '';
          if (content.isEmpty) continue;
          await memoryService.updateOrSaveMemory(
            content:     content,
            type:        (m['type'] as String?)?.trim() ?? 'note',
            importance:  (m['importance'] as num?)?.toInt() ?? 5,
            sourceMsgId: sessionId,
          );
        }
      } catch (_) {}
    });
  }

  static Map<String, dynamic> parseUnifiedResponse(String raw) {
    try {
      final clean = raw.replaceAll('```json', '').replaceAll('```', '').trim();
      final s = clean.indexOf('{');
      final e = clean.lastIndexOf('}');
      if (s == -1 || e <= s) return {'reply': raw};
      final decoded = jsonDecode(clean.substring(s, e + 1));
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return {'reply': raw};
  }

  // ─── EMERGENCY MODE ───────────────────────────────────────

  Future<bool> _isEmergencyMode() async {
    try {
      final sqlDb   = await db.database;
      final allRows = await sqlDb.rawQuery(
        "SELECT type, COALESCE(SUM(amount),0) as t FROM finance_transactions GROUP BY type"
      );
      double income = 0, expense = 0;
      for (final r in allRows) {
        final t = (r['t'] as num?)?.toDouble() ?? 0;
        if (r['type'] == 'income')  income  = t;
        if (r['type'] == 'expense') expense = t;
      }
      return income > 0 && (income - expense) < 500;
    } catch (_) { return false; }
  }

  // ─── CONTEXT ──────────────────────────────────────────────

  Future<String> _getTodayContext() async {
    try {
      final now   = DateTime.now();
      final parts = <String>[];

      // Cumulative + monthly balance
      try {
        final sqlDb   = await db.database;
        final allRows = await sqlDb.rawQuery(
          "SELECT type, COALESCE(SUM(amount),0) as t FROM finance_transactions GROUP BY type"
        );
        double totalIn = 0, totalOut = 0;
        for (final r in allRows) {
          final t = (r['t'] as num?)?.toDouble() ?? 0;
          if (r['type'] == 'income')  totalIn  = t;
          if (r['type'] == 'expense') totalOut = t;
        }
        final cumBal = totalIn - totalOut;
        parts.add('الرصيد الإجمالي: ${cumBal >= 0 ? '+' : ''}${cumBal.toStringAsFixed(0)} ج.م');

        final monthly = await db.getMonthSummary(now.year, now.month);
        final mIn     = monthly['income']  ?? 0.0;
        final mOut    = monthly['expense'] ?? 0.0;
        parts.add('رصيد ${now.month}/${now.year}: ${(mIn-mOut).toStringAsFixed(0)} ج.م (دخل: ${mIn.toStringAsFixed(0)} | مصروف: ${mOut.toStringAsFixed(0)})');
      } catch (_) {}

      // Budget warnings
      try {
        final budgets   = await db.getBudgets(now.year, now.month);
        final catTotals = await db.getCategoryTotals(now.year, now.month);
        for (final b in budgets) {
          final spent = catTotals[b['category']] ?? 0.0;
          final limit = (b['limit_amount'] as num).toDouble();
          if (limit > 0 && (spent / limit) >= 0.8) {
            parts.add('⚠️ ميزانية ${b['category']}: ${(spent/limit*100).toStringAsFixed(0)}%');
          }
        }
      } catch (_) {}

      // Overdue tasks
      try {
        final overdue = await db.getOverdueTasks();
        if (overdue.isNotEmpty) {
          parts.add('مهام متأخرة (${overdue.length}): ${overdue.take(2).map((t) => t['title']).join(' · ')}');
        }
      } catch (_) {}

      // Today tasks
      try {
        final tasks = await db.getTodayTasks();
        if (tasks.isNotEmpty) {
          parts.add('مهام اليوم: ${tasks.take(3).map((t) => t['title']).join(' · ')}');
        }
      } catch (_) {}

      // Upcoming appointments
      try {
        final appts = await db.getUpcomingAppointments(withinDays: 2);
        if (appts.isNotEmpty) {
          parts.add('مواعيد قريبة: ${appts.take(2).map((a) => a['title']).join(' · ')}');
        }
      } catch (_) {}

      // Birthdays
      try {
        final bdays = await db.getUpcomingBirthdays(withinDays: 3);
        if (bdays.isNotEmpty) {
          final names = bdays.map((r) => r['days_until'] == 0
              ? '${r['name']} 🎂 اليوم!'
              : '${r['name']} (${r['days_until']} يوم)').join(', ');
          parts.add('أعياد ميلاد: $names');
        }
      } catch (_) {}

      return parts.isEmpty ? '' : parts.join('\n');
    } catch (_) { return ''; }
  }

  // ─── SINGLE SHOT (for reports etc.) ──────────────────────

  Future<String> singleShot(String prompt, {int maxTokens = 200, double temperature = 0.7}) =>
      _singleShot(prompt, maxTokens: maxTokens, temperature: temperature);

  Future<String> _singleShot(String prompt, {int maxTokens = 200, double temperature = 0.4}) async {
    if (!_ready) return '';
    if (!_rl.canSend()) { await Future.delayed(const Duration(milliseconds: 400)); }
    _rl.record();
    try {
      final httpResponse = await http.post(
        Uri.parse('$_geminiUrl?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{'role': 'user', 'parts': [{'text': prompt}]}],
          'generationConfig': {
            'maxOutputTokens': maxTokens,
            'temperature':     temperature,
          },
        }),
      ).timeout(const Duration(seconds: 20));
      if (httpResponse.statusCode != 200) return '';
      final data = jsonDecode(utf8.decode(httpResponse.bodyBytes));
      final raw  = (data['candidates']?[0]?['content']?['parts']?[0]?['text']
          as String?)?.trim() ?? '';
      final parsed = parseUnifiedResponse(raw);
      final reply  = parsed['reply'] as String?;
      return (reply != null && reply.isNotEmpty) ? reply : raw;
    } catch (_) { return ''; }
  }

  // ─── ANALYSIS METHODS ─────────────────────────────────────

  Future<String> analyzeFinances({required int year, required int month}) async {
    if (!_ready) return 'محتاج API key';
    try {
      final summary = await db.getMonthSummary(year, month);
      final cats    = await db.getCategoryTotals(year, month);
      final goals   = await db.getFinancialGoals();
      final budgets = await db.getBudgets(year, month);
      final income  = summary['income']  ?? 0.0;
      final expense = summary['expense'] ?? 0.0;

      final budgetWarnings = <String>[];
      for (final b in budgets) {
        final spent = cats[b['category']] ?? 0.0;
        final limit = (b['limit_amount'] as num).toDouble();
        final pct   = limit > 0 ? (spent / limit * 100) : 0.0;
        if (pct >= 80) budgetWarnings.add('⚠️ ${b['category']}: ${pct.toStringAsFixed(0)}%');
      }

      final financeData =
          'دخل: ${income.toStringAsFixed(0)} ج.م\n'
          'مصروف: ${expense.toStringAsFixed(0)} ج.م\n'
          'صافي: ${(income - expense).toStringAsFixed(0)} ج.م\n'
          '${budgetWarnings.isEmpty ? '' : 'تحذيرات: ${budgetWarnings.join(' | ')}\n'}'
          'أعلى فئات: ${cats.entries.take(5).map((e) => '${e.key}: ${e.value.toStringAsFixed(0)}').join(' | ')}';

      final goalsStr = goals.isEmpty ? 'لا توجد أهداف' :
          goals.take(3).map((g) => '${g['title']}: ${g['current_amount']}/${g['target_amount']}').join(' | ');

      final prompt = PromptConstants.FINANCE_ANALYSIS_PROMPT
          .replaceAll('{finance_data}', financeData)
          .replaceAll('{goals_data}',   goalsStr);

      return await _singleShot(prompt, maxTokens: 600, temperature: 0.6);
    } catch (e) { return 'خطأ في التحليل: $e'; }
  }

  Future<String> generateWeeklyReport() async {
    if (!_ready) return '';
    try {
      final now       = DateTime.now();
      final weekStart = now.subtract(const Duration(days: 7));
      final txs       = await db.getTransactionsByDateRange(
          weekStart.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
      double income = 0, expense = 0;
      final cats = <String, double>{};
      for (final t in txs) {
        final amount = (t['amount'] as num).toDouble();
        if (t['type'] == 'income') { income += amount; }
        else { expense += amount; cats[t['category'] as String] = (cats[t['category'] as String] ?? 0) + amount; }
      }
      final topCats = (cats.entries.toList()..sort((a,b) => b.value.compareTo(a.value)))
          .take(3).map((e) => '${e.key}: ${e.value.toStringAsFixed(0)}').join(' | ');
      final prompt = 'أنت حماده. اكتب تقرير أسبوعي مالي بالعربي المصري (4-5 جمل).\n'
          'دخل: ${income.toStringAsFixed(0)} | مصروف: ${expense.toStringAsFixed(0)} | أعلى مصروفات: $topCats\n'
          'رد بـ JSON: {"reply":"..."}';
      return await _singleShot(prompt, maxTokens: 250, temperature: 0.7);
    } catch (_) { return ''; }
  }

  Future<String> predictNextMonthFinance() async {
    if (!_ready) return '';
    try {
      final now    = DateTime.now();
      final months = <Map<String,double>>[];
      for (int i = 1; i <= 3; i++) {
        final d = DateTime(now.year, now.month - i + 1);
        months.add(await db.getMonthSummary(d.year, d.month));
      }
      final expenses  = months.map((m) => m['expense'] ?? 0.0).toList();
      final avg       = expenses.reduce((a,b) => a+b) / 3;
      final trend     = (expenses[0] - expenses[2]) / 2;
      final predicted = (avg + trend).clamp(0.0, double.infinity);
      final hist      = months.asMap().entries.map((e) =>
          'شهر -${e.key+1}: ${(e.value['expense']??0).toStringAsFixed(0)} ج.م').join(', ');
      final prompt = 'أنت حماده. بناءً على: $hist، التنبؤ: ${predicted.toStringAsFixed(0)} ج.م. علّق في جملتين.\n'
          'رد بـ JSON: {"reply":"..."}';
      return await _singleShot(prompt, maxTokens: 120, temperature: 0.7);
    } catch (_) { return ''; }
  }

  Future<String> summarizeConversation(List<Map<String,dynamic>> messages) async {
    if (!_ready || messages.isEmpty) return '';
    try {
      final convo = messages.take(20)
          .map((m) => '${m['role'] == 'user' ? 'المستخدم' : 'حماده'}: ${m['content']}')
          .join('\n');
      final prompt = 'لخّص المحادثة دي في نقاط مهمة (بالعربي المصري، أقل من 10 سطور):\n$convo\n'
          'اذكر: المعلومات الشخصية، القرارات، المواضيع. رد بـ JSON: {"reply":"..."}';
      return await _singleShot(prompt, maxTokens: 300, temperature: 0.3);
    } catch (_) { return ''; }
  }

  Future<String> getGoalComment({required String goalName, required double target,
      required double current, required int? deadlineMs}) async {
    if (!_ready) return '';
    try {
      final daysLeft = deadlineMs != null
          ? DateTime.fromMillisecondsSinceEpoch(deadlineMs).difference(DateTime.now()).inDays
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
      final time   = hour < 12 ? 'الصبح' : (hour < 17 ? 'الضهر' : 'المسا');
      final task   = await db.getTopTodayTask();
      final sum    = await db.getMonthSummary(DateTime.now().year, DateTime.now().month);
      final bal    = ((sum['income'] ?? 0) - (sum['expense'] ?? 0)).toStringAsFixed(0);
      final prompt = PromptConstants.WIDGET_MESSAGE_PROMPT
          .replaceAll('{time_of_day}', time)
          .replaceAll('{top_task}',    task?['title'] as String? ?? 'لا مهام')
          .replaceAll('{balance}',     bal);
      return await _singleShot(prompt, maxTokens: 30, temperature: 0.9);
    } catch (_) { return 'يلا نعمل يوم تمام!'; }
  }

  Future<String> generateMorningGreeting({required List<String> todayTasks,
      required List<String> todayAppointments}) async {
    if (!_ready) return '🌅 صباح الخير!';
    try {
      final prompt = PromptConstants.MORNING_GREETING_PROMPT
          .replaceAll('{tasks}',        todayTasks.join(' • '))
          .replaceAll('{appointments}', todayAppointments.join(' • '));
      return await _singleShot(prompt, maxTokens: 150);
    } catch (_) { return '🌅 صباح الخير! يلا نعمل يوم تمام 💪'; }
  }

  Future<String> generateEveningSummary({required List<String> pendingTasks}) async {
    if (!_ready) return '🌙 مساء الخير!';
    try {
      final prompt = PromptConstants.EVENING_SUMMARY_PROMPT
          .replaceAll('{tasks}', pendingTasks.join(' • '));
      return await _singleShot(prompt, maxTokens: 150);
    } catch (_) { return '🌙 مساء الخير!'; }
  }

  Future<String> classifyFinanceTransaction({required String description,
      required double amount}) async {
    if (!_ready) return 'أخرى';
    try {
      final prompt = PromptConstants.FINANCE_CATEGORY_PROMPT
          .replaceAll('{description}', description)
          .replaceAll('{amount}',      amount.toStringAsFixed(2));
      return await _singleShot(prompt, maxTokens: 10, temperature: 0.1);
    } catch (_) { return 'أخرى'; }
  }

  // ─── HELPERS ──────────────────────────────────────────────

  Future<List<String>> _getRecentNotes() async {
    try {
      final notes = await db.getAllNotes(limit: 4);
      return notes.map((n) {
        final c = n['content'] as String;
        return (n['title'] as String?) ?? c.substring(0, c.length.clamp(0, 60));
      }).toList();
    } catch (_) { return []; }
  }

  void _checkRateLimit() {
    if (!_rl.canSend()) throw Exception('انت بتبعت رسايل بسرعة — استنى ثانية 🐢');
  }

  Future<void> dispose() async {}
}
