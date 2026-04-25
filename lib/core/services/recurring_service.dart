// lib/core/services/recurring_service.dart
import 'package:logger/logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
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

  /// Check for due recurring transactions and create them
  Future<int> processDueTransactions() async {
    final due = await db.getDueRecurringTransactions();
    if (due.isEmpty) return 0;

    int count = 0;
    for (final rec in due) {
      try {
        final now = DateTime.now().millisecondsSinceEpoch;
        // Create actual transaction
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

        // Calculate next due date
        final nextDue = _calcNextDue(
          DateTime.fromMillisecondsSinceEpoch(rec['next_due'] as int),
          rec['frequency'] as String,
        );
        await db.updateRecurringNextDue(rec['id'] as String, nextDue.millisecondsSinceEpoch);
        count++;
        _log.i('✅ Recurring tx created: ${rec['title']} — ${rec['amount']} EGP');
      } catch (e) {
        _log.e('Failed to process recurring: ${rec['id']}', error: e);
      }
    }
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
}
