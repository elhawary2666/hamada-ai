// lib/core/database/database_helper.dart
import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:logger/logger.dart';

const int _kDbVersion = 5;
const String _kDbName = 'hamada_ai.db';

abstract class Tables {
  static const messages            = 'messages';
  static const memories            = 'memories';
  static const memoriesFts         = 'memories_fts';
  static const userNotes           = 'user_notes';
  static const notesFts            = 'user_notes_fts';
  static const financeTransactions = 'finance_transactions';
  static const transactionsFts     = 'finance_transactions_fts';
  static const assets              = 'assets';
  static const debts               = 'debts';
  static const tasks               = 'tasks';
  static const appointments        = 'appointments';
  static const financialGoals      = 'financial_goals';
  static const recurringTx         = 'recurring_transactions';
  static const appSettings         = 'app_settings';
  static const habits              = 'habits';
  static const habitLogs           = 'habit_logs';
  static const relationships       = 'relationships';
  static const billSplits          = 'bill_splits';
}

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static Database? _db;
  final _log = Logger(printer: PrettyPrinter(methodCount: 0));

  Future<Database> get database async { _db ??= await _init(); return _db!; }

  Future<Database> _init() async {
    final path = join(await getDatabasesPath(), _kDbName);
    return openDatabase(path,
        version: _kDbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onConfigure: _onConfigure);
  }

  Future<void> _onConfigure(Database db) async {
    for (final pragma in [
      'PRAGMA foreign_keys = ON',
      'PRAGMA cache_size = -8000',
      'PRAGMA synchronous = NORMAL',
      'PRAGMA temp_store = MEMORY',
    ]) {
      try { await db.execute(pragma); } catch (_) {}
    }
  }

  Future<void> _onCreate(Database db, int v) async {
    _log.i('Creating database v$v');
    for (final create in [
      () => _createMessages(db),
      () => _createMemories(db),
      () => _createNotes(db),
      () => _createTransactions(db),
      () => _createAssets(db),
      () => _createDebts(db),
      () => _createBudgets(db),
      () => _createTasks(db),
      () => _createAppointments(db),
      () => _createFinancialGoals(db),
      () => _createRecurringTx(db),
      () => _createSettings(db),
      () => _createHabits(db),
      () => _createHabitLogs(db),
      () => _createRelationships(db),
      () => _createBillSplits(db),
      () => _createFts(db),
      () => _createIndexes(db),
    ]) {
      try { await create(); } catch (e) { _log.w('Table create warning: $e'); }
    }
    _log.i('Database ready');
  }

  Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    _log.i('Upgrading DB from v$oldV to v$newV');
    if (oldV < 2) {
      try { await _createFinancialGoals(db); } catch (_) {}
      try { await _createRecurringTx(db); } catch (_) {}
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_recurring_next_due ON ${Tables.recurringTx}(next_due)'); } catch (_) {}
    }
    if (oldV < 3) {
      try { await _createSettings(db); } catch (_) {}
    }
    if (oldV < 4) {
      try {
        await db.execute("UPDATE ${Tables.tasks} SET priority = 'high'   WHERE priority = '5' OR CAST(priority AS INTEGER) = 5");
        await db.execute("UPDATE ${Tables.tasks} SET priority = 'medium' WHERE priority = '3' OR CAST(priority AS INTEGER) = 3");
        await db.execute("UPDATE ${Tables.tasks} SET priority = 'low'    WHERE priority = '1' OR CAST(priority AS INTEGER) = 1");
        await db.execute("UPDATE ${Tables.tasks} SET priority = 'medium' WHERE priority IS NULL OR priority NOT IN ('low','medium','high')");
        _log.i('v4: Migrated tasks.priority INT -> TEXT');
      } catch (e) { _log.w('v4 priority migration warning: $e'); }
      try { await db.execute('ALTER TABLE ${Tables.tasks} ADD COLUMN due_date INTEGER'); } catch (_) {}
    }
    if (oldV < 5) {
      try { await _createHabits(db); } catch (_) {}
      try { await _createHabitLogs(db); } catch (_) {}
      try { await _createRelationships(db); } catch (_) {}
      try { await _createBillSplits(db); } catch (_) {}
      _log.i('v5: Added habits, habit_logs, relationships, bill_splits');
    }
  }

  // TABLE DDL
  Future<void> _createMessages(DatabaseExecutor db) => db.execute("""
    CREATE TABLE IF NOT EXISTS ${Tables.messages}(
      id TEXT PRIMARY KEY, session_id TEXT NOT NULL,
      role TEXT NOT NULL CHECK(role IN('user','assistant')),
      content TEXT NOT NULL, timestamp INTEGER NOT NULL,
      is_bookmarked INTEGER DEFAULT 0, metadata TEXT DEFAULT '{}'
    )""");

  Future<void> _createMemories(DatabaseExecutor db) => db.execute("""
    CREATE TABLE IF NOT EXISTS ${Tables.memories}(
      id TEXT PRIMARY KEY, content TEXT NOT NULL,
      type TEXT NOT NULL CHECK(type IN('fact','preference','goal','event','finance','health','relationship','note')),
      importance INTEGER DEFAULT 5 CHECK(importance BETWEEN 1 AND 10),
      embedding BLOB, embedding_dim INTEGER DEFAULT 0, source_msg_id TEXT,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
      last_accessed INTEGER, access_count INTEGER DEFAULT 0,
      is_active INTEGER DEFAULT 1, tags TEXT DEFAULT '[]'
    )""");

  Future<void> _createNotes(DatabaseExecutor db) => db.execute("""
    CREATE TABLE IF NOT EXISTS ${Tables.userNotes}(
      id TEXT PRIMARY KEY, title TEXT, content TEXT NOT NULL,
      tags TEXT DEFAULT '[]', color TEXT DEFAULT 'default',
      is_pinned INTEGER DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
    )""");

  Future<void> _createTransactions(DatabaseExecutor db) => db.execute("""
    CREATE TABLE IF NOT EXISTS ${Tables.financeTransactions}(
      id TEXT PRIMARY KEY, type TEXT NOT NULL CHECK(type IN('income','expense')),
      amount REAL NOT NULL CHECK(amount > 0), currency TEXT DEFAULT 'EGP',
      category TEXT NOT NULL, ai_category TEXT DEFAULT '', description TEXT,
      date INTEGER NOT NULL, is_recurring INTEGER DEFAULT 0, recurring_id TEXT,
      payment_method TEXT DEFAULT 'cash', created_at INTEGER NOT NULL
    )""");

  Future<void> _createAssets(DatabaseExecutor db) => db.execute("""
    CREATE TABLE IF NOT EXISTS ${Tables.assets}(
      id TEXT PRIMARY KEY, name TEXT NOT NULL, value REAL NOT NULL,
      type TEXT DEFAULT 'other', updated_at INTEGER NOT NULL
    )""");

  Future<void> _createDebts(DatabaseExecutor db) => db.execute("""
    CREATE TABLE IF NOT EXISTS ${Tables.debts}(
      id TEXT PRIMARY KEY, name TEXT NOT NULL, amount REAL NOT NULL,
      direction TEXT NOT NULL CHECK(direction IN('owe','owed')),
      due_date INTEGER, notes TEXT, is_paid INTEGER DEFAULT 0, created_at INTEGER NOT NULL
    )""");

  Future<void> _createBudgets(DatabaseExecutor db) => db.execute("""
    CREATE TABLE IF NOT EXISTS budgets(
      id TEXT PRIMARY KEY, category TEXT NOT NULL UNIQUE,
      limit_amount REAL NOT NULL, month INTEGER NOT NULL,
      year INTEGER NOT NULL, created_at INTEGER NOT NULL
    )""");

  Future<void> _createTasks(DatabaseExecutor db) => db.execute("""
    CREATE TABLE IF NOT EXISTS ${Tables.tasks}(
      id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT,
      due_date INTEGER, priority TEXT DEFAULT 'medium',
      status TEXT DEFAULT 'pending' CHECK(status IN('pending','done','cancelled')),
      created_at INTEGER NOT NULL
    )""");

  Future<void> _createAppointments(DatabaseExecutor db) => db.execute("""
    CREATE TABLE IF NOT EXISTS ${Tables.appointments}(
      id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT,
      start_time INTEGER NOT NULL, end_time INTEGER, location TEXT,
      created_at INTEGER NOT NULL
    )""");

  Future<void> _createFinancialGoals(DatabaseExecutor db) => db.execute("""
    CREATE TABLE IF NOT EXISTS ${Tables.financialGoals}(
      id TEXT PRIMARY KEY, title TEXT NOT NULL,
      target_amount REAL NOT NULL CHECK(target_amount > 0),
      current_amount REAL NOT NULL DEFAULT 0, category TEXT DEFAULT 'saving',
      deadline INTEGER, notes TEXT, icon TEXT DEFAULT '🎯',
      is_completed INTEGER DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
    )""");

  Future<void> _createSettings(DatabaseExecutor db) => db.execute("""
    CREATE TABLE IF NOT EXISTS app_settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)""");

  Future<void> _createRecurringTx(DatabaseExecutor db) => db.execute("""
    CREATE TABLE IF NOT EXISTS ${Tables.recurringTx}(
      id TEXT PRIMARY KEY, title TEXT NOT NULL,
      amount REAL NOT NULL CHECK(amount > 0), type TEXT NOT NULL CHECK(type IN('income','expense')),
      category TEXT NOT NULL, description TEXT,
      frequency TEXT NOT NULL CHECK(frequency IN('daily','weekly','monthly','yearly')),
      next_due INTEGER NOT NULL, payment_method TEXT DEFAULT 'cash',
      is_active INTEGER DEFAULT 1, created_at INTEGER NOT NULL
    )""");

  Future<void> _createHabits(DatabaseExecutor db) => db.execute("""
    CREATE TABLE IF NOT EXISTS ${Tables.habits}(
      id TEXT PRIMARY KEY, name TEXT NOT NULL, icon TEXT DEFAULT '⭐',
      frequency TEXT DEFAULT 'daily' CHECK(frequency IN('daily','weekly')),
      target_days INTEGER DEFAULT 7, created_at INTEGER NOT NULL
    )""");

  Future<void> _createHabitLogs(DatabaseExecutor db) => db.execute("""
    CREATE TABLE IF NOT EXISTS ${Tables.habitLogs}(
      id TEXT PRIMARY KEY, habit_id TEXT NOT NULL,
      completed_date TEXT NOT NULL, created_at INTEGER NOT NULL,
      FOREIGN KEY(habit_id) REFERENCES habits(id) ON DELETE CASCADE
    )""");

  Future<void> _createRelationships(DatabaseExecutor db) => db.execute("""
    CREATE TABLE IF NOT EXISTS ${Tables.relationships}(
      id TEXT PRIMARY KEY, name TEXT NOT NULL, relation TEXT,
      notes TEXT DEFAULT '[]', birthday INTEGER, last_contact INTEGER,
      created_at INTEGER NOT NULL
    )""");

  Future<void> _createBillSplits(DatabaseExecutor db) => db.execute("""
    CREATE TABLE IF NOT EXISTS ${Tables.billSplits}(
      id TEXT PRIMARY KEY, title TEXT NOT NULL,
      total_amount REAL NOT NULL, payers TEXT NOT NULL,
      created_at INTEGER NOT NULL
    )""");

  Future<void> _createFts(DatabaseExecutor db) async {
    for (final sql in [
      "CREATE VIRTUAL TABLE IF NOT EXISTS ${Tables.memoriesFts} USING fts4(content)",
      "CREATE VIRTUAL TABLE IF NOT EXISTS ${Tables.notesFts} USING fts4(title, content)",
      "CREATE VIRTUAL TABLE IF NOT EXISTS ${Tables.transactionsFts} USING fts4(description, category)",
    ]) { try { await db.execute(sql); } catch (_) {} }
  }

  Future<void> _createIndexes(DatabaseExecutor db) async {
    for (final sql in [
      'CREATE INDEX IF NOT EXISTS idx_messages_session   ON ${Tables.messages}(session_id, timestamp)',
      'CREATE INDEX IF NOT EXISTS idx_memories_type      ON ${Tables.memories}(type, importance DESC)',
      'CREATE INDEX IF NOT EXISTS idx_tx_date            ON ${Tables.financeTransactions}(date DESC)',
      'CREATE INDEX IF NOT EXISTS idx_tasks_due          ON ${Tables.tasks}(due_date, status)',
      'CREATE INDEX IF NOT EXISTS idx_goals_completed    ON ${Tables.financialGoals}(is_completed)',
      'CREATE INDEX IF NOT EXISTS idx_recurring_next_due ON ${Tables.recurringTx}(next_due)',
      'CREATE INDEX IF NOT EXISTS idx_habit_logs_date    ON ${Tables.habitLogs}(habit_id, completed_date)',
      'CREATE INDEX IF NOT EXISTS idx_relationships_name ON ${Tables.relationships}(name)',
    ]) { try { await db.execute(sql); } catch (_) {} }
  }

  // GENERIC CRUD
  Future<void> insert(String table, Map<String, dynamic> row) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
      await _syncFtsTxn(txn, table, row);
    });
  }

  Future<void> update(String table, Map<String, dynamic> row, String id) async {
    final db = await database;
    await db.update(table, row, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> delete(String table, String id) async {
    final db = await database;
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getAll(String table,
      {String? orderBy, int? limit, String? where, List<dynamic>? whereArgs}) async {
    final db = await database;
    return db.query(table, orderBy: orderBy, limit: limit, where: where, whereArgs: whereArgs);
  }

  Future<void> _syncFtsTxn(DatabaseExecutor txn, String table, Map<String, dynamic> row) async {
    try {
      if (table == Tables.memories) {
        await txn.insert(Tables.memoriesFts, {'content': row['content'] ?? ''},
            conflictAlgorithm: ConflictAlgorithm.replace);
      } else if (table == Tables.userNotes) {
        await txn.insert(Tables.notesFts,
            {'title': row['title'] ?? '', 'content': row['content'] ?? ''},
            conflictAlgorithm: ConflictAlgorithm.replace);
      } else if (table == Tables.financeTransactions) {
        await txn.insert(Tables.transactionsFts,
            {'description': row['description'] ?? '', 'category': row['category'] ?? ''},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    } catch (_) {}
  }

  void _syncFts(String table, Map<String, dynamic> row) {
    Future.microtask(() async {
      final db = await database;
      try { await _syncFtsTxn(db, table, row); } catch (_) {}
    });
  }

  // MESSAGES
  Future<List<Map<String, dynamic>>> getSessionMessages(String sessionId, {int? limit}) async {
    final db = await database;
    return db.query(Tables.messages, where: 'session_id = ?', whereArgs: [sessionId],
        orderBy: 'timestamp ASC', limit: limit);
  }

  Future<List<Map<String, dynamic>>> getDistinctSessions() async {
    final db = await database;
    return db.rawQuery(
        'SELECT session_id, MAX(timestamp) as last_ts, COUNT(*) as msg_count '
        'FROM ${Tables.messages} GROUP BY session_id ORDER BY last_ts DESC LIMIT 20');
  }

  // MEMORIES
  Future<List<Map<String, dynamic>>> searchMemoriesFts(String q, {int limit = 20}) async {
    final db = await database;
    final cleaned = q.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), ' ').trim();
    if (cleaned.isEmpty) return [];
    try {
      final ftsRows = await db.rawQuery(
          'SELECT content FROM ${Tables.memoriesFts} WHERE content MATCH ? LIMIT ?',
          [cleaned, limit * 2]);
      if (ftsRows.isEmpty) return [];
      final contents = ftsRows.map((r) => r['content'] as String?)
          .where((c) => c != null && c.isNotEmpty).toList();
      if (contents.isEmpty) return [];
      final placeholders = contents.map((_) => 'content LIKE ?').join(' OR ');
      final args = contents.map((c) => '%$c%').toList();
      return db.query(Tables.memories,
          where: 'is_active = 1 AND ($placeholders)', whereArgs: args,
          orderBy: 'importance DESC, last_accessed DESC', limit: limit);
    } catch (_) {
      return db.query(Tables.memories,
          where: 'content LIKE ? AND is_active = 1', whereArgs: ['%$q%'],
          limit: limit, orderBy: 'importance DESC');
    }
  }

  Future<List<Map<String, dynamic>>> getRecentMemories({int limit = 8}) async {
    final db = await database;
    return db.query(Tables.memories, where: 'is_active = 1',
        orderBy: 'importance DESC, last_accessed DESC', limit: limit);
  }

  Future<List<Map<String, dynamic>>> getMemoriesByType(String type, {int limit = 8}) async {
    final db = await database;
    return db.query(Tables.memories, where: 'type = ? AND is_active = 1', whereArgs: [type],
        orderBy: 'importance DESC, last_accessed DESC', limit: limit);
  }

  Future<void> touchMemory(String id) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.rawUpdate(
        'UPDATE ${Tables.memories} SET last_accessed=?, access_count=access_count+1 WHERE id=?',
        [now, id]);
  }

  Future<int> pruneOldMemories() async {
    final db = await database;
    final cutoff = DateTime.now().subtract(const Duration(days: 90)).millisecondsSinceEpoch;
    return db.delete(Tables.memories,
        where: 'importance < 4 AND last_accessed < ? AND is_active = 1', whereArgs: [cutoff]);
  }

  // NOTES
  Future<List<Map<String, dynamic>>> getAllNotes({int limit = 50}) async {
    final db = await database;
    return db.query(Tables.userNotes, orderBy: 'is_pinned DESC, updated_at DESC', limit: limit);
  }

  Future<List<Map<String, dynamic>>> searchNotes(String q) async {
    final db = await database;
    return db.query(Tables.userNotes,
        where: 'title LIKE ? OR content LIKE ?', whereArgs: ['%$q%', '%$q%'],
        orderBy: 'updated_at DESC');
  }

  // FINANCE
  Future<List<Map<String, dynamic>>> getTransactionsByMonth(int year, int month) async {
    final db = await database;
    final start = DateTime(year, month).millisecondsSinceEpoch;
    final end   = DateTime(year, month + 1).millisecondsSinceEpoch;
    return db.query(Tables.financeTransactions,
        where: 'date >= ? AND date < ?', whereArgs: [start, end], orderBy: 'date DESC');
  }

  Future<List<Map<String, dynamic>>> getTransactionsByDateRange(int start, int end) async {
    final db = await database;
    return db.query(Tables.financeTransactions,
        where: 'date >= ? AND date < ?', whereArgs: [start, end], orderBy: 'date DESC');
  }

  Future<Map<String, double>> getCategoryTotals(int year, int month) async {
    final db    = await database;
    final start = DateTime(year, month).millisecondsSinceEpoch;
    final end   = DateTime(year, month + 1).millisecondsSinceEpoch;
    final rows  = await db.rawQuery(
        'SELECT category, SUM(amount) as total FROM ${Tables.financeTransactions} '
        "WHERE type='expense' AND date>=? AND date<? GROUP BY category ORDER BY total DESC",
        [start, end]);
    return {for (final r in rows) r['category'] as String: (r['total'] as num).toDouble()};
  }

  Future<Map<String, double>> getMonthSummary(int year, int month) async {
    final db    = await database;
    final start = DateTime(year, month).millisecondsSinceEpoch;
    final end   = DateTime(year, month + 1).millisecondsSinceEpoch;
    final income  = await db.rawQuery(
        "SELECT COALESCE(SUM(amount),0) as t FROM ${Tables.financeTransactions} WHERE type='income' AND date>=? AND date<?",
        [start, end]);
    final expense = await db.rawQuery(
        "SELECT COALESCE(SUM(amount),0) as t FROM ${Tables.financeTransactions} WHERE type='expense' AND date>=? AND date<?",
        [start, end]);
    return {
      'income':  (income.first['t']  as num?)?.toDouble() ?? 0.0,
      'expense': (expense.first['t'] as num?)?.toDouble() ?? 0.0,
    };
  }

  Future<Map<String, dynamic>?> getDebtSummary() async {
    final db   = await database;
    final rows = await db.query(Tables.debts, where: 'is_paid = 0');
    if (rows.isEmpty) return null;
    double owe = 0, owed = 0;
    for (final r in rows) {
      final amount = (r['amount'] as num).toDouble();
      if (r['direction'] == 'owe') { owe += amount; } else { owed += amount; }
    }
    return {'owe': owe, 'owed': owed, 'count': rows.length};
  }

  Future<Map<String, double>> getSpendingByTimeOfDay(int year, int month) async {
    final db    = await database;
    final start = DateTime(year, month).millisecondsSinceEpoch;
    final end   = DateTime(year, month + 1).millisecondsSinceEpoch;
    final rows  = await db.rawQuery("""
      SELECT
        CASE
          WHEN CAST(strftime('%H', datetime(date/1000, 'unixepoch', 'localtime')) AS INTEGER) BETWEEN 6 AND 11  THEN 'صباح'
          WHEN CAST(strftime('%H', datetime(date/1000, 'unixepoch', 'localtime')) AS INTEGER) BETWEEN 12 AND 16 THEN 'ضهر'
          WHEN CAST(strftime('%H', datetime(date/1000, 'unixepoch', 'localtime')) AS INTEGER) BETWEEN 17 AND 21 THEN 'مساء'
          ELSE 'ليل'
        END as period,
        SUM(amount) as total
      FROM ${Tables.financeTransactions}
      WHERE type = 'expense' AND date >= ? AND date < ?
      GROUP BY period
    """, [start, end]);
    return {for (final r in rows) r['period'] as String: (r['total'] as num).toDouble()};
  }

  // FINANCIAL GOALS
  Future<List<Map<String, dynamic>>> getFinancialGoals({bool activeOnly = false}) async {
    final db = await database;
    return db.query(Tables.financialGoals,
        where: activeOnly ? 'is_completed = 0' : null,
        orderBy: 'is_completed ASC, created_at DESC');
  }

  Future<void> updateGoalAmount(String id, double newAmount) async {
    final db  = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.rawUpdate(
        'UPDATE ${Tables.financialGoals} SET current_amount=?, updated_at=?, '
        'is_completed = CASE WHEN ? >= target_amount THEN 1 ELSE 0 END WHERE id=?',
        [newAmount, now, newAmount, id]);
  }

  Future<void> addToGoal(String id, double amount) async {
    final db   = await database;
    final rows = await db.query(Tables.financialGoals, where: 'id=?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final current = (rows.first['current_amount'] as num).toDouble();
    await updateGoalAmount(id, current + amount);
  }

  // RECURRING TRANSACTIONS
  Future<List<Map<String, dynamic>>> getRecurringTransactions({bool activeOnly = true}) async {
    final db = await database;
    return db.query(Tables.recurringTx,
        where: activeOnly ? 'is_active = 1' : null, orderBy: 'next_due ASC');
  }

  Future<List<Map<String, dynamic>>> getDueRecurringTransactions() async {
    final db  = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.query(Tables.recurringTx,
        where: 'is_active = 1 AND next_due <= ?', whereArgs: [now]);
  }

  Future<void> updateRecurringNextDue(String id, int nextDue) async {
    final db = await database;
    await db.update(Tables.recurringTx, {'next_due': nextDue}, where: 'id = ?', whereArgs: [id]);
  }

  // TASKS
  Future<List<Map<String, dynamic>>> getTodayTasks() async {
    final db    = await database;
    final start = DateTime.now().copyWith(hour: 0,  minute: 0,  second: 0).millisecondsSinceEpoch;
    final end   = DateTime.now().copyWith(hour: 23, minute: 59, second: 59).millisecondsSinceEpoch;
    return db.query(Tables.tasks,
        where: 'due_date >= ? AND due_date <= ? AND status != ?',
        whereArgs: [start, end, 'cancelled'],
        orderBy: "CASE priority WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END, due_date ASC");
  }

  Future<List<Map<String, dynamic>>> getAllTasks({String? statusFilter}) async {
    final db = await database;
    return db.query(Tables.tasks,
        where: statusFilter != null ? 'status = ?' : null,
        whereArgs: statusFilter != null ? [statusFilter] : null,
        orderBy: "status ASC, CASE priority WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END, due_date ASC");
  }

  Future<Map<String, dynamic>?> getTopTodayTask() async {
    final tasks = await getTodayTasks();
    return tasks.isEmpty ? null : tasks.first;
  }

  Future<List<Map<String, dynamic>>> getOverdueTasks() async {
    final db    = await database;
    final today = DateTime.now().copyWith(hour: 0, minute: 0, second: 0).millisecondsSinceEpoch;
    return db.query(Tables.tasks,
        where: 'due_date < ? AND due_date > 0 AND status = ?',
        whereArgs: [today, 'pending'], orderBy: 'due_date ASC');
  }

  // APPOINTMENTS
  Future<List<Map<String, dynamic>>> getUpcomingAppointments({int withinDays = 7}) async {
    final db  = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final end = DateTime.now().add(Duration(days: withinDays)).millisecondsSinceEpoch;
    return db.query(Tables.appointments,
        where: 'start_time >= ? AND start_time <= ?', whereArgs: [now, end],
        orderBy: 'start_time ASC');
  }

  // HABITS
  Future<List<Map<String, dynamic>>> getAllHabits() async {
    final db = await database;
    return db.query(Tables.habits, orderBy: 'created_at ASC');
  }

  Future<void> logHabit(String habitId, String completedDate, String logId, int createdAt) async {
    final db       = await database;
    final existing = await db.query(Tables.habitLogs,
        where: 'habit_id = ? AND completed_date = ?', whereArgs: [habitId, completedDate]);
    if (existing.isNotEmpty) return;
    await db.insert(Tables.habitLogs,
        {'id': logId, 'habit_id': habitId, 'completed_date': completedDate, 'created_at': createdAt});
  }

  Future<int> calculateStreak(String habitId) async {
    final db   = await database;
    final rows = await db.query(Tables.habitLogs,
        where: 'habit_id = ?', whereArgs: [habitId], orderBy: 'completed_date DESC');
    if (rows.isEmpty) return 0;

    final today = DateTime.now();
    final todayNorm = DateTime(today.year, today.month, today.day);

    // ✅ FIX: parse and normalise dates, filter out future dates
    final dates = rows
        .map((r) => DateTime.tryParse(r['completed_date'] as String))
        .where((d) => d != null)
        .map((d) => DateTime(d!.year, d.month, d.day))
        .where((d) => !d.isAfter(todayNorm)) // ignore future dates
        .toList();

    if (dates.isEmpty) return 0;

    int streak = 0;
    // Start from today or yesterday
    DateTime cursor = todayNorm;
    for (final d in dates) {
      final diff = cursor.difference(d).inDays;
      if (diff == 0) {
        streak++;
        cursor = d.subtract(const Duration(days: 1));
      } else if (diff == 1) {
        streak++;
        cursor = d.subtract(const Duration(days: 1));
      } else {
        break; // gap in streak
      }
    }
    return streak;
  }

  Future<bool> isHabitLoggedToday(String habitId) async {
    final db    = await database;
    final today = _dateStr(DateTime.now());
    final rows  = await db.query(Tables.habitLogs,
        where: 'habit_id = ? AND completed_date = ?', whereArgs: [habitId, today]);
    return rows.isNotEmpty;
  }

  Future<Map<String, dynamic>?> getHabitByName(String name) async {
    final db   = await database;
    final rows = await db.query(Tables.habits,
        where: 'name LIKE ?', whereArgs: ['%$name%'], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  // RELATIONSHIPS
  Future<List<Map<String, dynamic>>> getAllRelationships() async {
    final db = await database;
    return db.query(Tables.relationships, orderBy: 'name ASC');
  }

  Future<Map<String, dynamic>?> getRelationshipByName(String name) async {
    final db   = await database;
    final rows = await db.query(Tables.relationships,
        where: 'name LIKE ?', whereArgs: ['%$name%'], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> getUpcomingBirthdays({int withinDays = 3}) async {
    final db       = await database;
    final now      = DateTime.now();
    final upcoming = <Map<String, dynamic>>[];
    final all      = await db.query(Tables.relationships, where: 'birthday IS NOT NULL');
    for (final r in all) {
      final bday = r['birthday'] as int?;
      if (bday == null) continue;
      final bd       = DateTime.fromMillisecondsSinceEpoch(bday);
      final thisYear = DateTime(now.year, bd.month, bd.day);
      final diff     = thisYear.difference(DateTime(now.year, now.month, now.day)).inDays;
      if (diff >= 0 && diff <= withinDays) {
        upcoming.add({...r, 'days_until': diff});
      }
    }
    return upcoming;
  }

  Future<void> addNoteToRelationship(String id, String note) async {
    final db   = await database;
    final rows = await db.query(Tables.relationships, where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final existing = rows.first['notes'] as String? ?? '[]';
    final now      = DateTime.now().toIso8601String();
    // ✅ FIX: use jsonEncode for safe string serialization
    List<dynamic> notesList;
    try {
      notesList = jsonDecode(existing) as List<dynamic>;
    } catch (_) {
      notesList = [];
    }
    notesList.add({'note': note, 'date': now});
    final updated = jsonEncode(notesList);
    await db.update(Tables.relationships, {'notes': updated}, where: 'id = ?', whereArgs: [id]);
  }

  // BILL SPLITS
  Future<List<Map<String, dynamic>>> getAllBillSplits() async {
    final db = await database;
    return db.query(Tables.billSplits, orderBy: 'created_at DESC');
  }

  // BUDGETS
  Future<List<Map<String, dynamic>>> getBudgets(int year, int month) async {
    final db = await database;
    return db.query('budgets', where: 'year = ? AND month = ?', whereArgs: [year, month]);
  }

  Future<void> setBudget(String category, double limit, int year, int month) async {
    final db  = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.rawInsert(
      'INSERT OR REPLACE INTO budgets(id, category, limit_amount, month, year, created_at) VALUES(?, ?, ?, ?, ?, ?)',
      ['${category}_${year}_$month', category, limit, month, year, now],
    );
  }

  Future<void> deleteBudget(String category, int year, int month) async {
    final db = await database;
    await db.delete('budgets',
        where: 'category = ? AND year = ? AND month = ?', whereArgs: [category, year, month]);
  }

  // DEBTS
  Future<List<Map<String, dynamic>>> getAllDebts() async {
    final db = await database;
    return db.query('debts', orderBy: 'is_paid ASC, due_date ASC');
  }

  Future<void> markDebtPaid(String id) async {
    final db = await database;
    await db.update('debts', {'is_paid': 1}, where: 'id = ?', whereArgs: [id]);
  }

  // STATS
  Future<Map<String, int>> getDatabaseStats() async {
    final db     = await database;
    final tables = [
      Tables.messages, Tables.memories, Tables.userNotes,
      Tables.financeTransactions, Tables.tasks, Tables.appointments,
      Tables.financialGoals, Tables.recurringTx, 'budgets', 'debts',
      Tables.habits, Tables.relationships, Tables.billSplits,
    ];
    final stats = <String, int>{};
    for (final t in tables) {
      final r = await db.rawQuery('SELECT COUNT(*) as c FROM $t');
      stats[t] = (r.first['c'] as int?) ?? 0;
    }
    return stats;
  }

  Future<void> clearAll() async {
    final db     = await database;
    final tables = [
      Tables.messages, Tables.memories, Tables.memoriesFts,
      Tables.userNotes, Tables.notesFts,
      Tables.financeTransactions, Tables.transactionsFts,
      Tables.assets, Tables.debts, Tables.tasks, Tables.appointments,
      Tables.financialGoals, Tables.recurringTx, 'budgets',
      Tables.habits, Tables.habitLogs, Tables.relationships, Tables.billSplits,
    ];
    for (final t in tables) { try { await db.delete(t); } catch (_) {} }
    _log.i('All tables cleared');
  }

  // HELPERS
  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
}
