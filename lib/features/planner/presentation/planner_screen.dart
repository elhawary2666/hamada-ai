// lib/features/planner/presentation/planner_screen.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/di/providers.dart';
import '../../../core/theme/app_colors.dart';

part 'planner_screen.g.dart';

// ── PRIORITY HELPERS ──────────────────────────────────────────
// FIX Bug #1: Priority stored as TEXT ('low','medium','high') in DB
// These helpers normalize both old INT and new TEXT values

String priorityToString(int p) =>
    p >= 5 ? 'high' : p >= 3 ? 'medium' : 'low';

int priorityFromDynamic(dynamic p) {
  switch (p?.toString().toLowerCase()) {
    case 'high':   return 5;
    case 'medium': return 3;
    case 'low':    return 1;
    default:
      final n = int.tryParse(p?.toString() ?? '');
      return n ?? 3;
  }
}

Color priorityColor(dynamic p) {
  final n = priorityFromDynamic(p);
  if (n >= 5) return AppColors.expense;
  if (n >= 3) return AppColors.warning;
  return AppColors.textSecondary;
}

// ── TASKS NOTIFIER ────────────────────────────────────────────

@riverpod
class TasksNotifier extends _$TasksNotifier {
  @override
  Future<Map<String, List<Map<String, dynamic>>>> build() async {
    final db = ref.read(databaseHelperProvider);
    return {
      'today':   await db.getTodayTasks(),
      'overdue': await db.getOverdueTasks(),
      'pending': await db.getAllTasks(statusFilter: 'pending'),
    };
  }

  Future<void> add({
    required String title,
    String priority  = 'medium',
    int?   dueDateMs,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await ref.read(databaseHelperProvider).insert(Tables.tasks, {
      'id':         const Uuid().v4(),
      'title':      title,
      'status':     'pending',
      'priority':   priority,
      'due_date':   dueDateMs,
      'created_at': now,
    });
    ref.invalidateSelf();
  }

  Future<void> toggleDone(String id, String currentStatus) async {
    final newStatus = currentStatus == 'done' ? 'pending' : 'done';
    await ref.read(databaseHelperProvider)
        .update(Tables.tasks, {'status': newStatus}, id);
    ref.invalidateSelf();
    HapticFeedback.lightImpact();
  }


  Future<void> editTask(String id, {
    required String title,
    String priority  = 'medium',
    int?   dueDateMs,
  }) async {
    await ref.read(databaseHelperProvider).update(Tables.tasks, {
      'title':    title,
      'priority': priority,
      'due_date': dueDateMs,
    }, id);
    ref.invalidateSelf();
  }
  Future<void> deleteTask(String id) async {
    await ref.read(databaseHelperProvider).delete(Tables.tasks, id);
    ref.invalidateSelf();
    HapticFeedback.mediumImpact();
  }
}

// ── APPOINTMENTS NOTIFIER — ✅ Riverpod not FutureBuilder ─────

@riverpod
Future<List<Map<String, dynamic>>> appointments(AppointmentsRef ref) =>
    ref.read(databaseHelperProvider).getUpcomingAppointments(withinDays: 30);

// ── PLANNER SCREEN ────────────────────────────────────────────

class PlannerScreen extends ConsumerStatefulWidget {
  const PlannerScreen({super.key});
  @override
  ConsumerState<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends ConsumerState<PlannerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      backgroundColor: AppColors.surface,
      title: Text('مهامي 📋', style: GoogleFonts.cairo(
          fontSize: 18, fontWeight: FontWeight.bold)),
      bottom: TabBar(
        controller:           _tabCtrl,
        indicatorColor:       AppColors.primary,
        labelColor:           AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle:           GoogleFonts.cairo(fontWeight: FontWeight.bold),
        unselectedLabelStyle: GoogleFonts.cairo(),
        tabs: const [Tab(text: 'المهام'), Tab(text: 'المواعيد')],
      ),
    ),
    floatingActionButton: FloatingActionButton.extended(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.add),
      label: Text(
        _tabCtrl.index == 0 ? 'مهمة جديدة' : 'موعد جديد',
        style: GoogleFonts.cairo(),
      ),
      onPressed: () => _tabCtrl.index == 0
          ? _showAddTask(context)
          : _showAddAppointment(context),
    ),
    body: TabBarView(
      controller: _tabCtrl,
      children: [_TasksTab(), _AppointmentsTab()],
    ),
  );

  void _showAddTask(BuildContext context) => showModalBottomSheet(
    context: context, isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _AddTaskSheet(ref: ref),
  );

  void _showAddAppointment(BuildContext context) => showModalBottomSheet(
    context: context, isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _AddAppointmentSheet(ref: ref),
  );
}

// ── TASKS TAB ─────────────────────────────────────────────────

class _TasksTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tasksNotifierProvider);
    return async.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => Center(child: Text('خطأ: $e',
          style: GoogleFonts.cairo(color: AppColors.error))),
      data: (data) {
        final overdue    = data['overdue']  ?? [];
        final today      = data['today']    ?? [];
        final allPending = data['pending']  ?? [];
        final todayIds   = today.map((t) => t['id']).toSet();
        final overdueIds = overdue.map((t) => t['id']).toSet();
        final other = allPending
            .where((t) =>
                !todayIds.contains(t['id']) &&
                !overdueIds.contains(t['id']))
            .toList();

        if (overdue.isEmpty && today.isEmpty && other.isEmpty) {
          return Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('✅', style: TextStyle(fontSize: 52)),
            const Gap(12),
            Text('مفيش مهام دلوقتي 🎉', style: GoogleFonts.cairo(
                fontSize: 15, color: AppColors.textSecondary)),
          ]));
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
          children: [
            if (overdue.isNotEmpty) ...[
              _SectionHeader(
                  title: '⏰ متأخرة (${overdue.length})',
                  color: AppColors.expense),
              ...overdue.map((t) => _TaskTile(task: t)),
              const Gap(16),
            ],
            if (today.isNotEmpty) ...[
              _SectionHeader(
                  title: '📅 اليوم (${today.length})',
                  color: AppColors.primary),
              ...today.map((t) => _TaskTile(task: t)),
              const Gap(16),
            ],
            if (other.isNotEmpty) ...[
              _SectionHeader(
                  title: '📝 المهام (${other.length})',
                  color: AppColors.textSecondary),
              ...other.map((t) => _TaskTile(task: t)),
            ],
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.color});
  final String title;
  final Color  color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(title, style: GoogleFonts.cairo(
        fontSize: 13, fontWeight: FontWeight.bold, color: color)),
  );
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task});
  final Map<String, dynamic> task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDone     = task['status'] == 'done';
    final pColor     = priorityColor(task['priority']);
    final dueDateMs  = task['due_date'] as int?;
    final dueDateStr = (dueDateMs != null && dueDateMs > 0)
        ? DateFormat('d/M/yyyy').format(
            DateTime.fromMillisecondsSinceEpoch(dueDateMs))
        : null;

    return Dismissible(
      key:       ValueKey(task['id']),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('حذف المهمة؟',
              style: GoogleFonts.cairo(color: AppColors.textPrimary)),
          content: Text(task['title'] as String,
              style: GoogleFonts.cairo(color: AppColors.textSecondary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('لا', style: GoogleFonts.cairo()),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('حذف',
                  style: GoogleFonts.cairo(color: AppColors.error)),
            ),
          ],
        ),
      ),
      onDismissed: (_) => ref.read(tasksNotifierProvider.notifier)
          .deleteTask(task['id'] as String),
      background: Container(
        alignment: Alignment.centerRight,
        padding:   const EdgeInsets.only(right: 16),
        color:     AppColors.error.withValues(alpha: 0.2),
        child:     const Icon(Icons.delete_outline, color: AppColors.error),
      ),
      child: Container(
        margin:     const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
            color:        AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.inputBorder, width: 0.5)),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          leading: GestureDetector(
            onTap: () => ref.read(tasksNotifierProvider.notifier)
                .toggleDone(task['id'] as String, task['status'] as String),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24, height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone ? AppColors.success : Colors.transparent,
                border: Border.all(
                    color: isDone
                        ? AppColors.success
                        : AppColors.textSecondary,
                    width: 1.5),
              ),
              child: isDone
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ),
          onLongPress: () => _showEditTask(context, ref, task),
          title: Text(task['title'] as String,
              style: GoogleFonts.cairo(
                fontSize: 14,
                color:      isDone ? AppColors.textHint : AppColors.textPrimary,
                decoration: isDone ? TextDecoration.lineThrough : null,
              )),
          subtitle: dueDateStr != null
              ? Text(dueDateStr, style: GoogleFonts.cairo(
                  fontSize: 11, color: AppColors.textSecondary))
              : null,
          trailing: Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: pColor)),
        ),
      ),
    );
  }
}


void _showEditTask(BuildContext context, WidgetRef ref, Map<String, dynamic> task) {
  showModalBottomSheet(
    context: context, isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _EditTaskSheet(ref: ref, task: task),
  );
}

// ── APPOINTMENTS TAB ──────────────────────────────────────────

class _AppointmentsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(appointmentsProvider);
    return async.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => Center(child: Text('خطأ: $e',
          style: GoogleFonts.cairo(color: AppColors.error))),
      data: (appts) {
        if (appts.isEmpty) {
          return Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('📅', style: TextStyle(fontSize: 52)),
            const Gap(12),
            Text('مفيش مواعيد قريبة', style: GoogleFonts.cairo(
                fontSize: 15, color: AppColors.textSecondary)),
          ]));
        }

        return ListView.builder(
          padding:   const EdgeInsets.all(12),
          itemCount: appts.length,
          itemBuilder: (_, i) {
            final a      = appts[i];
            final dt     = DateTime.fromMillisecondsSinceEpoch(
                a['start_time'] as int);
            final isToday = dt.day   == DateTime.now().day &&
                dt.month == DateTime.now().month &&
                dt.year  == DateTime.now().year;

            return Dismissible(
              key:       ValueKey(a['id']),
              direction: DismissDirection.endToStart,
              onDismissed: (_) async {
                await ref.read(databaseHelperProvider)
                    .delete(Tables.appointments, a['id'] as String);
                ref.invalidate(appointmentsProvider);
              },
              background: Container(
                alignment: Alignment.centerRight,
                padding:   const EdgeInsets.only(right: 16),
                color:     AppColors.error.withValues(alpha: 0.2),
                child:     const Icon(Icons.delete_outline,
                    color: AppColors.error),
              ),
              child: Container(
                margin:     const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                    color:        AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: isToday
                            ? AppColors.primary.withValues(alpha: 0.4)
                            : AppColors.inputBorder,
                        width: isToday ? 1.5 : 0.5)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isToday
                        ? AppColors.primary
                        : AppColors.surfaceVariant,
                    child: Icon(Icons.event_outlined,
                        color:  isToday ? Colors.white : AppColors.textSecondary,
                        size: 18),
                  ),
                  onLongPress: () => _showEditAppointment(context, ref, a),
                  title: Text(a['title'] as String,
                      style: GoogleFonts.cairo(
                          fontSize: 14, color: AppColors.textPrimary)),
                  subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                      DateFormat('d/M/yyyy  HH:mm').format(dt),
                      style: GoogleFonts.cairo(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                    if ((a['location'] as String?)?.isNotEmpty == true)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.location_on_outlined,
                            size: 11, color: AppColors.textHint),
                        const Gap(2),
                        Text(a['location'] as String,
                            style: GoogleFonts.cairo(
                                fontSize: 11, color: AppColors.textHint)),
                      ]),
                  ]),
                  trailing: isToday
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6)),
                          child: Text('اليوم',
                              style: GoogleFonts.cairo(
                                  fontSize: 10, color: AppColors.primary)))
                      : null,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ── ADD TASK SHEET ────────────────────────────────────────────

class _AddTaskSheet extends StatefulWidget {
  const _AddTaskSheet({required this.ref});
  final WidgetRef ref;
  @override
  State<_AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends State<_AddTaskSheet> {
  final _ctrl      = TextEditingController();
  String   _priority = 'medium';
  DateTime? _dueDate;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(
                color: AppColors.textHint,
                borderRadius: BorderRadius.circular(2)))),
        const Gap(16),
        Text('مهمة جديدة', style: GoogleFonts.cairo(
            fontSize: 18, fontWeight: FontWeight.bold,
            color: AppColors.textPrimary)),
        const Gap(14),
        TextField(
          controller:    _ctrl,
          textDirection: ui.TextDirection.rtl,
          autofocus:     true,
          style: GoogleFonts.cairo(color: AppColors.textPrimary),
          decoration: InputDecoration(
              labelText: 'عنوان المهمة',
              hintText:  'مثال: مراجعة التقرير'),
        ),
        const Gap(14),
        Text('الأولوية', style: GoogleFonts.cairo(
            fontSize: 13, color: AppColors.textSecondary)),
        const Gap(8),
        Row(children: [
          for (final item in [
            ('low',    'عادية',   AppColors.success),
            ('medium', 'متوسطة',  AppColors.warning),
            ('high',   'عالية',   AppColors.expense),
          ])
            Expanded(child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: GestureDetector(
                onTap: () => setState(() => _priority = item.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: _priority == item.$1
                        ? item.$3.withValues(alpha: 0.15)
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: _priority == item.$1
                            ? item.$3
                            : AppColors.inputBorder),
                  ),
                  child: Text(item.$2,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.cairo(
                          fontSize: 12,
                          color: _priority == item.$1
                              ? item.$3
                              : AppColors.textSecondary)),
                ),
              ),
            )),
        ]),
        const Gap(12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.calendar_today_outlined,
              size: 18, color: AppColors.textSecondary),
          title: Text(
            _dueDate == null
                ? 'تاريخ الاستحقاق (اختياري)'
                : DateFormat('yyyy/MM/dd').format(_dueDate!),
            style: GoogleFonts.cairo(
                fontSize: 13,
                color: _dueDate == null
                    ? AppColors.textHint
                    : AppColors.textPrimary),
          ),
          trailing: _dueDate != null
              ? GestureDetector(
                  onTap: () => setState(() => _dueDate = null),
                  child: const Icon(Icons.clear,
                      size: 16, color: AppColors.textHint))
              : null,
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate:   DateTime.now(),
              lastDate:    DateTime.now().add(const Duration(days: 365 * 2)),
              builder: (_, child) =>
                  Theme(data: ThemeData.dark(), child: child!),
            );
            if (d != null) setState(() => _dueDate = d);
          },
        ),
        const Gap(16),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: () async {
            if (_ctrl.text.trim().isEmpty) return;
            await widget.ref.read(tasksNotifierProvider.notifier).add(
              title:     _ctrl.text.trim(),
              priority:  _priority,
              dueDateMs: _dueDate?.millisecondsSinceEpoch,
            );
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

// ── ADD APPOINTMENT SHEET ─────────────────────────────────────

class _AddAppointmentSheet extends StatefulWidget {
  const _AddAppointmentSheet({required this.ref});
  final WidgetRef ref;
  @override
  State<_AddAppointmentSheet> createState() => _AddAppointmentSheetState();
}

class _AddAppointmentSheetState extends State<_AddAppointmentSheet> {
  final _titleCtrl    = TextEditingController();
  final _locationCtrl = TextEditingController();
  DateTime _startTime = DateTime.now().add(const Duration(hours: 1));

  @override
  void dispose() {
    _titleCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(
                color: AppColors.textHint,
                borderRadius: BorderRadius.circular(2)))),
        const Gap(16),
        Text('موعد جديد', style: GoogleFonts.cairo(
            fontSize: 18, fontWeight: FontWeight.bold,
            color: AppColors.textPrimary)),
        const Gap(14),
        TextField(
          controller:    _titleCtrl,
          textDirection: ui.TextDirection.rtl,
          autofocus:     true,
          style: GoogleFonts.cairo(color: AppColors.textPrimary),
          decoration: InputDecoration(
              labelText: 'عنوان الموعد',
              hintText:  'مثال: اجتماع مع المدير'),
        ),
        const Gap(10),
        TextField(
          controller:    _locationCtrl,
          textDirection: ui.TextDirection.rtl,
          style: GoogleFonts.cairo(color: AppColors.textPrimary),
          decoration: InputDecoration(
            labelText: 'المكان (اختياري)',
            prefixIcon: const Icon(Icons.location_on_outlined,
                size: 18, color: AppColors.textSecondary),
          ),
        ),
        const Gap(12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.access_time_outlined,
              size: 18, color: AppColors.textSecondary),
          title: Text(
            DateFormat('yyyy/MM/dd  HH:mm').format(_startTime),
            style: GoogleFonts.cairo(
                fontSize: 14, color: AppColors.textPrimary),
          ),
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _startTime,
              firstDate:   DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
              builder: (_, child) =>
                  Theme(data: ThemeData.dark(), child: child!),
            );
            if (d == null || !mounted) return;
            final t = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(_startTime),
              builder: (_, child) =>
                  Theme(data: ThemeData.dark(), child: child!),
            );
            if (t != null) {
              setState(() => _startTime = DateTime(
                  d.year, d.month, d.day, t.hour, t.minute));
            }
          },
        ),
        const Gap(16),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: () async {
            final title = _titleCtrl.text.trim();
            if (title.isEmpty) return;
            final now = DateTime.now().millisecondsSinceEpoch;
            await widget.ref.read(databaseHelperProvider).insert(
                Tables.appointments, {
              'id':          const Uuid().v4(),
              'title':       title,
              'description': '',
              'start_time':  _startTime.millisecondsSinceEpoch,
              'end_time':    null,
              'location':    _locationCtrl.text.trim(),
              'created_at':  now,
            });
            widget.ref.invalidate(appointmentsProvider);
            if (!mounted) return;
            Navigator.pop(context);
            HapticFeedback.lightImpact();
          },
          child: Text('حفظ الموعد', style: GoogleFonts.cairo(fontSize: 16)),
        )),
        const Gap(8),
      ]),
    ),
  );
}


void _showEditAppointment(BuildContext context, WidgetRef ref, Map<String, dynamic> appt) {
  showModalBottomSheet(
    context: context, isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _EditAppointmentSheet(ref: ref, appt: appt),
  );
}

// ── EDIT TASK SHEET ───────────────────────────────────────────

class _EditTaskSheet extends StatefulWidget {
  const _EditTaskSheet({required this.ref, required this.task});
  final WidgetRef ref;
  final Map<String, dynamic> task;
  @override
  State<_EditTaskSheet> createState() => _EditTaskSheetState();
}

class _EditTaskSheetState extends State<_EditTaskSheet> {
  late final TextEditingController _ctrl;
  late String   _priority;
  DateTime?     _dueDate;

  @override
  void initState() {
    super.initState();
    _ctrl     = TextEditingController(text: widget.task['title'] as String? ?? '');
    _priority = widget.task['priority'] as String? ?? 'medium';
    final ms  = widget.task['due_date'] as int?;
    if (ms != null && ms > 0) _dueDate = DateTime.fromMillisecondsSinceEpoch(ms);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(
                color: AppColors.textHint,
                borderRadius: BorderRadius.circular(2)))),
        const Gap(16),
        Text('تعديل المهمة', style: GoogleFonts.cairo(
            fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const Gap(14),
        TextField(
          controller: _ctrl, textDirection: ui.TextDirection.rtl, autofocus: true,
          style: GoogleFonts.cairo(color: AppColors.textPrimary),
          decoration: InputDecoration(labelText: 'عنوان المهمة'),
        ),
        const Gap(14),
        Text('الأولوية', style: GoogleFonts.cairo(fontSize: 13, color: AppColors.textSecondary)),
        const Gap(8),
        Row(children: [
          for (final item in [
            ('low', 'عادية', AppColors.success),
            ('medium', 'متوسطة', AppColors.warning),
            ('high', 'عالية', AppColors.expense),
          ])
            Expanded(child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: GestureDetector(
                onTap: () => setState(() => _priority = item.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: _priority == item.$1
                        ? item.$3.withValues(alpha: 0.15)
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: _priority == item.$1 ? item.$3 : AppColors.inputBorder),
                  ),
                  child: Text(item.$2, textAlign: TextAlign.center,
                      style: GoogleFonts.cairo(
                          fontSize: 12,
                          color: _priority == item.$1 ? item.$3 : AppColors.textSecondary)),
                ),
              ),
            )),
        ]),
        const Gap(12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.textSecondary),
          title: Text(
            _dueDate == null ? 'تاريخ الاستحقاق (اختياري)' : DateFormat('yyyy/MM/dd').format(_dueDate!),
            style: GoogleFonts.cairo(
                fontSize: 13,
                color: _dueDate == null ? AppColors.textHint : AppColors.textPrimary),
          ),
          trailing: _dueDate != null
              ? GestureDetector(
                  onTap: () => setState(() => _dueDate = null),
                  child: const Icon(Icons.clear, size: 16, color: AppColors.textHint))
              : null,
          onTap: () async {
            final d = await showDatePicker(
              context: context, initialDate: _dueDate ?? DateTime.now(),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
              builder: (_, child) => Theme(data: ThemeData.dark(), child: child!),
            );
            if (d != null) setState(() => _dueDate = d);
          },
        ),
        const Gap(16),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: () async {
            if (_ctrl.text.trim().isEmpty) return;
            await widget.ref.read(tasksNotifierProvider.notifier).editTask(
              widget.task['id'] as String,
              title:     _ctrl.text.trim(),
              priority:  _priority,
              dueDateMs: _dueDate?.millisecondsSinceEpoch,
            );
            if (!mounted) return;
            Navigator.pop(context);
            HapticFeedback.lightImpact();
          },
          child: Text('حفظ التعديل', style: GoogleFonts.cairo(fontSize: 16)),
        )),
        const Gap(8),
      ]),
    ),
  );
}

// ── EDIT APPOINTMENT SHEET ────────────────────────────────────

class _EditAppointmentSheet extends StatefulWidget {
  const _EditAppointmentSheet({required this.ref, required this.appt});
  final WidgetRef ref;
  final Map<String, dynamic> appt;
  @override
  State<_EditAppointmentSheet> createState() => _EditAppointmentSheetState();
}

class _EditAppointmentSheetState extends State<_EditAppointmentSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _locationCtrl;
  late DateTime _startTime;

  @override
  void initState() {
    super.initState();
    _titleCtrl    = TextEditingController(text: widget.appt['title'] as String? ?? '');
    _locationCtrl = TextEditingController(text: widget.appt['location'] as String? ?? '');
    final ms = widget.appt['start_time'] as int?;
    _startTime = ms != null
        ? DateTime.fromMillisecondsSinceEpoch(ms)
        : DateTime.now().add(const Duration(hours: 1));
  }

  @override
  void dispose() { _titleCtrl.dispose(); _locationCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: AppColors.textHint, borderRadius: BorderRadius.circular(2)))),
        const Gap(16),
        Text('تعديل الموعد', style: GoogleFonts.cairo(
            fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const Gap(14),
        TextField(
          controller: _titleCtrl, textDirection: ui.TextDirection.rtl, autofocus: true,
          style: GoogleFonts.cairo(color: AppColors.textPrimary),
          decoration: InputDecoration(labelText: 'عنوان الموعد'),
        ),
        const Gap(10),
        TextField(
          controller: _locationCtrl, textDirection: ui.TextDirection.rtl,
          style: GoogleFonts.cairo(color: AppColors.textPrimary),
          decoration: InputDecoration(
            labelText: 'المكان (اختياري)',
            prefixIcon: const Icon(Icons.location_on_outlined, size: 18, color: AppColors.textSecondary),
          ),
        ),
        const Gap(12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.access_time_outlined, size: 18, color: AppColors.textSecondary),
          title: Text(DateFormat('yyyy/MM/dd  HH:mm').format(_startTime),
              style: GoogleFonts.cairo(fontSize: 14, color: AppColors.textPrimary)),
          onTap: () async {
            final d = await showDatePicker(
              context: context, initialDate: _startTime,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
              builder: (_, child) => Theme(data: ThemeData.dark(), child: child!),
            );
            if (d == null || !mounted) return;
            final t = await showTimePicker(
              context: context, initialTime: TimeOfDay.fromDateTime(_startTime),
              builder: (_, child) => Theme(data: ThemeData.dark(), child: child!),
            );
            if (t != null) setState(() => _startTime = DateTime(d.year, d.month, d.day, t.hour, t.minute));
          },
        ),
        const Gap(16),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: () async {
            final title = _titleCtrl.text.trim();
            if (title.isEmpty) return;
            await widget.ref.read(databaseHelperProvider).update(
              Tables.appointments,
              {
                'title':      title,
                'location':   _locationCtrl.text.trim(),
                'start_time': _startTime.millisecondsSinceEpoch,
              },
              widget.appt['id'] as String,
            );
            widget.ref.invalidate(appointmentsProvider);
            if (!mounted) return;
            Navigator.pop(context);
            HapticFeedback.lightImpact();
          },
          child: Text('حفظ التعديل', style: GoogleFonts.cairo(fontSize: 16)),
        )),
        const Gap(8),
      ]),
    ),
  );
}
