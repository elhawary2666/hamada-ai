// lib/core/services/pattern_service.dart
import 'dart:convert';
import 'dart:math' as math;
import 'package:logger/logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../database/database_helper.dart';
import '../di/providers.dart';
import 'ai_service.dart';

part 'pattern_service.g.dart';

@riverpod
PatternService patternService(PatternServiceRef ref) => PatternService(
  db: ref.watch(databaseHelperProvider),
  ai: ref.watch(aiServiceProvider),
);

class PatternInsight {
  final String type;
  final String message;
  final double confidence;
  const PatternInsight({required this.type, required this.message, required this.confidence});
}

class PatternService {
  PatternService({required this.db, required this.ai});
  final DatabaseHelper db;
  final AiService      ai;
  final _log = Logger(printer: PrettyPrinter(methodCount: 0));

  // ── Run full pattern analysis ─────────────────────────────
  Future<List<PatternInsight>> analyzePatterns() async {
    final insights = <PatternInsight>[];
    try {
      insights.addAll(await _detectSpendingPatterns());
      insights.addAll(await _detectLifeBalance());
      insights.addAll(await _detectFinancialDNA());
      // Save patterns to DB
      for (final insight in insights) {
        await db.upsertPattern(insight.type, insight.message, {}, insight.confidence);
      }
    } catch (e) { _log.w('Pattern analysis error: $e'); }
    return insights;
  }

  // ── Spending pattern detection ────────────────────────────
  Future<List<PatternInsight>> _detectSpendingPatterns() async {
    final insights = <PatternInsight>[];
    try {
      final sqlDb = await db.database;
      final now   = DateTime.now();
      final since = now.subtract(const Duration(days: 60)).millisecondsSinceEpoch;

      // Check spending by day of week
      final byDay = await sqlDb.rawQuery("""
        SELECT
          CAST(strftime('%w', datetime(date/1000,'unixepoch','localtime')) AS INTEGER) as dow,
          SUM(amount) as total, COUNT(*) as cnt
        FROM finance_transactions
        WHERE type='expense' AND date > ?
        GROUP BY dow ORDER BY total DESC
      """, [since]);

      if (byDay.isNotEmpty) {
        final topDay = byDay.first;
        final dowNames = ['الأحد','الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت'];
        final dow      = (topDay['dow'] as int?) ?? 0;
        final total    = (topDay['total'] as num?)?.toDouble() ?? 0;
        final avgOther = byDay.skip(1)
            .map((r) => (r['total'] as num?)?.toDouble() ?? 0)
            .fold(0.0, (a, b) => a + b) / math.max(byDay.length - 1, 1);
        if (avgOther > 0 && total > avgOther * 1.5) {
          insights.add(PatternInsight(
            type:       'spending_day',
            message:    'لاحظت إنك بتصرف أكتر يوم ${dowNames[dow]} - حوالي ${total.toStringAsFixed(0)} ج.م في المتوسط',
            confidence: 0.75,
          ));
        }
      }

      // Check end-of-month spending spike
      final endMonth = await sqlDb.rawQuery("""
        SELECT
          CASE WHEN CAST(strftime('%d', datetime(date/1000,'unixepoch','localtime')) AS INTEGER) >= 25 THEN 'end' ELSE 'other' END as period,
          SUM(amount) as total
        FROM finance_transactions WHERE type='expense' AND date > ?
        GROUP BY period
      """, [since]);
      double endTotal = 0, otherTotal = 0;
      for (final r in endMonth) {
        if (r['period'] == 'end') endTotal = (r['total'] as num?)?.toDouble() ?? 0;
        else otherTotal = (r['total'] as num?)?.toDouble() ?? 0;
      }
      if (otherTotal > 0 && endTotal > otherTotal * 0.4) {
        insights.add(PatternInsight(
          type:       'end_month_spike',
          message:    'مصروفاتك بتزيد آخر الشهر - غالباً بتنهار الميزانية في الأسبوع الأخير',
          confidence: 0.7,
        ));
      }

    } catch (_) {}
    return insights;
  }

  // ── Life balance analysis (time/energy not just money) ────
  Future<List<PatternInsight>> _detectLifeBalance() async {
    final insights = <PatternInsight>[];
    try {
      final topicsCount = await db.getChatTopics();
      if (topicsCount.isEmpty) return insights;

      final total   = topicsCount.values.fold(0, (a, b) => a + b);
      if (total < 10) return insights;

      // Find dominant topic
      final sorted = topicsCount.entries.toList()..sort((a,b) => b.value.compareTo(a.value));
      final top    = sorted.first;
      final pct    = (top.value / total * 100).toInt();

      if (pct > 50) {
        insights.add(PatternInsight(
          type:       'life_imbalance',
          message:    'الأسبوع ده ${pct}% من حديثك كان عن "${top.key}" - باقي جوانب حياتك بتاخد مساحة أقل',
          confidence: 0.65,
        ));
      }

      // Check if health is neglected
      final healthPct = ((topicsCount['صحة'] ?? 0) / total * 100).toInt();
      if (healthPct < 5 && total > 20) {
        insights.add(PatternInsight(
          type:       'health_neglect',
          message:    'لاحظت إن موضوع الصحة مش بياخد وقت في حياتك الأخيرة',
          confidence: 0.6,
        ));
      }

      // Save life balance for this week
      final weekKey = _weekKey(DateTime.now());
      await db.saveLifeBalance(weekKey, {
        'topics':    topicsCount,
        'top_topic': top.key,
        'top_pct':   pct,
      });

    } catch (_) {}
    return insights;
  }

  // ── Financial DNA ─────────────────────────────────────────
  Future<List<PatternInsight>> _detectFinancialDNA() async {
    final insights = <PatternInsight>[];
    try {
      final sqlDb = await db.database;
      final rows  = await sqlDb.rawQuery(
          'SELECT COUNT(*) as c FROM finance_transactions');
      final txCount = (rows.first['c'] as int?) ?? 0;
      if (txCount < 30) return insights; // Need enough data

      final since = DateTime.now().subtract(const Duration(days: 90)).millisecondsSinceEpoch;
      final cats  = await sqlDb.rawQuery("""
        SELECT category, SUM(amount) as total
        FROM finance_transactions WHERE type='expense' AND date > ?
        GROUP BY category ORDER BY total DESC
      """, [since]);

      if (cats.isEmpty) return insights;

      final totalExp  = cats.map((r) => (r['total'] as num?)?.toDouble() ?? 0).fold(0.0, (a,b) => a+b);
      final topCat    = cats.first;
      final topCatName = topCat['category'] as String? ?? '';
      final topCatPct  = totalExp > 0 ? ((topCat['total'] as num?)?.toDouble() ?? 0) / totalExp * 100 : 0;

      // Classify financial personality
      String dna = '';
      if (topCatName == 'طعام' && topCatPct > 35) {
        dna = 'أنت النوع اللي بيصرف كتير على الأكل - الأكل بالنسباله متعة وراحة نفسية';
      } else if (topCatName == 'تسوق' && topCatPct > 30) {
        dna = 'أنت النوع اللي بيشتري لما زهق أو في ضغط - التسوق نوع من التعبير العاطفي';
      } else if (topCatName == 'ترفيه' && topCatPct > 25) {
        dna = 'أنت النوع اللي بيصرف على التجارب مش الأشياء - الذكريات أهم من الممتلكات';
      } else if (topCatName == 'إيجار' || topCatName == 'فواتير') {
        dna = 'معظم مصروفاتك التزامات ثابتة - ده بيقلل مرونتك المالية';
      }

      if (dna.isNotEmpty) {
        insights.add(PatternInsight(
          type:       'financial_dna',
          message:    dna,
          confidence: 0.7,
        ));
      }

    } catch (_) {}
    return insights;
  }

  // ── Auto daily timeline ───────────────────────────────────
  Future<String> buildDailyTimeline(DateTime date) async {
    try {
      final dateStr  = _dateStr(date);
      final existing = await db.getDailyTimeline(dateStr);
      if (existing != null) return existing;

      final start = DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
      final end   = start + 86400000;
      final txs   = await db.getTransactionsByDateRange(start, end);
      final tasks = await db.getAllTasks();
      final doneTasks = tasks.where((t) {
        // tasks done today (updated_at or created_at in range)
        final ca = t['created_at'] as int? ?? 0;
        return t['status'] == 'done' && ca >= start && ca < end;
      }).toList();

      final parts = <String>[];

      // Transactions
      if (txs.isNotEmpty) {
        double income = 0, expense = 0;
        final cats = <String>{};
        for (final t in txs) {
          final amt = (t['amount'] as num).toDouble();
          if (t['type'] == 'income') { income += amt; }
          else { expense += amt; cats.add(t['category'] as String? ?? ''); }
        }
        if (income > 0)  parts.add('دخل ${income.toStringAsFixed(0)} ج.م');
        if (expense > 0) parts.add('صرف ${expense.toStringAsFixed(0)} ج.م على ${cats.take(3).join(', ')}');
      }

      // Tasks done
      if (doneTasks.isNotEmpty) {
        parts.add('خلّص ${doneTasks.length} مهمة');
      }

      if (parts.isEmpty) parts.add('يوم هادي');

      final timeline = parts.join(' | ');
      await db.saveDailyTimeline(dateStr, timeline);
      return timeline;
    } catch (_) { return ''; }
  }

  // ── Appointment prep brief ────────────────────────────────
  Future<String> getAppointmentBrief(Map<String,dynamic> appt) async {
    try {
      if (!ai.isReady) return '';
      final title    = appt['title'] as String? ?? '';
      final location = appt['location'] as String? ?? '';
      // Search memories for related info
      final memories = await db.searchMemoriesFts(title, limit: 5);
      if (memories.isEmpty) return '';
      final memStr   = memories.take(3).map((m) => m['content'] as String).join(' | ');
      final prompt   = 'أنت حماده. بكرة عند صاحبك موعد: "$title" ${location.isNotEmpty ? "في $location" : ""}.
'
          'ذكريات مرتبطة: $memStr
'
          'اكتب جملة أو جملتين تجهيز مفيد قبل الموعد ده.
'
          'رد: {"reply":"..."}';
      return await ai.singleShot(prompt, maxTokens: 100);
    } catch (_) { return ''; }
  }

  // ── Helpers ───────────────────────────────────────────────
  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  String _weekKey(DateTime d) {
    final mon = d.subtract(Duration(days: d.weekday - 1));
    return _dateStr(mon);
  }
}
