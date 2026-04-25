// lib/core/database/database_helper.dart
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:logger/logger.dart';

const int _kDbVersion = 2;
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
    // Each PRAGMA wrapped individually — some devices don't support all of them
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
    // Each table created independently — one failure won't block the rest
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
  }

  // ─── TABLE DDL ────────────────────────────────────────────

  Future<void> _createMessages(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS ${Tables.messages}(
      id            TEXT PRIMARY KEY,
      session_id    TEXT NOT NULL,
      role          TEXT NOT NULL CHECK(role IN('user','assistant')),
      content       TEXT NOT NULL,
      timestamp     INTEGER NOT NULL,
      is_bookmarked INTEGER DEFAULT 0,
      metadata      TEXT DEFAULT '{}'
    )''');

  Future<void> _createMemories(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS ${Tables.memories}(
      id            TEXT PRIMARY KEY,
      content       TEXT NOT NULL,
      type          TEXT NOT NULL CHECK(type IN(
                      'fact','preference','goal','event',
                      'finance','health','relationship','note')),
      importance    INTEGER DEFAULT 5 CHECK(importance BETWEEN 1 AND 10),
      embedding     BLOB,
      embedding_dim INTEGER DEFAULT 0,
      source_msg_id TEXT,
      created_at    INTEGER NOT NULL,
      updated_at    INTEGER NOT NULL,
      last_accessed INTEGER,
      access_count  INTEGER DEFAULT 0,
      is_active     INTEGER DEFAULT 1,
      tags          TEXT DEFAULT '[]'
    )''');

  Future<void> _createNotes(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS ${Tables.userNotes}(
      id         TEXT PRIMARY KEY,
      title      TEXT,
      content    TEXT NOT NULL,
      tags       TEXT DEFAULT '[]',
      color      TEXT DEFAULT 'default',
      is_pinned  INTEGER DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )''');

  Future<void> _createTransactions(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS ${Tables.financeTransactions}(
      id             TEXT PRIMARY KEY,
      type           TEXT NOT NULL CHECK(type IN('income','expense')),
      amount         REAL NOT NULL CHECK(amount > 0),
      currency       TEXT DEFAULT 'EGP',
      category       TEXT NOT NULL,
      ai_category    TEXT DEFAULT '',
      description    TEXT,
      date           INTEGER NOT NULL,
      is_recurring   INTEGER DEFAULT 0,
      recurring_id   TEXT,
      payment_method TEXT DEFAULT 'cash',
      created_at     INTEGER NOT NULL
    )''');

  Future<void> _createAssets(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS ${Tables.assets}(
      id          TEXT PRIMARY KEY,
      name        TEXT NOT NULL,
      value       REAL NOT NULL,
      type        TEXT DEFAULT 'other',
      updated_at  INTEGER NOT NULL
    )''');

  Future<void> _createDebts(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS ${Tables.debts}(
      id          TEXT PRIMARY KEY,
      name        TEXT NOT NULL,
      amount      REAL NOT NULL,
      direction   TEXT NOT NULL CHECK(direction IN('owe','owed')),
      due_date    INTEGER,
      notes       TEXT,
      is_paid     INTEGER DEFAULT 0,
      created_at  INTEGER NOT NULL
    )''');


  Future<void> _createBudgets(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS budgets(
      id          TEXT PRIMARY KEY,
      category    TEXT NOT NULL UNIQUE,
      limit_amount REAL NOT NULL,
      month       INTEGER NOT NULL,
      year        INTEGER NOT NULL,
      created_at  INTEGER NOT NULL
    )''');

  Future<void> _createTasks(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS ${Tables.tasks}(
      id          TEXT PRIMARY KEY,
      title       TEXT NOT NULL,
      description TEXT,
      due_date    INTEGER,
      priority    TEXT DEFAULT 'medium',
      status      TEXT DEFAULT 'pending' CHECK(status IN('pending','done','cancelled')),
      created_at  INTEGER NOT NULL
    )''');

  Future<void> _createAppointments(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS ${Tables.appointments}(
      id          TEXT PRIMARY KEY,
      title       TEXT NOT NULL,
      description TEXT,
      start_time  INTEGER NOT NULL,
      end_time    INTEGER,
      location    TEXT,
      created_at  INTEGER NOT NULL
    )''');

  Future<void> _createFinancialGoals(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS ${Tables.financialGoals}(
      id             TEXT PRIMARY KEY,
      title          TEXT NOT NULL,
      target_amount  REAL NOT NULL CHECK(target_amount > 0),
      current_amount REAL NOT NULL DEFAULT 0,
      category       TEXT DEFAULT 'saving',
      deadline       INTEGER,
      notes          TEXT,
      icon           TEXT DEFAULT '🎯',
      is_completed   INTEGER DEFAULT 0,
      created_at     INTEGER NOT NULL,
      updated_at     INTEGER NOT NULL
    )''');

  Future<void> _createRecurringTx(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS ${Tables.recurringTx}(
      id             TEXT PRIMARY KEY,
      title          TEXT NOT NULL,
      amount         REAL NOT NULL CHECK(amount > 0),
      type           TEXT NOT NULL CHECK(type IN('income','expense')),
      category       TEXT NOT NULL,
      description    TEXT,
      frequency      TEXT NOT NULL CHECK(frequency IN('daily','weekly','monthly','yearly')),
      next_due       INTEGER NOT NULL,
      payment_method TEXT DEFAULT 'cash',
      is_active      INTEGER DEFAULT 1,
      created_at     INTEGER NOT NULL
    )''');

  Future<void> _createFts(DatabaseExecutor db) async {
    // Use simple tokenizer — unicode61 not available on all Android versions
    final ftsTables = [
      "CREATE VIRTUAL TABLE IF NOT EXISTS ${Tables.memoriesFts} USING fts4(content)",
      "CREATE VIRTUAL TABLE IF NOT EXISTS ${Tables.notesFts} USING fts4(title, content)",
      "CREATE VIRTUAL TABLE IF NOT EXISTS ${Tables.transactionsFts} USING fts4(description, category)",
    ];
    for (final sql in ftsTables) {
      try { await db.execute(sql); } catch (_) {}
    }
  }

  Future<void> _createIndexes(DatabaseExecutor db) async {
    final indexes = [
      'CREATE INDEX IF NOT EXISTS idx_messages_session   ON ${Tables.messages}(session_id, timestamp)',
      'CREATE INDEX IF NOT EXISTS idx_memories_type      ON ${Tables.memories}(type, importance DESC)',
      'CREATE INDEX IF NOT EXISTS idx_tx_date            ON ${Tables.financeTransactions}(date DESC)',
      'CREATE INDEX IF NOT EXISTS idx_tasks_due          ON ${Tables.tasks}(due_date, status)',
      'CREATE INDEX IF NOT EXISTS idx_goals_completed    ON ${Tables.financialGoals}(is_completed)',
      'CREATE INDEX IF NOT EXISTS idx_recurring_next_due ON ${Tables.recurringTx}(next_due)',
    ];
    for (final sql in indexes) {
      try { await db.execute(sql); } catch (_) {}
    }
  }

  // ─── GENERIC CRUD ─────────────────────────────────────────

  Future<void> insert(String table, Map<String, dynamic> row) async {
    final db = await database;
    await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
    _syncFts(table, row);
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
    return db.query(table, orderBy: orderBy, limit: limit,
        where: where, whereArgs: whereArgs);
  }

  void _syncFts(String table, Map<String, dynamic> row) {
    Future.microtask(() async {
      final db = await database;
      try {
        if (table == Tables.memories) {
          await db.insert(Tables.memoriesFts, {'content': row['content'] ?? ''},
              conflictAlgorithm: ConflictAlgorithm.replace);
        } else if (table == Tables.userNotes) {
          await db.insert(Tables.notesFts,
              {'title': row['title'] ?? '', 'content': row['content'] ?? ''},
              conflictAlgorithm: ConflictAlgorithm.replace);
        } else if (table == Tables.financeTransactions) {
          await db.insert(Tables.transactionsFts,
              {'description': row['description'] ?? '', 'category': row['category'] ?? ''},
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      } catch (_) {}
    });
  }

  // ─── MESSAGES ─────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getSessionMessages(String sessionId,
      {int? limit}) async {
    final db = await database;
    return db.query(Tables.messages,
        where: 'session_id = ?', whereArgs: [sessionId],
        orderBy: 'timestamp ASC',
        limit: limit);
  }

  Future<List<Map<String, dynamic>>> getDistinctSessions() async {
    final db = await database;
    return db.rawQuery(
        'SELECT session_id, MAX(timestamp) as last_ts, COUNT(*) as msg_count '
        'FROM ${Tables.messages} GROUP BY session_id ORDER BY last_ts DESC LIMIT 20');
  }

  // ─── MEMORIES ─────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> searchMemoriesFts(String q, {int limit = 20}) async {
    final db = await database;
    try {
      final ids = await db.rawQuery(
          'SELECT rowid FROM ${Tables.memoriesFts} WHERE content MATCH ? LIMIT ?',
          [q.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), ''), limit]);
      if (ids.isEmpty) return [];
      final rowIds = ids.map((r) => r['rowid']).toList();
      return db.query(Tables.memories,
          where: 'rowid IN (${List.filled(rowIds.length, '?').join(',')}) AND is_active = 1',
          whereArgs: rowIds,
          orderBy: 'importance DESC, last_accessed DESC',
          limit: limit);
    } catch (_) {
      return db.query(Tables.memories,
          where: 'content LIKE ? AND is_active = 1',
          whereArgs: ['%$q%'], limit: limit,
          orderBy: 'importance DESC');
    }
  }

  Future<List<Map<String, dynamic>>> getMemoriesByType(String type, {int limit = 8}) async {
    final db = await database;
    return db.query(Tables.memories,
        where: 'type = ? AND is_active = 1', whereArgs: [type],
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
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 90))
        .millisecondsSinceEpoch;
    return db.delete(Tables.memories,
        where: 'importance < 4 AND last_accessed < ? AND is_active = 1',
        whereArgs: [cutoff]);
  }

  // ─── NOTES ────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getAllNotes({int limit = 50}) async {
    final db = await database;
    return db.query(Tables.userNotes,
        orderBy: 'is_pinned DESC, updated_at DESC', limit: limit);
  }

  Future<List<Map<String, dynamic>>> searchNotes(String q) async {
    final db = await database;
    return db.query(Tables.userNotes,
        where: 'title LIKE ? OR content LIKE ?',
        whereArgs: ['%$q%', '%$q%'],
        orderBy: 'updated_at DESC');
  }

  // ─── FINANCE ──────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getTransactionsByMonth(int year, int month) async {
    final db = await database;
    final start = DateTime(year, month).millisecondsSinceEpoch;
    final end   = DateTime(year, month + 1).millisecondsSinceEpoch;
    return db.query(Tables.financeTransactions,
        where: 'date >= ? AND date < ?', whereArgs: [start, end],
        orderBy: 'date DESC');
  }

  Future<Map<String, double>> getCategoryTotals(int year, int month) async {
    final db    = await database;
    final start = DateTime(year, month).millisecondsSinceEpoch;
    final end   = DateTime(year, month + 1).millisecondsSinceEpoch;
    final rows  = await db.rawQuery(
        'SELECT category, SUM(amount) as total FROM ${Tables.financeTransactions} '
        'WHERE type=\'expense\' AND date>=? AND date<? GROUP BY category ORDER BY total DESC',
        [start, end]);
    return {for (final r in rows) r['category'] as String: (r['total'] as num).toDouble()};
  }

  Future<Map<String, double>> getMonthSummary(int year, int month) async {
    final db    = await database;
    final start = DateTime(year, month).millisecondsSinceEpoch;
    final end   = DateTime(year, month + 1).millisecondsSinceEpoch;
    final income = await db.rawQuery(
        'SELECT COALESCE(SUM(amount),0) as t FROM ${Tables.financeTransactions} WHERE type=\'income\' AND date>=? AND date<?',
        [start, end]);
    final expense = await db.rawQuery(
        'SELECT COALESCE(SUM(amount),0) as t FROM ${Tables.financeTransactions} WHERE type=\'expense\' AND date>=? AND date<?',
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

  // ─── FINANCIAL GOALS ──────────────────────────────────────

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

  // ─── RECURRING TRANSACTIONS ───────────────────────────────

  Future<List<Map<String, dynamic>>> getRecurringTransactions({bool activeOnly = true}) async {
    final db = await database;
    return db.query(Tables.recurringTx,
        where: activeOnly ? 'is_active = 1' : null,
        orderBy: 'next_due ASC');
  }

  Future<List<Map<String, dynamic>>> getDueRecurringTransactions() async {
    final db  = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.query(Tables.recurringTx,
        where: 'is_active = 1 AND next_due <= ?', whereArgs: [now]);
  }

  Future<void> updateRecurringNextDue(String id, int nextDue) async {
    final db = await database;
    await db.update(Tables.recurringTx, {'next_due': nextDue},
        where: 'id = ?', whereArgs: [id]);
  }

  // ─── TASKS ────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getTodayTasks() async {
    final db    = await database;
    final start = DateTime.now().copyWith(hour: 0,  minute: 0,  second: 0).millisecondsSinceEpoch;
    final end   = DateTime.now().copyWith(hour: 23, minute: 59, second: 59).millisecondsSinceEpoch;
    return db.query(Tables.tasks,
        where: 'due_date >= ? AND due_date <= ? AND status != ?',
        whereArgs: [start, end, 'cancelled'],
        orderBy: 'priority DESC, due_date ASC');
  }

  Future<List<Map<String, dynamic>>> getAllTasks({String? statusFilter}) async {
    final db = await database;
    return db.query(Tables.tasks,
        where: statusFilter != null ? 'status = ?' : null,
        whereArgs: statusFilter != null ? [statusFilter] : null,
        orderBy: 'status ASC, priority DESC, due_date ASC');
  }

  Future<Map<String, dynamic>?> getTopTodayTask() async {
    final tasks = await getTodayTasks();
    if (tasks.isEmpty) return null;
    return tasks.first;
  }

  // ─── APPOINTMENTS ─────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getUpcomingAppointments({int withinDays = 7}) async {
    final db  = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final end = DateTime.now().add(Duration(days: withinDays)).millisecondsSinceEpoch;
    return db.query(Tables.appointments,
        where: 'start_time >= ? AND start_time <= ?', whereArgs: [now, end],
        orderBy: 'start_time ASC');
  }

  // ─── STATS ────────────────────────────────────────────────

  Future<Map<String, int>> getDatabaseStats() async {
    final db = await database;
    final tables = [
      Tables.messages, Tables.memories, Tables.userNotes,
      Tables.financeTransactions, Tables.tasks, Tables.appointments,
      Tables.financialGoals, Tables.recurringTx, 'budgets', 'debts',
    ];
    final stats = <String, int>{};
    for (final t in tables) {
      final r = await db.rawQuery('SELECT COUNT(*) as c FROM $t');
      stats[t] = (r.first['c'] as int?) ?? 0;
    }
    return stats;
  }


  // ─── BUDGETS ──────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getBudgets(int year, int month) async {
    final db = await database;
    return db.query('budgets',
        where: 'year = ? AND month = ?', whereArgs: [year, month]);
  }

  Future<void> setBudget(String category, double limit, int year, int month) async {
    final db  = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.rawInsert(
      '''INSERT OR REPLACE INTO budgets(id, category, limit_amount, month, year, created_at)
         VALUES(?, ?, ?, ?, ?, ?)''',
      ['${category}_${year}_$month',
       category, limit, month, year, now],
    );
  }

  Future<void> deleteBudget(String category, int year, int month) async {
    final db = await database;
    await db.delete('budgets',
        where: 'category = ? AND year = ? AND month = ?',
        whereArgs: [category, year, month]);
  }

  // ─── DEBTS ────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getAllDebts() async {
    final db = await database;
    return db.query('debts', orderBy: 'is_paid ASC, due_date ASC');
  }

  Future<void> markDebtPaid(String id) async {
    final db = await database;
    await db.update('debts', {'is_paid': 1}, where: 'id = ?', whereArgs: [id]);
  }

  // ─── CLEAR ALL ────────────────────────────────────────────

  Future<void> clearAll() async {
    final db = await database;
    final tables = [
      Tables.messages, Tables.memories, Tables.memoriesFts,
      Tables.userNotes, Tables.notesFts,
      Tables.financeTransactions, Tables.transactionsFts,
      Tables.assets, Tables.debts, Tables.tasks, Tables.appointments,
      Tables.financialGoals, Tables.recurringTx, 'budgets', 'debts',
    ];
    for (final t in tables) { try { await db.delete(t); } catch (_) {} }
    _log.i('🗑️ All tables cleared');
  }

  // ─── EXTRA TASK QUERIES ───────────────────────────────────
  Future<List<Map<String, dynamic>>> getOverdueTasks() async {
    final db  = await database;
    final today = DateTime.now().copyWith(hour: 0, minute: 0, second: 0).millisecondsSinceEpoch;
    return db.query(Tables.tasks,
        where: 'due_date < ? AND due_date > 0 AND status = ?',
        whereArgs: [today, 'pending'],
        orderBy: 'due_date ASC');
  }
}
