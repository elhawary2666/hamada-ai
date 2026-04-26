// lib/core/services/recurring_service.dart
import 'package:logger/logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../di/providers.dart';

part 'recurring_service.g.dart';

@riverpod
RecurringService recurringService(RecurringServiceRef ref) =>
    RecurringService(db: ref.watch(databaseHelperProvider));

class RecurringService {
  RecurringService({required this.db});
  final DatabaseHelper db;
  final _uuid = const Uuid();
  final _log  = Logger(printer: PrettyPrinter(methodCount: 0));

  // ✅ FIX Bug #7: Idempotency guard — only run once per calendar day
  Future<int> processDueTransactions() async {
    final prefs   = await SharedPreferences.getInstance();
    final todayKey = _todayKey();
    final lastRun  = prefs.getString('recurring_last_run');

    // Already ran today — skip to prevent duplicates
    if (lastRun == todayKey) {
      _log.d('Recurring: already ran today, skipping');
      return 0;
    }

    final due = await db.getDueRecurringTransactions();
    if (due.isEmpty) {
      await prefs.setString('recurring_last_run', todayKey);
      return 0;
    }

    int count = 0;
    for (final rec in due) {
      try {
        final now = DateTime.now().millisecondsSinceEpoch;
        await db.insert('finance_transactions', {
          'id':             _uuid.v4(),
          'type':           rec['type'],
          'amount':         rec['amount'],
          'currency':       'EGP',
          'category':       rec['category'],
          'ai_category':    rec['category'],
          'description':    rec['title'],
          'date':           now,
          'is_recurring':   1,
          'recurring_id':   rec['id'],
          'payment_method': rec['payment_method'] ?? 'cash',
          'created_at':     now,
        });

        final nextDue = _calcNextDue(
          DateTime.fromMillisecondsSinceEpoch(rec['next_due'] as int),
          rec['frequency'] as String,
        );
        await db.updateRecurringNextDue(rec['id'] as String, nextDue.millisecondsSinceEpoch);
        count++;
        _log.i('✅ Recurring tx: ${rec['title']} — ${rec['amount']} EGP');
      } catch (e) {
        _log.e('Failed recurring: ${rec['id']}', error: e);
      }
    }

    // Mark as run for today
    await prefs.setString('recurring_last_run', todayKey);
    return count;
  }

  DateTime _calcNextDue(DateTime from, String frequency) {
    switch (frequency) {
      case 'daily':   return from.add(const Duration(days: 1));
      case 'weekly':  return from.add(const Duration(days: 7));
      case 'monthly': return DateTime(from.year, from.month + 1, from.day);
      case 'yearly':  return DateTime(from.year + 1, from.month, from.day);
      default:        return from.add(const Duration(days: 30));
    }
  }

  String frequencyArabic(String f) {
    switch (f) {
      case 'daily':   return 'يومياً';
      case 'weekly':  return 'أسبوعياً';
      case 'monthly': return 'شهرياً';
      case 'yearly':  return 'سنوياً';
      default:        return f;
    }
  }

  String _todayKey() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  }
}

