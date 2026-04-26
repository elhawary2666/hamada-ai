// lib/features/finance/providers/finance_provider.dart

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';


import '../../../core/di/providers.dart';
import '../../../core/services/ai_service.dart';
import '../../../core/services/recurring_service.dart';

part 'finance_provider.g.dart';

// ── Models ────────────────────────────────────────────────────

class FinanceTransaction {
  final String  id, type, category;
  final double  amount;
  final String? description, aiCategory, recurringId;
  final int     date;
  final String  paymentMethod;
  final bool    isRecurring;

  const FinanceTransaction({
    required this.id, required this.type, required this.category,
    required this.amount, required this.date,
    this.description, this.aiCategory, this.recurringId,
    this.paymentMethod = 'cash', this.isRecurring = false,
  });

  bool get isIncome  => type == 'income';
  bool get isExpense => type == 'expense';

  factory FinanceTransaction.fromMap(Map<String, dynamic> m) => FinanceTransaction(
    id:            m['id']             as String,
    type:          m['type']           as String,
    amount:        (m['amount']        as num).toDouble(),
    category:      m['category']       as String,
    aiCategory:    m['ai_category']    as String?,
    description:   m['description']    as String?,
    date:          m['date']           as int,
    paymentMethod: m['payment_method'] as String? ?? 'cash',
    isRecurring:   (m['is_recurring']  as int? ?? 0) == 1,
    recurringId:   m['recurring_id']   as String?,
  );

  Map<String, dynamic> toMap() => {
    'id': id, 'type': type, 'amount': amount, 'currency': 'EGP',
    'category': category, 'ai_category': aiCategory ?? '',
    'description': description, 'date': date,
    'is_recurring': isRecurring ? 1 : 0,
    'recurring_id': recurringId,
    'payment_method': paymentMethod,
    'created_at': DateTime.now().millisecondsSinceEpoch,
  };
}

class MonthlySummary {
  final double income, expense;
  double get net         => income - expense;
  double get savingsRate => income > 0 ? (net / income) * 100 : 0;
  const MonthlySummary({required this.income, required this.expense});
}

class CategoryStat {
  final String category;
  final double total, percentage;
  final int    count;
  const CategoryStat({
    required this.category, required this.total,
    required this.count,    this.percentage = 0,
  });
}

// ── Financial Goal Model ──────────────────────────────────────

class FinancialGoal {
  final String  id, title, icon;
  final double  targetAmount, currentAmount;
  final String  category;
  final int?    deadline;
  final String? notes;
  final bool    isCompleted;
  final int     createdAt;

  const FinancialGoal({
    required this.id, required this.title, required this.targetAmount,
    required this.currentAmount, required this.createdAt,
    this.category = 'saving', this.deadline, this.notes,
    this.icon = '🎯', this.isCompleted = false,
  });

  double get progress => targetAmount > 0 ? (currentAmount / targetAmount).clamp(0.0, 1.0) : 0.0;
  int    get daysLeft => deadline != null
      ? DateTime.fromMillisecondsSinceEpoch(deadline!).difference(DateTime.now()).inDays
      : -1;

  factory FinancialGoal.fromMap(Map<String, dynamic> m) => FinancialGoal(
    id:            m['id']             as String,
    title:         m['title']          as String,
    targetAmount:  (m['target_amount'] as num).toDouble(),
    currentAmount: (m['current_amount'] as num).toDouble(),
    category:      m['category']       as String? ?? 'saving',
    deadline:      m['deadline']       as int?,
    notes:         m['notes']          as String?,
    icon:          m['icon']           as String? ?? '🎯',
    isCompleted:   (m['is_completed']  as int? ?? 0) == 1,
    createdAt:     m['created_at']     as int,
  );
}

// ── Recurring Transaction Model ───────────────────────────────

class RecurringTransaction {
  final String  id, title, type, category, frequency;
  final double  amount;
  final String? description, paymentMethod;
  final int     nextDue;
  final bool    isActive;

  const RecurringTransaction({
    required this.id, required this.title, required this.type,
    required this.category, required this.frequency,
    required this.amount, required this.nextDue,
    this.description, this.paymentMethod = 'cash', this.isActive = true,
  });

  bool get isExpense => type == 'expense';

  factory RecurringTransaction.fromMap(Map<String, dynamic> m) => RecurringTransaction(
    id:            m['id']             as String,
    title:         m['title']          as String,
    type:          m['type']           as String,
    amount:        (m['amount']        as num).toDouble(),
    category:      m['category']       as String,
    frequency:     m['frequency']      as String,
    nextDue:       m['next_due']       as int,
    description:   m['description']    as String?,
    paymentMethod: m['payment_method'] as String? ?? 'cash',
    isActive:      (m['is_active']     as int? ?? 1) == 1,
  );
}

// ── Finance State ─────────────────────────────────────────────

class FinanceState {
  final List<FinanceTransaction> transactions;
  final MonthlySummary?          monthlySummary;
  final List<CategoryStat>       categoryStats;
  final List<FinancialGoal>      goals;
  final List<RecurringTransaction> recurring;
  final Map<String, dynamic>?    debtSummary;
  final String?                  aiAnalysis;
  final bool isLoading, isClassifying, isAnalyzing;
  final int  selectedYear, selectedMonth;

  const FinanceState({
    this.transactions  = const [],
    this.monthlySummary,
    this.categoryStats = const [],
    this.goals         = const [],
    this.recurring     = const [],
    this.debtSummary,
    this.aiAnalysis,
    this.isLoading     = false,
    this.isClassifying = false,
    this.isAnalyzing   = false,
    required this.selectedYear,
    required this.selectedMonth,
  });

  FinanceState copyWith({
    List<FinanceTransaction>?    transactions,
    MonthlySummary?              monthlySummary,
    List<CategoryStat>?          categoryStats,
    List<FinancialGoal>?         goals,
    List<RecurringTransaction>?  recurring,
    Map<String, dynamic>?        debtSummary,
    String?                      aiAnalysis,
    bool? isLoading, bool? isClassifying, bool? isAnalyzing,
    int?  selectedYear, int? selectedMonth,
  }) => FinanceState(
    transactions:   transactions   ?? this.transactions,
    monthlySummary: monthlySummary ?? this.monthlySummary,
    categoryStats:  categoryStats  ?? this.categoryStats,
    goals:          goals          ?? this.goals,
    recurring:      recurring      ?? this.recurring,
    debtSummary:    debtSummary    ?? this.debtSummary,
    aiAnalysis:     aiAnalysis     ?? this.aiAnalysis,
    isLoading:      isLoading      ?? this.isLoading,
    isClassifying:  isClassifying  ?? this.isClassifying,
    isAnalyzing:    isAnalyzing    ?? this.isAnalyzing,
    selectedYear:   selectedYear   ?? this.selectedYear,
    selectedMonth:  selectedMonth  ?? this.selectedMonth,
  );
}

// ── Finance Notifier ──────────────────────────────────────────

@riverpod
class FinanceNotifier extends _$FinanceNotifier {
  final _uuid = const Uuid();

  @override
  FinanceState build() {
    final now = DateTime.now();
    final s   = FinanceState(selectedYear: now.year, selectedMonth: now.month);
    Future.microtask(_load);
    return s;
  }

  // ── LOAD ──────────────────────────────────────────────────

  Future<void> _load() async {
    state = state.copyWith(isLoading: true);
    try {
      await _processRecurring();
      await _loadAll();
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> _loadAll() async {
    final db   = ref.read(databaseHelperProvider);
    final y    = state.selectedYear;
    final m    = state.selectedMonth;

    final txRows  = await db.getTransactionsByMonth(y, m);
    final sumMap  = await db.getMonthSummary(y, m);
    final catMap  = await db.getCategoryTotals(y, m);
    final debt    = await db.getDebtSummary();
    final goalRows = await db.getFinancialGoals();
    final recRows  = await db.getRecurringTransactions();

    final txs   = txRows.map(FinanceTransaction.fromMap).toList();
    final sum   = MonthlySummary(
      income:  sumMap['income']  ?? 0.0,
      expense: sumMap['expense'] ?? 0.0,
    );

    final totalExpense = sum.expense > 0 ? sum.expense : 1.0;
    final cats = catMap.entries.map((e) => CategoryStat(
      category:   e.key,
      total:      e.value,
      count:      txs.where((t) => t.category == e.key && t.isExpense).length,
      percentage: e.value / totalExpense * 100,
    )).toList();

    final goals     = goalRows.map(FinancialGoal.fromMap).toList();
    final recurring = recRows.map(RecurringTransaction.fromMap).toList();

    state = state.copyWith(
      transactions:   txs,
      monthlySummary: sum,
      categoryStats:  cats,
      goals:          goals,
      recurring:      recurring,
      debtSummary:    debt,
    );
  }

  Future<void> _processRecurring() async {
    try {
      final svc = ref.read(recurringServiceProvider);
      final n   = await svc.processDueTransactions();
      if (n > 0) await _loadAll();
    } catch (_) {}
  }

  // ── TRANSACTIONS ──────────────────────────────────────────

  Future<void> addTransaction({
    required String type,
    required double amount,
    required String category,
    String? description,
    int? dateMs,
    String paymentMethod = 'cash',
  }) async {
    final db  = ref.read(databaseHelperProvider);
    final ai  = ref.read(aiServiceProvider);
    final now = DateTime.now().millisecondsSinceEpoch;

    // ✅ FIX P1: Optimistic update — only if viewing the current month
    final txDate  = dateMs != null ? DateTime.fromMillisecondsSinceEpoch(dateMs) : DateTime.now();
    final isCurrentMonthView = state.selectedYear  == txDate.year &&
                               state.selectedMonth == txDate.month;

    final tempTx = FinanceTransaction(
      id:            _uuid.v4(),
      type:          type,
      amount:        amount,
      category:      category,
      aiCategory:    category,
      description:   description,
      date:          dateMs ?? now,
      paymentMethod: paymentMethod,
    );

    // Update state instantly (user sees it right away — only for current month view)
    if (isCurrentMonthView) {
      final currentTxs = [tempTx, ...state.transactions];
      final newIncome  = state.monthlySummary?.income  ?? 0;
      final newExpense = state.monthlySummary?.expense ?? 0;
      final updatedSummary = MonthlySummary(
        income:  type == 'income'  ? newIncome  + amount : newIncome,
        expense: type == 'expense' ? newExpense + amount : newExpense,
      );
      state = state.copyWith(
        transactions:   currentTxs,
        monthlySummary: updatedSummary,
        isClassifying:  description != null && description.isNotEmpty,
      );
    } else {
      state = state.copyWith(
        isClassifying: description != null && description.isNotEmpty);
    }

    // Persist to DB
    await db.insert('finance_transactions', tempTx.toMap());

    // AI classification in background if description provided
    if (description != null && description.isNotEmpty) {
      final aiCategory = await ai.classifyFinanceTransaction(
          description: description, amount: amount);
      final cleanCat = aiCategory.trim().split('\n').first;

      // Update the saved record with AI category
      await db.update('finance_transactions',
          {'ai_category': cleanCat}, tempTx.id);

      state = state.copyWith(isClassifying: false);
    }

    // Full reload only for category stats (chart) — not the whole state
    await _reloadCategoryStats();
  }

  Future<void> _reloadCategoryStats() async {
    final db  = ref.read(databaseHelperProvider);
    final y   = state.selectedYear;
    final m   = state.selectedMonth;
    final catMap  = await db.getCategoryTotals(y, m);
    final expense = state.monthlySummary?.expense ?? 1.0;
    final cats = catMap.entries.map((e) => CategoryStat(
      category:   e.key,
      total:      e.value,
      count:      state.transactions
          .where((t) => t.category == e.key && t.isExpense).length,
      percentage: e.value / (expense > 0 ? expense : 1) * 100,
    )).toList();
    state = state.copyWith(categoryStats: cats);
  }

  Future<void> deleteTransaction(String id) async {
    final db = ref.read(databaseHelperProvider);
    await db.delete('finance_transactions', id);
    await _loadAll();
  }

  // ── AI ANALYSIS ───────────────────────────────────────────

  Future<void> runAiAnalysis() async {
    state = state.copyWith(isAnalyzing: true, aiAnalysis: null);
    try {
      final ai      = ref.read(aiServiceProvider);
      final analysis = await ai.analyzeFinances(
        year: state.selectedYear, month: state.selectedMonth);
      state = state.copyWith(isAnalyzing: false, aiAnalysis: analysis);
    } catch (e) {
      state = state.copyWith(isAnalyzing: false,
          aiAnalysis: 'حصل خطأ: ${e.toString()}');
    }
  }

  // ── GOALS ─────────────────────────────────────────────────

  Future<void> addGoal({
    required String title,
    required double targetAmount,
    String  category   = 'saving',
    String  icon       = '🎯',
    int?    deadline,
    String? notes,
  }) async {
    final db  = ref.read(databaseHelperProvider);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('financial_goals', {
      'id':             _uuid.v4(),
      'title':          title,
      'target_amount':  targetAmount,
      'current_amount': 0.0,
      'category':       category,
      'icon':           icon,
      'deadline':       deadline,
      'notes':          notes,
      'is_completed':   0,
      'created_at':     now,
      'updated_at':     now,
    });
    await _loadAll();
  }

  Future<void> addToGoal(String id, double amount) async {
    final db = ref.read(databaseHelperProvider);
    await db.addToGoal(id, amount);
    await _loadAll();
  }

  Future<void> deleteGoal(String id) async {
    final db = ref.read(databaseHelperProvider);
    await db.delete('financial_goals', id);
    await _loadAll();
  }

  // ── RECURRING ─────────────────────────────────────────────

  Future<void> addRecurring({
    required String title,
    required double amount,
    required String type,
    required String category,
    required String frequency,
    String? description,
    String  paymentMethod = 'cash',
  }) async {
    final db  = ref.read(databaseHelperProvider);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('recurring_transactions', {
      'id':             _uuid.v4(),
      'title':          title,
      'amount':         amount,
      'type':           type,
      'category':       category,
      'frequency':      frequency,
      'description':    description,
      'next_due':       now,
      'payment_method': paymentMethod,
      'is_active':      1,
      'created_at':     now,
    });
    await _loadAll();
  }

  Future<void> toggleRecurring(String id, bool active) async {
    final db = ref.read(databaseHelperProvider);
    await db.update('recurring_transactions', {'is_active': active ? 1 : 0}, id);
    await _loadAll();
  }

  Future<void> deleteRecurring(String id) async {
    final db = ref.read(databaseHelperProvider);
    await db.delete('recurring_transactions', id);
    await _loadAll();
  }

  // ── NAVIGATION ────────────────────────────────────────────

  Future<void> changeMonth(int year, int month) async {
    state = state.copyWith(selectedYear: year, selectedMonth: month, aiAnalysis: null);
    await _loadAll();
  }

  Future<void> refresh() => _load();
}
