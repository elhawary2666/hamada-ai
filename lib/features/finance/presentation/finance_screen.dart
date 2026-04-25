// lib/features/finance/presentation/finance_screen.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui show TextDirection;
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart' show MarkdownBody, MarkdownStyleSheet;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';


import '../../../core/theme/app_colors.dart';
import '../providers/finance_provider.dart';

const _months = [
  'يناير','فبراير','مارس','أبريل','مايو','يونيو',
  'يوليو','أغسطس','سبتمبر','أكتوبر','نوفمبر','ديسمبر',
];

class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state    = ref.watch(financeNotifierProvider);
    final notifier = ref.read(financeNotifierProvider.notifier);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          title: Text('💰 حساباتي', style: GoogleFonts.cairo(
              fontSize: 18, fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              color: AppColors.textSecondary,
              onPressed: notifier.refresh,
            ),
          ],
          bottom: TabBar(
            labelStyle:       GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
            unselectedLabelStyle: GoogleFonts.cairo(fontSize: 13),
            labelColor:       AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor:   AppColors.primary,
            tabs: const [
              Tab(text: 'الحركات'),
              Tab(text: 'الأهداف'),
              Tab(text: 'المتكررة'),
            ],
          ),
        ),
        body: state.isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : TabBarView(children: [
                _TransactionsTab(state: state, notifier: notifier),
                _GoalsTab(state: state, notifier: notifier),
                _RecurringTab(state: state, notifier: notifier),
              ]),
        floatingActionButton: _AddFab(state: state, notifier: notifier),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// TAB 1: TRANSACTIONS
// ════════════════════════════════════════════════════════════

class _TransactionsTab extends StatelessWidget {
  const _TransactionsTab({required this.state, required this.notifier});
  final FinanceState    state;
  final FinanceNotifier notifier;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      _MonthSelector(state: state, notifier: notifier),
      const Gap(12),
      _SummaryCards(state: state),
      const Gap(12),
      if (state.categoryStats.isNotEmpty) ...[
        _PieChartCard(state: state),
        const Gap(12),
      ],
      _AiAnalysisCard(state: state, notifier: notifier),
      const Gap(12),
      if (state.transactions.isEmpty)
        _EmptyState(msg: 'مفيش معاملات في الشهر ده')
      else ...[
        Text('آخر الحركات',
            style: GoogleFonts.cairo(
                fontSize: 13, color: AppColors.textSecondary)),
        const Gap(8),
        ...state.transactions.take(30).map(
              (tx) => _TxTile(tx: tx, onDelete: () => notifier.deleteTransaction(tx.id)),
            ),
      ],
      const Gap(80),
    ],
  );
}

class _MonthSelector extends StatelessWidget {
  const _MonthSelector({required this.state, required this.notifier});
  final FinanceState    state;
  final FinanceNotifier notifier;

  @override
  Widget build(BuildContext context) => Row(children: [
    IconButton(
      icon: const Icon(Icons.chevron_left),
      color: AppColors.textSecondary,
      onPressed: () {
        var m = state.selectedMonth - 1;
        var y = state.selectedYear;
        if (m < 1) { m = 12; y--; }
        notifier.changeMonth(y, m);
      },
    ),
    Expanded(child: Text(
      '${_months[state.selectedMonth - 1]} ${state.selectedYear}',
      textAlign: TextAlign.center,
      style: GoogleFonts.cairo(
          fontSize: 16, fontWeight: FontWeight.bold,
          color: AppColors.textPrimary),
    )),
    IconButton(
      icon: const Icon(Icons.chevron_right),
      color: AppColors.textSecondary,
      onPressed: () {
        var m = state.selectedMonth + 1;
        var y = state.selectedYear;
        if (m > 12) { m = 1; y++; }
        notifier.changeMonth(y, m);
      },
    ),
  ]);
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.state});
  final FinanceState state;

  @override
  Widget build(BuildContext context) {
    final sum = state.monthlySummary;
    if (sum == null) return const SizedBox.shrink();
    final net     = sum.net;
    final netColor = net >= 0 ? AppColors.income : AppColors.expense;
    return Row(children: [
      Expanded(child: _StatCard(
          label: 'الدخل', value: sum.income,
          color: AppColors.income, icon: Icons.arrow_downward)),
      const Gap(8),
      Expanded(child: _StatCard(
          label: 'المصروف', value: sum.expense,
          color: AppColors.expense, icon: Icons.arrow_upward)),
      const Gap(8),
      Expanded(child: _StatCard(
          label: 'الصافي', value: net,
          color: netColor, icon: Icons.account_balance_wallet_outlined)),
    ]);
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label, required this.value,
    required this.color, required this.icon});
  final String    label;
  final double    value;
  final Color     color;
  final IconData  icon;

  @override
  Widget build(BuildContext context) => Container(
    padding:    const EdgeInsets.all(12),
    decoration: BoxDecoration(
        color:        AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.inputBorder, width: 0.5)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 12, color: color),
        const Gap(4),
        Text(label, style: GoogleFonts.cairo(
            fontSize: 11, color: AppColors.textSecondary)),
      ]),
      const Gap(4),
      Text(
        NumberFormat('#,###').format(value.abs()),
        style: GoogleFonts.cairo(
            fontSize: 16, fontWeight: FontWeight.bold, color: color),
      ),
      Text('ج.م', style: GoogleFonts.cairo(
          fontSize: 10, color: AppColors.textHint)),
    ]),
  );
}

class _PieChartCard extends StatefulWidget {
  const _PieChartCard({required this.state});
  final FinanceState state;
  @override
  State<_PieChartCard> createState() => _PieChartCardState();
}

class _PieChartCardState extends State<_PieChartCard> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final cats = widget.state.categoryStats.take(6).toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.inputBorder, width: 0.5)),
      child: Column(children: [
        Text('توزيع المصروفات',
            style: GoogleFonts.cairo(
                fontSize: 13, fontWeight: FontWeight.bold,
                color: AppColors.textSecondary)),
        const Gap(12),
        SizedBox(
          height: 180,
          child: PieChart(PieChartData(
            sections: List.generate(cats.length, (i) {
              final cat = cats[i];
              final isTouched = i == _touched;
              return PieChartSectionData(
                color:         AppColors.chartColors[i % AppColors.chartColors.length],
                value:         cat.total,
                title:         isTouched ? '${cat.percentage.toStringAsFixed(0)}%' : '',
                radius:        isTouched ? 60 : 50,
                titleStyle:    const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold,
                    color: Colors.white),
              );
            }),
            pieTouchData: PieTouchData(
              touchCallback: (FlTouchEvent e, PieTouchResponse? r) {
                setState(() {
                  _touched = (e is FlTapUpEvent || e is FlPointerExitEvent)
                      ? -1
                      : r?.touchedSection?.touchedSectionIndex ?? -1;
                });
              },
            ),
            borderData:    FlBorderData(show: false),
            sectionsSpace: 2,
            centerSpaceRadius: 35,
          )),
        ),
        const Gap(8),
        Wrap(spacing: 8, runSpacing: 6, children: List.generate(cats.length, (i) {
          final cat = cats[i];
          return Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10,
                decoration: BoxDecoration(
                    color:  AppColors.chartColors[i % AppColors.chartColors.length],
                    shape:  BoxShape.circle)),
            const Gap(4),
            Text('${cat.category} • ${NumberFormat('#,###').format(cat.total)}',
                style: GoogleFonts.cairo(
                    fontSize: 11, color: AppColors.textSecondary)),
          ]);
        })),
      ]),
    );
  }
}

class _AiAnalysisCard extends StatelessWidget {
  const _AiAnalysisCard({required this.state, required this.notifier});
  final FinanceState    state;
  final FinanceNotifier notifier;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.primary.withOpacity(0.3), width: 1)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.psychology_outlined,
            size: 16, color: AppColors.primary),
        const Gap(6),
        Text('تحليل مالي ذكي',
            style: GoogleFonts.cairo(
                fontSize: 13, fontWeight: FontWeight.bold,
                color: AppColors.primary)),
        const Spacer(),
        if (!state.isAnalyzing)
          TextButton(
            onPressed: notifier.runAiAnalysis,
            child: Text('حلّل الشهر',
                style: GoogleFonts.cairo(
                    fontSize: 12, color: AppColors.primary)),
          ),
      ]),
      if (state.isAnalyzing) ...[
        const Gap(8),
        const LinearProgressIndicator(color: AppColors.primary),
        const Gap(4),
        Text('حماده بيحلل ماليتك...',
            style: GoogleFonts.cairo(
                fontSize: 11, color: AppColors.textSecondary)),
      ] else if (state.aiAnalysis != null) ...[
        const Divider(color: AppColors.inputBorder, height: 16),
        MarkdownBody(
          data: state.aiAnalysis!,
          styleSheet: MarkdownStyleSheet(
            p: GoogleFonts.cairo(
                color: AppColors.textPrimary,
                fontSize: 13, height: 1.6),
            strong: GoogleFonts.cairo(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
      ] else ...[
        const Gap(4),
        Text('اضغط "حلّل الشهر" وحماده يقولك إيه اللي بيحصل في ماليتك',
            style: GoogleFonts.cairo(
                fontSize: 12, color: AppColors.textSecondary)),
      ],
    ]),
  );
}

class _TxTile extends StatelessWidget {
  const _TxTile({required this.tx, required this.onDelete});
  final FinanceTransaction tx;
  final VoidCallback       onDelete;

  @override
  Widget build(BuildContext context) => Dismissible(
    key:        ValueKey(tx.id),
    direction:  DismissDirection.endToStart,
    onDismissed: (_) { onDelete(); HapticFeedback.mediumImpact(); },
    background: Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 16),
      color: AppColors.error.withOpacity(0.2),
      child: const Icon(Icons.delete_outline, color: AppColors.error),
    ),
    child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color:        AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.inputBorder, width: 0.5)),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
              color: (tx.isIncome ? AppColors.income : AppColors.expense)
                  .withOpacity(0.15),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(
              tx.isIncome ? Icons.arrow_downward : Icons.arrow_upward,
              size: 16,
              color: tx.isIncome ? AppColors.income : AppColors.expense),
        ),
        const Gap(10),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tx.description ?? tx.category,
              style: GoogleFonts.cairo(
                  fontSize: 13, color: AppColors.textPrimary),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          Row(children: [
            Text(tx.category,
                style: GoogleFonts.cairo(
                    fontSize: 11, color: AppColors.textSecondary)),
            if (tx.isRecurring) ...[
              const Gap(4),
              const Icon(Icons.repeat, size: 10,
                  color: AppColors.textHint),
            ],
          ]),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            '${tx.isIncome ? '+' : '-'}${NumberFormat('#,###').format(tx.amount)}',
            style: GoogleFonts.cairo(
                fontSize: 14, fontWeight: FontWeight.bold,
                color: tx.isIncome ? AppColors.income : AppColors.expense),
          ),
          Text(
            DateFormat('dd/MM').format(
                DateTime.fromMillisecondsSinceEpoch(tx.date)),
            style: GoogleFonts.cairo(
                fontSize: 10, color: AppColors.textHint),
          ),
        ]),
      ]),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.msg});
  final String msg;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.account_balance_wallet_outlined,
            size: 48, color: AppColors.textHint),
        const Gap(12),
        Text(msg, style: GoogleFonts.cairo(
            color: AppColors.textSecondary, fontSize: 14)),
      ]),
    ),
  );
}

// ════════════════════════════════════════════════════════════
// TAB 2: GOALS
// ════════════════════════════════════════════════════════════

class _GoalsTab extends StatelessWidget {
  const _GoalsTab({required this.state, required this.notifier});
  final FinanceState    state;
  final FinanceNotifier notifier;

  @override
  Widget build(BuildContext context) {
    if (state.goals.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.flag_outlined, size: 48, color: AppColors.textHint),
        const Gap(12),
        Text('مفيش أهداف لسه',
            style: GoogleFonts.cairo(
                color: AppColors.textSecondary, fontSize: 14)),
        const Gap(8),
        Text('اضغط + عشان تضيف هدف مالي',
            style: GoogleFonts.cairo(
                color: AppColors.textHint, fontSize: 12)),
      ]));
    }

    return ListView(padding: const EdgeInsets.all(12), children: [
      ...state.goals.map((g) => _GoalCard(
            goal: g, notifier: notifier,
          ).animate().fadeIn(duration: 200.ms)),
      const Gap(80),
    ]);
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, required this.notifier});
  final FinancialGoal   goal;
  final FinanceNotifier notifier;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: goal.isCompleted
                ? AppColors.success.withOpacity(0.5)
                : AppColors.inputBorder,
            width: goal.isCompleted ? 1.5 : 0.5)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(goal.icon,
            style: const TextStyle(fontSize: 22)),
        const Gap(10),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(goal.title,
              style: GoogleFonts.cairo(
                  fontSize: 15, fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary)),
          if (goal.deadline != null)
            Text(
              goal.daysLeft >= 0
                  ? 'متبقي ${goal.daysLeft} يوم'
                  : 'انتهت المدة',
              style: GoogleFonts.cairo(
                  fontSize: 11,
                  color: goal.daysLeft > 30
                      ? AppColors.textSecondary
                      : AppColors.warning),
            ),
        ])),
        if (goal.isCompleted)
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6)),
            child: Text('مكتمل ✅',
                style: GoogleFonts.cairo(
                    fontSize: 11, color: AppColors.success)),
          )
        else
          IconButton(
            icon: const Icon(Icons.add_circle_outline,
                color: AppColors.primary, size: 20),
            tooltip: 'أضف مبلغ',
            onPressed: () => _showAddAmountDialog(context),
          ),
        IconButton(
          icon: const Icon(Icons.delete_outline,
              color: AppColors.textHint, size: 18),
          onPressed: () => notifier.deleteGoal(goal.id),
        ),
      ]),
      const Gap(10),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${NumberFormat('#,###').format(goal.currentAmount)} ج.م',
            style: GoogleFonts.cairo(
                fontSize: 13, color: AppColors.primary,
                fontWeight: FontWeight.bold),
          ),
          Text(
            'من ${NumberFormat('#,###').format(goal.targetAmount)} ج.م',
            style: GoogleFonts.cairo(
                fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
      const Gap(6),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: goal.progress,
          backgroundColor: AppColors.surfaceVariant,
          color: goal.isCompleted ? AppColors.success : AppColors.primary,
          minHeight: 8,
        ),
      ),
      const Gap(4),
      Text(
        '${(goal.progress * 100).toStringAsFixed(0)}%',
        style: GoogleFonts.cairo(
            fontSize: 11, color: AppColors.textHint),
      ),
    ]),
  );

  void _showAddAmountDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('أضف للهدف', style: GoogleFonts.cairo(
            color: AppColors.textPrimary)),
        content: TextField(
          controller:   ctrl,
          keyboardType: TextInputType.number,
          textDirection: ui.TextDirection.ltr,
          decoration: InputDecoration(
            hintText: 'المبلغ بالجنيه',
            hintStyle: GoogleFonts.cairo(color: AppColors.textHint),
            suffixText: 'ج.م',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء', style: GoogleFonts.cairo())),
          TextButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text);
              if (v != null && v > 0) {
                notifier.addToGoal(goal.id, v);
                Navigator.pop(context);
              }
            },
            child: Text('أضف',
                style: GoogleFonts.cairo(color: AppColors.success))),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// TAB 3: RECURRING
// ════════════════════════════════════════════════════════════

class _RecurringTab extends StatelessWidget {
  const _RecurringTab({required this.state, required this.notifier});
  final FinanceState    state;
  final FinanceNotifier notifier;

  @override
  Widget build(BuildContext context) {
    if (state.recurring.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.repeat_outlined,
            size: 48, color: AppColors.textHint),
        const Gap(12),
        Text('مفيش مصروفات متكررة لسه',
            style: GoogleFonts.cairo(
                color: AppColors.textSecondary, fontSize: 14)),
        const Gap(8),
        Text('اضغط + عشان تضيف مصروف أو دخل متكرر',
            style: GoogleFonts.cairo(
                color: AppColors.textHint, fontSize: 12)),
      ]));
    }

    return ListView(padding: const EdgeInsets.all(12), children: [
      ...state.recurring.map((r) => _RecurringTile(
            rec: r, notifier: notifier,
          ).animate().fadeIn(duration: 200.ms)),
      const Gap(80),
    ]);
  }
}

class _RecurringTile extends StatelessWidget {
  const _RecurringTile({required this.rec, required this.notifier});
  final RecurringTransaction rec;
  final FinanceNotifier      notifier;

  @override
  Widget build(BuildContext context) {
    final nextDue  = DateTime.fromMillisecondsSinceEpoch(rec.nextDue);
    final daysLeft = nextDue.difference(DateTime.now()).inDays;
    final freqAr   = _freqAr(rec.frequency);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color:        AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.inputBorder, width: 0.5)),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
              color: (rec.isExpense ? AppColors.expense : AppColors.income)
                  .withOpacity(0.12),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.repeat,
              size: 18,
              color: rec.isExpense ? AppColors.expense : AppColors.income),
        ),
        const Gap(10),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(rec.title,
              style: GoogleFonts.cairo(
                  fontSize: 13, color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500)),
          Row(children: [
            Text('$freqAr • ${rec.category}',
                style: GoogleFonts.cairo(
                    fontSize: 11, color: AppColors.textSecondary)),
            if (daysLeft <= 3 && daysLeft >= 0) ...[
              const Gap(6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4)),
                child: Text(daysLeft == 0 ? 'اليوم!' : 'باقي $daysLeft أيام',
                    style: GoogleFonts.cairo(
                        fontSize: 10, color: AppColors.warning)),
              ),
            ],
          ]),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            '${rec.isExpense ? '-' : '+'}${NumberFormat('#,###').format(rec.amount)}',
            style: GoogleFonts.cairo(
                fontSize: 14, fontWeight: FontWeight.bold,
                color: rec.isExpense ? AppColors.expense : AppColors.income),
          ),
          Text('ج.م', style: GoogleFonts.cairo(
              fontSize: 10, color: AppColors.textHint)),
        ]),
        const Gap(4),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert,
              size: 18, color: AppColors.textHint),
          color: AppColors.surface,
          onSelected: (v) {
            if (v == 'toggle') {
              notifier.toggleRecurring(rec.id, !rec.isActive);
            } else if (v == 'delete') {
              notifier.deleteRecurring(rec.id);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'toggle', child: Text(
                rec.isActive ? 'إيقاف مؤقت' : 'تفعيل',
                style: GoogleFonts.cairo(
                    color: AppColors.textPrimary))),
            PopupMenuItem(value: 'delete', child: Text(
                'حذف',
                style: GoogleFonts.cairo(color: AppColors.error))),
          ],
        ),
      ]),
    );
  }

  String _freqAr(String f) {
    switch (f) {
      case 'daily':   return 'يومياً';
      case 'weekly':  return 'أسبوعياً';
      case 'monthly': return 'شهرياً';
      case 'yearly':  return 'سنوياً';
      default:        return f;
    }
  }
}

// ════════════════════════════════════════════════════════════
// FLOATING ACTION BUTTON
// ════════════════════════════════════════════════════════════

class _AddFab extends StatelessWidget {
  const _AddFab({required this.state, required this.notifier});
  final FinanceState    state;
  final FinanceNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final tabCtrl = DefaultTabController.of(context);
    return AnimatedBuilder(
      animation: tabCtrl,
      builder: (_, __) => FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed:       () => _onAdd(context, tabCtrl.index),
        icon:  state.isClassifying
            ? const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.add, color: Colors.white),
        label: Text(
          tabCtrl.index == 0
              ? 'إضافة معاملة'
              : tabCtrl.index == 1
                  ? 'إضافة هدف'
                  : 'إضافة متكرر',
          style: GoogleFonts.cairo(
              color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  void _onAdd(BuildContext context, int tabIndex) {
    if (tabIndex == 0) {
      _showAddTxSheet(context);
    } else if (tabIndex == 1) {
      _showAddGoalSheet(context);
    } else {
      _showAddRecurringSheet(context);
    }
  }

  // ── Add Transaction Sheet ─────────────────────────────────

  void _showAddTxSheet(BuildContext context) {
    final amountCtrl = TextEditingController();
    final descCtrl   = TextEditingController();
    String type      = 'expense';
    String category  = 'طعام';
    String payment   = 'cash';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor:    AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (_, setSt) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4,
                decoration: BoxDecoration(
                    color: AppColors.textHint,
                    borderRadius: BorderRadius.circular(2))),
            const Gap(16),
            Text('معاملة جديدة',
                style: GoogleFonts.cairo(
                    fontSize: 16, fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            const Gap(16),
            // Type toggle
            Row(children: ['expense', 'income'].map((t) => Expanded(
              child: GestureDetector(
                onTap: () => setSt(() => type = t),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                      color: type == t
                          ? (t == 'expense'
                              ? AppColors.expense.withOpacity(0.2)
                              : AppColors.income.withOpacity(0.2))
                          : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: type == t
                              ? (t == 'expense'
                                  ? AppColors.expense
                                  : AppColors.income)
                              : Colors.transparent)),
                  child: Text(
                    t == 'expense' ? 'مصروف' : 'دخل',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        color: type == t
                            ? (t == 'expense'
                                ? AppColors.expense
                                : AppColors.income)
                            : AppColors.textSecondary),
                  ),
                ),
              ),
            )).toList()),
            const Gap(12),
            TextField(
              controller:    amountCtrl,
              keyboardType:  TextInputType.number,
              textDirection: ui.TextDirection.ltr,
              style: GoogleFonts.cairo(
                  fontSize: 22, fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText:  '0.00',
                suffixText: 'ج.م',
                hintStyle: GoogleFonts.cairo(
                    color: AppColors.textHint, fontSize: 22),
              ),
            ),
            const Gap(8),
            TextField(
              controller: descCtrl,
              textDirection: ui.TextDirection.rtl,
              style: GoogleFonts.cairo(
                  fontSize: 14, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'وصف (اختياري) — حماده هيصنّفه تلقائياً',
                hintStyle: GoogleFonts.cairo(
                    color: AppColors.textHint, fontSize: 13),
              ),
            ),
            const Gap(8),
            DropdownButtonFormField<String>(
              value:        category,
              dropdownColor: AppColors.surface,
              style:        GoogleFonts.cairo(
                  color: AppColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                labelText:  'الفئة',
                labelStyle: GoogleFonts.cairo(
                    color: AppColors.textSecondary),
              ),
              items: ['طعام','مواصلات','ترفيه','فواتير','صحة',
                      'ملابس','تعليم','إيجار','راتب','غير ذلك']
                  .map((c) => DropdownMenuItem(value: c,
                      child: Text(c, style: GoogleFonts.cairo(
                          color: AppColors.textPrimary))))
                  .toList(),
              onChanged: (v) => setSt(() => category = v!),
            ),
            const Gap(16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () {
                  final amount = double.tryParse(amountCtrl.text);
                  if (amount == null || amount <= 0) return;
                  Navigator.pop(ctx);
                  notifier.addTransaction(
                    type:        type,
                    amount:      amount,
                    category:    category,
                    description: descCtrl.text.trim().isEmpty
                        ? null
                        : descCtrl.text.trim(),
                    paymentMethod: payment,
                  );
                },
                child: Text('إضافة',
                    style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Add Goal Sheet ────────────────────────────────────────

  void _showAddGoalSheet(BuildContext context) {
    final titleCtrl  = TextEditingController();
    final targetCtrl = TextEditingController();
    String icon      = '🎯';
    DateTime? deadline;

    final icons = ['🎯','🏠','🚗','✈️','📱','💍','🎓','💊','🏋️','💰'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor:    AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (_, setSt) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4,
                decoration: BoxDecoration(
                    color: AppColors.textHint,
                    borderRadius: BorderRadius.circular(2))),
            const Gap(16),
            Text('هدف مالي جديد',
                style: GoogleFonts.cairo(
                    fontSize: 16, fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            const Gap(12),
            // Icon selector
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: icons.map((ic) => GestureDetector(
                  onTap: () => setSt(() => icon = ic),
                  child: Container(
                    width: 40, height: 40,
                    margin: const EdgeInsets.only(left: 6),
                    decoration: BoxDecoration(
                        color: icon == ic
                            ? AppColors.primary.withOpacity(0.2)
                            : AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: icon == ic
                                ? AppColors.primary
                                : Colors.transparent)),
                    child: Center(child: Text(ic,
                        style: const TextStyle(fontSize: 20))),
                  ),
                )).toList(),
              ),
            ),
            const Gap(10),
            TextField(
              controller: titleCtrl,
              textDirection: ui.TextDirection.rtl,
              style: GoogleFonts.cairo(
                  fontSize: 14, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'اسم الهدف (مثال: شراء لاب توب)',
                hintStyle: GoogleFonts.cairo(
                    color: AppColors.textHint, fontSize: 13),
              ),
            ),
            const Gap(8),
            TextField(
              controller:   targetCtrl,
              keyboardType: TextInputType.number,
              textDirection: ui.TextDirection.ltr,
              style: GoogleFonts.cairo(
                  fontSize: 14, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'المبلغ المستهدف بالجنيه',
                hintStyle: GoogleFonts.cairo(
                    color: AppColors.textHint, fontSize: 13),
                suffixText: 'ج.م',
              ),
            ),
            const Gap(8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                deadline == null
                    ? 'تاريخ الانتهاء (اختياري)'
                    : DateFormat('yyyy/MM/dd').format(deadline!),
                style: GoogleFonts.cairo(
                    fontSize: 13,
                    color: deadline == null
                        ? AppColors.textHint
                        : AppColors.textPrimary),
              ),
              trailing: const Icon(Icons.calendar_today_outlined,
                  color: AppColors.textSecondary, size: 18),
              onTap: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: DateTime.now().add(
                      const Duration(days: 30)),
                  firstDate: DateTime.now(),
                  lastDate:  DateTime.now().add(
                      const Duration(days: 3650)),
                  builder: (_, child) => Theme(
                    data: ThemeData.dark(), child: child!),
                );
                if (d != null) setSt(() => deadline = d);
              },
            ),
            const Gap(12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () {
                  final title  = titleCtrl.text.trim();
                  final target = double.tryParse(targetCtrl.text);
                  if (title.isEmpty || target == null || target <= 0) return;
                  Navigator.pop(ctx);
                  notifier.addGoal(
                    title:        title,
                    targetAmount: target,
                    icon:         icon,
                    deadline:     deadline?.millisecondsSinceEpoch,
                  );
                },
                child: Text('إضافة الهدف',
                    style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Add Recurring Sheet ───────────────────────────────────

  void _showAddRecurringSheet(BuildContext context) {
    final titleCtrl  = TextEditingController();
    final amountCtrl = TextEditingController();
    String type      = 'expense';
    String category  = 'فواتير';
    String frequency = 'monthly';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor:    AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (_, setSt) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4,
                decoration: BoxDecoration(
                    color: AppColors.textHint,
                    borderRadius: BorderRadius.circular(2))),
            const Gap(16),
            Text('معاملة متكررة جديدة',
                style: GoogleFonts.cairo(
                    fontSize: 16, fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            const Gap(12),
            Row(children: ['expense', 'income'].map((t) => Expanded(
              child: GestureDetector(
                onTap: () => setSt(() => type = t),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                      color: type == t
                          ? (t == 'expense'
                              ? AppColors.expense.withOpacity(0.2)
                              : AppColors.income.withOpacity(0.2))
                          : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: type == t
                              ? (t == 'expense'
                                  ? AppColors.expense
                                  : AppColors.income)
                              : Colors.transparent)),
                  child: Text(
                    t == 'expense' ? 'مصروف' : 'دخل',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(
                        color: type == t
                            ? (t == 'expense'
                                ? AppColors.expense
                                : AppColors.income)
                            : AppColors.textSecondary),
                  ),
                ),
              ),
            )).toList()),
            const Gap(10),
            TextField(
              controller: titleCtrl,
              textDirection: ui.TextDirection.rtl,
              style: GoogleFonts.cairo(
                  fontSize: 14, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'الاسم (مثال: إيجار، نتفليكس)',
                hintStyle: GoogleFonts.cairo(
                    color: AppColors.textHint, fontSize: 13),
              ),
            ),
            const Gap(8),
            TextField(
              controller:   amountCtrl,
              keyboardType: TextInputType.number,
              textDirection: ui.TextDirection.ltr,
              style: GoogleFonts.cairo(
                  fontSize: 14, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'المبلغ',
                suffixText: 'ج.م',
                hintStyle: GoogleFonts.cairo(
                    color: AppColors.textHint, fontSize: 13),
              ),
            ),
            const Gap(8),
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(
                value:        category,
                dropdownColor: AppColors.surface,
                style:        GoogleFonts.cairo(
                    color: AppColors.textPrimary, fontSize: 12),
                decoration: InputDecoration(
                  labelText:  'الفئة',
                  labelStyle: GoogleFonts.cairo(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
                items: ['طعام','مواصلات','ترفيه','فواتير','صحة',
                        'ملابس','تعليم','إيجار','راتب','غير ذلك']
                    .map((c) => DropdownMenuItem(value: c,
                        child: Text(c, style: GoogleFonts.cairo(
                            color: AppColors.textPrimary, fontSize: 12))))
                    .toList(),
                onChanged: (v) => setSt(() => category = v!),
              )),
              const Gap(8),
              Expanded(child: DropdownButtonFormField<String>(
                value:        frequency,
                dropdownColor: AppColors.surface,
                style:        GoogleFonts.cairo(
                    color: AppColors.textPrimary, fontSize: 12),
                decoration: InputDecoration(
                  labelText:  'التكرار',
                  labelStyle: GoogleFonts.cairo(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
                items: [
                  ('daily',   'يومياً'),
                  ('weekly',  'أسبوعياً'),
                  ('monthly', 'شهرياً'),
                  ('yearly',  'سنوياً'),
                ].map((e) => DropdownMenuItem(value: e.$1,
                    child: Text(e.$2, style: GoogleFonts.cairo(
                        color: AppColors.textPrimary, fontSize: 12))))
                    .toList(),
                onChanged: (v) => setSt(() => frequency = v!),
              )),
            ]),
            const Gap(16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () {
                  final title  = titleCtrl.text.trim();
                  final amount = double.tryParse(amountCtrl.text);
                  if (title.isEmpty || amount == null || amount <= 0) return;
                  Navigator.pop(ctx);
                  notifier.addRecurring(
                    title:     title,
                    amount:    amount,
                    type:      type,
                    category:  category,
                    frequency: frequency,
                  );
                },
                child: Text('إضافة',
                    style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
