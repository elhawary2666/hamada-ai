// lib/features/planner/presentation/planner_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/di/providers.dart';
import '../../../core/theme/app_colors.dart';

part 'planner_screen.g.dart';

@riverpod
class TasksNotifier extends _$TasksNotifier {
  @override
  Future<Map<String, List<Map<String, dynamic>>>> build() async {
    final db = ref.read(databaseHelperProvider);
    return {'today': await db.getTodayTasks(), 'overdue': await db.getOverdueTasks()};
  }

  Future<void> add({required String title, int priority = 3}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await ref.read(databaseHelperProvider).insert(Tables.tasks, {
      'id': const Uuid().v4(), 'title': title,
      'status': 'pending', 'priority': priority,
      'created_at': now,
    });
    ref.invalidateSelf();
  }

  Future<void> toggleDone(String id, String status) async {
    final done = status == 'done';
    await ref.read(databaseHelperProvider).update(Tables.tasks, {
      'status': done ? 'pending' : 'done',
    }, id);
    ref.invalidateSelf();
    HapticFeedback.lightImpact();
  }
}

class PlannerScreen extends ConsumerWidget {
  const PlannerScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(length: 2, child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('📋 مهامي', style: GoogleFonts.cairo(
            fontSize: 18, fontWeight: FontWeight.bold)),
        bottom: TabBar(
          indicatorColor:      AppColors.primary,
          labelColor:          AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle:          GoogleFonts.cairo(),
          unselectedLabelStyle: GoogleFonts.cairo(),
          tabs: const [Tab(text: 'المهام'), Tab(text: 'المواعيد')],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary, foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text('مهمة', style: GoogleFonts.cairo()),
        onPressed: () => _showAdd(context, ref),
      ),
      body: TabBarView(children: [_TasksTab(), _AppointmentsTab()]),
    ));
  }

  void _showAdd(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddTaskSheet(ref: ref),
    );
  }
}

class _TasksTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tasksNotifierProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error:   (e, _) => Center(child: Text('خطأ: $e')),
      data:    (data) {
        final overdue = data['overdue'] ?? [];
        final today   = data['today']   ?? [];
        if (overdue.isEmpty && today.isEmpty) {
          return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('✅', style: TextStyle(fontSize: 52)), const Gap(12),
            Text('مفيش مهام دلوقتي', style: GoogleFonts.cairo(
                fontSize: 15, color: AppColors.textSecondary)),
          ]));
        }
        return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 100), children: [
          if (overdue.isNotEmpty) ...[
            _SectionHeader(title: '⏰ متأخرة (${overdue.length})', color: AppColors.expense),
            ...overdue.map((t) => _TaskTile(task: t, ref: ref)),
            const Gap(16),
          ],
          if (today.isNotEmpty) ...[
            _SectionHeader(title: '📅 اليوم (${today.length})', color: AppColors.primary),
            ...today.map((t) => _TaskTile(task: t, ref: ref)),
          ],
        ]);
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.color});
  final String title; final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(title, style: GoogleFonts.cairo(fontSize: 13,
        fontWeight: FontWeight.bold, color: color)),
  );
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.ref});
  final Map<String, dynamic> task;
  final WidgetRef ref;
  @override
  Widget build(BuildContext context) {
    final isDone   = task['status'] == 'done';
    final priority = task['priority'] as int? ?? 3;
    final pColor   = priority >= 5 ? AppColors.expense
        : priority >= 3 ? AppColors.warning : AppColors.textSecondary;
    return Container(
      margin:     const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.inputBorder, width: 0.5)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: GestureDetector(
          onTap: () => ref.read(tasksNotifierProvider.notifier)
              .toggleDone(task['id'] as String, task['status'] as String),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 24, height: 24,
            decoration: BoxDecoration(shape: BoxShape.circle,
              color:  isDone ? AppColors.success : Colors.transparent,
              border: Border.all(color: isDone ? AppColors.success : AppColors.textSecondary, width: 1.5),
            ),
            child: isDone ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
          ),
        ),
        title: Text(task['title'] as String, style: GoogleFonts.cairo(
          fontSize: 14,
          color: isDone ? AppColors.textHint : AppColors.textPrimary,
          decoration: isDone ? TextDecoration.lineThrough : null,
        )),
        trailing: Container(width: 6, height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: pColor)),
      ),
    );
  }
}

class _AppointmentsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseHelperProvider);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: db.getUpcomingAppointments(withinDays: 14),
      builder: (_, snap) {
        if (!snap.hasData) return const Center(
            child: CircularProgressIndicator(color: AppColors.primary));
        final appts = snap.data!;
        if (appts.isEmpty) return Center(child: Text(
          'لا توجد مواعيد قريبة',
          style: GoogleFonts.cairo(color: AppColors.textSecondary)));
        return ListView.builder(
          padding:     const EdgeInsets.all(12),
          itemCount:   appts.length,
          itemBuilder: (_, i) {
            final a  = appts[i];
            final dt = DateTime.fromMillisecondsSinceEpoch(a['start_time'] as int);
            return Container(
              margin:     const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.inputBorder, width: 0.5)),
              child: ListTile(
                leading: const CircleAvatar(backgroundColor: AppColors.primary,
                  child: Icon(Icons.event_outlined, color: Colors.white, size: 18)),
                title: Text(a['title'] as String,
                    style: GoogleFonts.cairo(fontSize: 14, color: AppColors.textPrimary)),
                subtitle: Text(
                  '${dt.day}/${dt.month}/${dt.year}  ${dt.hour}:${dt.minute.toString().padLeft(2,'0')}',
                  style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textSecondary)),
              ),
            );
          },
        );
      },
    );
  }
}

class _AddTaskSheet extends StatefulWidget {
  const _AddTaskSheet({required this.ref});
  final WidgetRef ref;
  @override
  State<_AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends State<_AddTaskSheet> {
  final _ctrl   = TextEditingController();
  int _priority = 3;
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: Padding(padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('مهمة جديدة', style: GoogleFonts.cairo(
            fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const Gap(14),
        TextField(controller: _ctrl, textDirection: TextDirection.rtl, autofocus: true,
          style: GoogleFonts.cairo(color: AppColors.textPrimary),
          decoration: InputDecoration(labelText: 'عنوان المهمة')),
        const Gap(14),
        Text('الأولوية', style: GoogleFonts.cairo(fontSize: 13, color: AppColors.textSecondary)),
        const Gap(8),
        Row(children: [for (final p in [1, 3, 5]) Expanded(child: Padding(
          padding: const EdgeInsets.only(left: 6),
          child: GestureDetector(
            onTap: () => setState(() => _priority = p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: _priority == p
                    ? (p == 5 ? AppColors.expense : p == 3 ? AppColors.warning : AppColors.success).withOpacity(0.15)
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _priority == p
                    ? (p == 5 ? AppColors.expense : p == 3 ? AppColors.warning : AppColors.success)
                    : AppColors.inputBorder),
              ),
              child: Text(p == 1 ? 'عادية' : p == 3 ? 'متوسطة' : 'عالية',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(fontSize: 12)),
            ),
          ),
        ))]),
        const Gap(16),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: () async {
            if (_ctrl.text.trim().isEmpty) return;
            await widget.ref.read(tasksNotifierProvider.notifier)
                .add(title: _ctrl.text.trim(), priority: _priority);
            if (!mounted) return;
            Navigator.pop(context);
            HapticFeedback.lightImpact();
          },
          child: Text('حفظ', style: GoogleFonts.cairo(fontSize: 16)),
        )),
        const Gap(8),
      ]),
    ),
  );
}
