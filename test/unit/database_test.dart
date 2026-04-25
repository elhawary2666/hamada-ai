// test/unit/database_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:hamada_ai/core/database/database_helper.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DatabaseHelper', () {
    late DatabaseHelper db;

    setUp(() async {
      db = DatabaseHelper.instance;
      await db.database;
    });

    tearDown(() async {
      await db.clearAll();
    });

    test('inserts and retrieves a task', () async {
      await db.insert(Tables.tasks, {
        'id':         'test-001',
        'title':      'مهمة تجريبية',
        'status':     'pending',
        'priority':   'high',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      final tasks = await db.getAllTasks();
      expect(tasks.length, 1);
      expect(tasks.first['title'], 'مهمة تجريبية');
    });

    test('inserts income transaction', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert(Tables.financeTransactions, {
        'id':          'tx-001',
        'type':        'income',
        'amount':      5000.0,
        'currency':    'EGP',
        'category':    'راتب',
        'ai_category': 'راتب',
        'date':        now,
        'is_recurring': 0,
        'payment_method': 'cash',
        'created_at':  now,
      });

      final summary = await db.getMonthSummary(
          DateTime.now().year, DateTime.now().month);
      expect(summary['income'], 5000.0);
      expect(summary['expense'], 0.0);
    });

    test('financial goal progress calculation', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert(Tables.financialGoals, {
        'id':             'goal-001',
        'title':          'شراء لاب توب',
        'target_amount':  10000.0,
        'current_amount': 2500.0,
        'category':       'saving',
        'icon':           '💻',
        'is_completed':   0,
        'created_at':     now,
        'updated_at':     now,
      });

      final goals = await db.getFinancialGoals();
      expect(goals.length, 1);
      expect(goals.first['current_amount'], 2500.0);
      expect(goals.first['target_amount'],  10000.0);

      // Add to goal
      await db.addToGoal('goal-001', 2500.0);
      final updated = await db.getFinancialGoals();
      expect(updated.first['current_amount'], 5000.0);
    });

    test('recurring transaction nextDue update', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert(Tables.recurringTx, {
        'id':          'rec-001',
        'title':       'إيجار',
        'amount':      2000.0,
        'type':        'expense',
        'category':    'إيجار',
        'frequency':   'monthly',
        'next_due':    now,
        'is_active':   1,
        'created_at':  now,
      });

      final due = await db.getDueRecurringTransactions();
      expect(due.length, 1);

      // Update next due
      final nextMonth = DateTime.now()
          .add(const Duration(days: 30)).millisecondsSinceEpoch;
      await db.updateRecurringNextDue('rec-001', nextMonth);

      final dueAfter = await db.getDueRecurringTransactions();
      expect(dueAfter.length, 0);
    });

    test('memory search returns results', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert(Tables.memories, {
        'id':           'mem-001',
        'content':      'صاحبي بيحب البرمجة بـ Flutter',
        'type':         'preference',
        'importance':   8,
        'created_at':   now,
        'updated_at':   now,
        'is_active':    1,
        'tags':         '[]',
      });

      final results = await db.searchMemoriesFts('Flutter');
      expect(results.isNotEmpty, true);
    });

    test('getMonthSummary returns zeros for empty month', () async {
      final summary = await db.getMonthSummary(2020, 1);
      expect(summary['income'],  0.0);
      expect(summary['expense'], 0.0);
    });

    test('category totals calculated correctly', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (int i = 0; i < 3; i++) {
        await db.insert(Tables.financeTransactions, {
          'id':          'tx-cat-$i',
          'type':        'expense',
          'amount':      100.0,
          'currency':    'EGP',
          'category':    'طعام',
          'ai_category': 'طعام',
          'date':        now,
          'is_recurring': 0,
          'payment_method': 'cash',
          'created_at':  now,
        });
      }

      final cats = await db.getCategoryTotals(
          DateTime.now().year, DateTime.now().month);
      expect(cats['طعام'], 300.0);
    });

    test('debt summary calculates owe vs owed', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert(Tables.debts, {
        'id':         'debt-001',
        'name':       'قرض من أحمد',
        'amount':     500.0,
        'direction':  'owe',
        'is_paid':    0,
        'created_at': now,
      });
      await db.insert(Tables.debts, {
        'id':         'debt-002',
        'name':       'دين لمحمد',
        'amount':     200.0,
        'direction':  'owed',
        'is_paid':    0,
        'created_at': now,
      });

      final summary = await db.getDebtSummary();
      expect(summary, isNotNull);
      expect(summary!['owe'],  500.0);
      expect(summary['owed'], 200.0);
    });

    test('clearAll removes all data', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert(Tables.tasks, {
        'id':         'cl-001',
        'title':      'مهمة',
        'status':     'pending',
        'priority':   'low',
        'created_at': now,
      });
      await db.clearAll();
      final tasks = await db.getAllTasks();
      expect(tasks.length, 0);
    });
  });
}
