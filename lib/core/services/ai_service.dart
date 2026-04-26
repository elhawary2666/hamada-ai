// lib/core/services/ai_service.dart
import 'dart:async';
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

// Global notifier — UI listens to this for instant updates
final aiReadyNotifier = ValueNotifier<bool>(false);

const _groqUrl = 'https://api.groq.com/openai/v1/chat/completions';
const _model   = 'llama-3.3-70b-versatile';
const _kApiKey = 'groq_api_key';

// ── Rate Limiter ──────────────────────────────────────────────

class _RateLimiter {
  static const _minGapMs      = 500;
  static const _maxPerMinute  = 25;

  final _timestamps = <int>[];
  int _lastMs       = 0;

  bool canSend() {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Gap check
    if (now - _lastMs < _minGapMs) return false;
    // Per-minute check
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

// ── Models ────────────────────────────────────────────────────

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

// ── Providers ─────────────────────────────────────────────────

@riverpod
AiService aiService(AiServiceRef ref) {
  // NOTE: ai_service.g.dart uses ref.keepAlive() so this service is never
  // disposed automatically. The onDispose here is a no-op kept for clarity.
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

// ── Service ───────────────────────────────────────────────────

class AiService {
  AiService({required this.db, required this.memoryService});

  final DatabaseHelper db;
  final MemoryService  memoryService;

  // Using dart:http package directly — more reliable on Android than Dio

  final _log      = Logger(printer: PrettyPrinter(methodCount: 0));
  final _rl       = _RateLimiter();

  bool   _ready  = false;
  String _apiKey = '';

  bool   get isReady           => _ready;
  String get activeModelName   => 'Llama 3.3 70B';
  String get activeBackendName => 'Groq (مجاني)';
  int    get remainingRequests => _rl.remainingThisMinute;

  // ── INIT ──────────────────────────────────────────────────

  Future<void> initialize() async {
    try {
      // db.database waits for DB to be fully ready including all tables
      final sqlDb = await db.database;
      // Safety: ensure app_settings exists (for users upgrading from old versions)
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
          _log.i('✅ API key loaded from DB: ${k.length}chars');
        }
      }
    } catch (e) {
      _log.e('Failed to load API key', error: e);
    }
  }

  Future<bool> setApiKey(String key) async {
    final k = key.trim();
    if (!k.startsWith('gsk_') || k.length < 20) return false;
    try {
      final sqlDb = await db.database;
      await sqlDb.execute(
        'CREATE TABLE IF NOT EXISTS app_settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)'
      );
      await sqlDb.insert(
        'app_settings',
        {'key': _kApiKey, 'value': k},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      // Verify the save actually worked
      final rows = await sqlDb.query(
        'app_settings', where: 'key = ?', whereArgs: [_kApiKey]
      );
      if (rows.isEmpty) return false;
      final saved = (rows.first['value'] as String?)?.trim() ?? '';
      if (saved != k) return false;
      _apiKey = k;
      _ready  = true;
      aiReadyNotifier.value = true;
      _log.i('✅ API key saved: ready=$_ready, key=${_apiKey.length}chars, notifier=${aiReadyNotifier.value}');
      return true;
    } catch (e) {
      _log.e('Failed to save API key', error: e);
      return false;
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

  Future<void> clearApiKey() async {
    try {
      final sqlDb = await db.database;
      await sqlDb.delete(
        'app_settings', where: 'key = ?', whereArgs: [_kApiKey]
      );
    } catch (_) {}
    _apiKey = '';
    _ready  = false;
    aiReadyNotifier.value = false;
  }

  // ── CHAT — streaming ──────────────────────────────────────

  Future<HamadaResponse> chat({
    required String userMessage,
    required String sessionId,
    required List<Map<String, dynamic>> history,
    void Function(String token)? onToken,
  }) async {
    // Re-check key from DB if not in memory
    if (_apiKey.isEmpty || !_ready) {
      await initialize();
    }
    if (_apiKey.isEmpty || !_ready) {
      throw Exception('API key مش متضبط — روح الإعدادات وضيف الـ Key 🔑');
    }
    _checkRateLimit();

    final memories = await memoryService.retrieveRelevantMemories(userMessage);
    final notes    = await _getRecentNotes();
    final today    = await _getTodayContext();

    final systemPrompt = PromptConstants.buildPromptWithMemory(
      systemPrompt:     PromptConstants.HAMADA_SYSTEM_PROMPT,
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
          'temperature': 0.7,
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
      // Rethrow known errors (401, 429, status codes)
      if (msg.contains('🔑') || msg.contains('🌙') || msg.contains('خطأ (')) rethrow;
      throw Exception('مشكلة في الاتصال — تأكد من النت وجرّب تاني 📶');
    }
  }

  // ── FINANCIAL ANALYSIS ────────────────────────────────────

  Future<String> analyzeFinances({
    required int year,
    required int month,
  }) async {
    if (!_ready) return 'مفيش API key — روح الإعدادات وضيف الـ Key عشان أحلل ماليتك 🔑';
    try {
      final summary  = await db.getMonthSummary(year, month);
      final cats     = await db.getCategoryTotals(year, month);
      final goals    = await db.getFinancialGoals(activeOnly: false);
      final debt     = await db.getDebtSummary();

      final income  = summary['income']  ?? 0.0;
      final expense = summary['expense'] ?? 0.0;
      final net     = income - expense;

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
          '\nتوزيع المصروفات:\n$catLines';

      final prompt = PromptConstants.FINANCE_ANALYSIS_PROMPT
          .replaceAll('{finance_data}', financeData)
          .replaceAll('{goals_data}',   goalsLines);

      return await _singleShot(prompt, maxTokens: 600, temperature: 0.6);
    } catch (e) {
      return 'حصل خطأ في التحليل: $e';
    }
  }

  // ── GOAL PROGRESS ─────────────────────────────────────────

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
      final pct = target > 0 ? (current / target * 100).toStringAsFixed(0) : '0';
      final prompt = PromptConstants.GOAL_PROGRESS_PROMPT
          .replaceAll('{goal_name}', goalName)
          .replaceAll('{target}',    target.toStringAsFixed(0))
          .replaceAll('{current}',   current.toStringAsFixed(0))
          .replaceAll('{percent}',   pct)
          .replaceAll('{days_left}', daysLeft >= 0 ? '$daysLeft' : 'غير محدد');
      return await _singleShot(prompt, maxTokens: 80, temperature: 0.8);
    } catch (_) { return ''; }
  }

  // ── WIDGET MESSAGE ────────────────────────────────────────

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

  // ── SPECIALIZED ───────────────────────────────────────────

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
    String userMsg, String reply,
  ) async {
    if (!_ready) return [];
    try {
      final prompt = PromptConstants.MEMORY_EXTRACT_PROMPT
          .replaceAll('{conversation}', 'المستخدم: $userMsg\nحماده: $reply');
      final result = await _singleShot(prompt, maxTokens: 500, temperature: 0.1);
      return _parseJsonList(result).cast<Map<String, dynamic>>();
    } catch (_) { return []; }
  }

  // ── PRIVATE ───────────────────────────────────────────────


  /// Public wrapper for single-shot calls (used by chat for suggestions)
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

      // الرصيد الحالي (الشهر الجاري)
      try {
        final summary = await db.getMonthSummary(now.year, now.month);
        final income  = summary['income']  ?? 0.0;
        final expense = summary['expense'] ?? 0.0;
        final balance = income - expense;
        final sign    = balance >= 0 ? '+' : '';
        parts.add('الرصيد الشهري: $sign${balance.toStringAsFixed(0)} ج.م'
            ' (دخل: ${income.toStringAsFixed(0)} | مصروف: ${expense.toStringAsFixed(0)})');
      } catch (_) {}

      // المهام المتأخرة
      try {
        final overdue = await db.getOverdueTasks();
        if (overdue.isNotEmpty) {
          final titles = overdue.take(3).map((t) => t['title'] as String).join(' · ');
          parts.add('مهام متأخرة (${overdue.length}): $titles');
        }
      } catch (_) {}

      // مهام اليوم
      try {
        final tasks = await db.getTodayTasks();
        if (tasks.isNotEmpty) {
          final titles = tasks.take(3).map((t) => t['title'] as String).join(' · ');
          parts.add('مهام اليوم: $titles');
        }
      } catch (_) {}

      // المواعيد القريبة (خلال يومين)
      try {
        final appts = await db.getUpcomingAppointments(withinDays: 2);
        if (appts.isNotEmpty) {
          final titles = appts.take(3).map((a) {
            final ts    = a['start_time'] as int?;
            final timeStr = ts != null
                ? '${DateTime.fromMillisecondsSinceEpoch(ts).hour}:${DateTime.fromMillisecondsSinceEpoch(ts).minute.toString().padLeft(2, '0')}'
                : '';
            return '${a['title']}${timeStr.isNotEmpty ? " ($timeStr)" : ""}';
          }).join(' · ');
          parts.add('مواعيد قريبة: $titles');
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
          await memoryService.saveMemory(
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

  void _assertReady() {
    if (!_ready || _apiKey.isEmpty) {
      throw Exception('API key مش متضبط — روح الإعدادات وضيف الـ Key 🔑');
    }
  }

  void _checkRateLimit() {
    if (!_rl.canSend()) {
      throw Exception('انت بتبعت رسايل بسرعة كبيرة — استنى ثانية 🐢');
    }
  }

  Future<void> dispose() async {}
}
