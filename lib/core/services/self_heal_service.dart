// lib/core/services/self_heal_service.dart
import 'dart:convert';
import 'package:logger/logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../database/database_helper.dart';
import '../di/providers.dart';

part 'self_heal_service.g.dart';

@riverpod
SelfHealService selfHealService(SelfHealServiceRef ref) =>
    SelfHealService(db: ref.watch(databaseHelperProvider));

class HealthReport {
  final bool   isHealthy;
  final List<String> issues;
  final List<String> fixes;
  const HealthReport({required this.isHealthy, this.issues = const [], this.fixes = const []});
}

class SelfHealService {
  SelfHealService({required this.db});
  final DatabaseHelper db;
  final _log = Logger(printer: PrettyPrinter(methodCount: 0));

  // ── Verify last write succeeded ──────────────────────────
  Future<bool> verifyTransactionWrite(String id) async {
    try {
      final sqlDb = await db.database;
      final rows  = await sqlDb.query('finance_transactions',
          where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) {
        await db.logError('write_failed', 'Transaction not saved', {'id': id});
        return false;
      }
      return true;
    } catch (_) { return false; }
  }

  Future<bool> verifyTaskWrite(String id) async {
    try {
      final sqlDb = await db.database;
      final rows  = await sqlDb.query('tasks', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) {
        await db.logError('write_failed', 'Task not saved', {'id': id});
        return false;
      }
      return true;
    } catch (_) { return false; }
  }

  // ── Full health check ─────────────────────────────────────
  Future<HealthReport> runHealthCheck() async {
    final issues = <String>[];
    final fixes  = <String>[];

    try {
      // 1. Check unresolved errors
      final errors = await db.getUnresolvedErrors();
      if (errors.isNotEmpty) {
        issues.add('${errors.length} خطأ غير محلول في السجل');
        // Auto-resolve old errors (>24h)
        final cutoff = DateTime.now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch;
        for (final e in errors) {
          final createdAt = e['created_at'] as int? ?? 0;
          if (createdAt < cutoff) {
            await db.markErrorResolved(e['id'] as String);
            fixes.add('تم تنظيف خطأ قديم: ${e['error_type']}');
          }
        }
      }

      // 2. Check orphan habit logs
      final sqlDb = await db.database;
      final orphanLogs = await sqlDb.rawQuery(
          'SELECT COUNT(*) as c FROM habit_logs hl '
          'WHERE NOT EXISTS (SELECT 1 FROM habits h WHERE h.id = hl.habit_id)'
      );
      final orphanCount = (orphanLogs.first['c'] as int?) ?? 0;
      if (orphanCount > 0) {
        await sqlDb.execute(
            'DELETE FROM habit_logs WHERE habit_id NOT IN (SELECT id FROM habits)');
        fixes.add('حذف $orphanCount سجل عادة يتيم');
      }

      // 3. Check transactions with 0 amount
      final zeroTx = await sqlDb.rawQuery(
          'SELECT COUNT(*) as c FROM finance_transactions WHERE amount <= 0');
      final zeroCount = (zeroTx.first['c'] as int?) ?? 0;
      if (zeroCount > 0) {
        await sqlDb.execute('DELETE FROM finance_transactions WHERE amount <= 0');
        fixes.add('حذف $zeroCount معاملة بمبلغ صفر');
      }

      // 4. Check memories integrity
      final badMemories = await sqlDb.rawQuery(
          "SELECT COUNT(*) as c FROM memories WHERE content IS NULL OR content = '' OR is_active = 1 AND length(content) < 3");
      final badCount = (badMemories.first['c'] as int?) ?? 0;
      if (badCount > 0) {
        await sqlDb.execute("DELETE FROM memories WHERE content IS NULL OR content = '' OR length(content) < 3");
        fixes.add('حذف $badCount ذاكرة فارغة');
      }

      // 5. Prune old memories (>90 days, low importance)
      final pruned = await db.pruneOldMemories();
      if (pruned > 0) fixes.add('نظّف $pruned ذاكرة قديمة');

      _log.i('Health check done: ${issues.length} issues, ${fixes.length} fixes');
      return HealthReport(
        isHealthy: issues.isEmpty,
        issues:    issues,
        fixes:     fixes,
      );
    } catch (e) {
      _log.w('Health check error: $e');
      return HealthReport(isHealthy: false, issues: ['خطأ في الفحص: $e']);
    }
  }

  // ── Detect data anomalies proactively ────────────────────
  Future<List<String>> detectAnomalies() async {
    final anomalies = <String>[];
    try {
      final sqlDb = await db.database;
      final now   = DateTime.now();

      // Large transaction spike (>3x average)
      final avgRow = await sqlDb.rawQuery(
          "SELECT AVG(amount) as avg FROM finance_transactions WHERE type='expense' AND date > ?",
          [now.subtract(const Duration(days: 30)).millisecondsSinceEpoch]);
      final avg    = (avgRow.first['avg'] as num?)?.toDouble() ?? 0;
      if (avg > 0) {
        final spikes = await sqlDb.rawQuery(
            "SELECT title, amount FROM finance_transactions "
            "WHERE type='expense' AND amount > ? AND date > ? ORDER BY amount DESC LIMIT 3",
            [avg * 3, now.subtract(const Duration(days: 7)).millisecondsSinceEpoch]);
        for (final s in spikes) {
          anomalies.add('مصروف كبير غير عادي: ${s['title'] ?? ''} (${s['amount']} ج.م)');
        }
      }

      // Overdue tasks > 5 days
      final overdueCutoff = now.subtract(const Duration(days: 5)).millisecondsSinceEpoch;
      final overdue = await sqlDb.rawQuery(
          "SELECT COUNT(*) as c FROM tasks WHERE status='pending' AND due_date > 0 AND due_date < ?",
          [overdueCutoff]);
      final overdueCount = (overdue.first['c'] as int?) ?? 0;
      if (overdueCount >= 3) {
        anomalies.add('$overdueCount مهام متأخرة أكتر من 5 أيام');
      }

      // Debt growing
      final debts = await sqlDb.rawQuery(
          "SELECT SUM(amount) as t FROM debts WHERE direction='owe' AND is_paid=0");
      final totalDebt = (debts.first['t'] as num?)?.toDouble() ?? 0;
      if (totalDebt > 5000) {
        anomalies.add('ديون تراكمية تجاوزت ${totalDebt.toStringAsFixed(0)} ج.م');
      }

    } catch (_) {}
    return anomalies;
  }
}
