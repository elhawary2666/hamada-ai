// lib/features/habits/presentation/habits_screen.dart
import 'dart:ui' as ui;
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

part 'habits_screen.g.dart';

@riverpod
class HabitsNotifier extends _$HabitsNotifier {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    final db     = ref.read(databaseHelperProvider);
    final habits = await db.getAllHabits();
    // Enrich with streak and today status
    final enriched = <Map<String, dynamic>>[];
    for (final h in habits) {
      final id      = h['id'] as String;
      final streak  = await db.calculateStreak(id);
      final doneToday = await db.isHabitLoggedToday(id);
      enriched.add({...h, 'streak': streak, 'done_today': doneToday});
    }
    return enriched;
  }

  Future<void> add({required String name, String icon = '⭐'}) async {
    final db  = ref.read(databaseHelperProvider);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(Tables.habits, {
      'id': const Uuid().v4(), 'name': name, 'icon': icon,
      'frequency': 'daily', 'target_days': 7, 'created_at': now,
    });
    ref.invalidateSelf();
  }

  Future<void> logToday(String habitId) async {
    final db    = ref.read(databaseHelperProvider);
    final now   = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
    await db.logHabit(habitId, today, const Uuid().v4(), now.millisecondsSinceEpoch);
    ref.invalidateSelf();
    HapticFeedback.lightImpact();
  }

  Future<void> delete(String id) async {
    await ref.read(databaseHelperProvider).delete(Tables.habits, id);
    ref.invalidateSelf();
  }
}

class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habitsAsync = ref.watch(habitsNotifierProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('🎯 عاداتي', style: GoogleFonts.cairo(
            fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary, foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text('عادة جديدة', style: GoogleFonts.cairo()),
        onPressed: () => _showAddHabit(context, ref),
      ),
      body: habitsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('خطأ: $e', style: GoogleFonts.cairo())),
        data: (habits) => habits.isEmpty
            ? _EmptyHabits()
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                itemCount: habits.length,
                itemBuilder: (_, i) => _HabitTile(habit: habits[i]),
              ),
      ),
    );
  }

  void _showAddHabit(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddHabitSheet(ref: ref),
    );
  }
}

class _HabitTile extends ConsumerWidget {
  const _HabitTile({required this.habit});
  final Map<String, dynamic> habit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doneToday = habit['done_today'] as bool? ?? false;
    final streak    = habit['streak'] as int? ?? 0;
    final icon      = habit['icon'] as String? ?? '⭐';
    final name      = habit['name'] as String? ?? '';

    return Dismissible(
      key: ValueKey(habit['id']),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('حذف العادة؟', style: GoogleFonts.cairo(color: AppColors.textPrimary)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
                child: Text('لا', style: GoogleFonts.cairo())),
            TextButton(onPressed: () => Navigator.pop(context, true),
                child: Text('حذف', style: GoogleFonts.cairo(color: AppColors.error))),
          ],
        ),
      ),
      onDismissed: (_) =>
          ref.read(habitsNotifierProvider.notifier).delete(habit['id'] as String),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: AppColors.error.withValues(alpha: 0.2),
        child: const Icon(Icons.delete_outline, color: AppColors.error),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: doneToday
                ? AppColors.success.withValues(alpha: 0.5)
                : AppColors.inputBorder,
            width: doneToday ? 1.5 : 0.5,
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: doneToday
                  ? AppColors.success.withValues(alpha: 0.15)
                  : AppColors.surfaceVariant,
            ),
            child: Center(child: Text(icon, style: const TextStyle(fontSize: 22))),
          ),
          title: Text(name, style: GoogleFonts.cairo(
              fontSize: 15, color: AppColors.textPrimary,
              fontWeight: FontWeight.w600)),
          subtitle: Row(children: [
            Text('🔥 $streak يوم متتالي',
                style: GoogleFonts.cairo(fontSize: 12,
                    color: streak > 0 ? AppColors.warning : AppColors.textHint)),
            if (doneToday) ...[
              const Gap(8),
              Text('✅ اليوم', style: GoogleFonts.cairo(
                  fontSize: 11, color: AppColors.success)),
            ],
          ]),
          trailing: doneToday
              ? const Icon(Icons.check_circle_rounded,
                  color: AppColors.success, size: 28)
              : GestureDetector(
                  onTap: () => ref.read(habitsNotifierProvider.notifier)
                      .logToday(habit['id'] as String),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Text('سجّل',
                        style: GoogleFonts.cairo(
                            fontSize: 12, color: AppColors.primary,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
        ),
      ),
    );
  }
}

class _EmptyHabits extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Text('🎯', style: TextStyle(fontSize: 52)),
      const Gap(12),
      Text('مفيش عادات لسه', style: GoogleFonts.cairo(
          fontSize: 15, color: AppColors.textSecondary)),
      const Gap(6),
      Text('ابدأ بعادة يومية بسيطة — حماده هيتابعك!',
          style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textHint)),
    ],
  ));
}

class _AddHabitSheet extends StatefulWidget {
  const _AddHabitSheet({required this.ref});
  final WidgetRef ref;
  @override
  State<_AddHabitSheet> createState() => _AddHabitSheetState();
}

class _AddHabitSheetState extends State<_AddHabitSheet> {
  final _ctrl = TextEditingController();
  String _icon = '⭐';

  static const _icons = ['⭐','🏃','💪','📚','💧','😴','🧘','🥗','✍️','🎯','💊','🚶'];

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: Padding(padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(
                color: AppColors.textHint, borderRadius: BorderRadius.circular(2)))),
        const Gap(16),
        Text('عادة جديدة', style: GoogleFonts.cairo(
            fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const Gap(14),
        TextField(
          controller: _ctrl, textDirection: ui.TextDirection.rtl, autofocus: true,
          style: GoogleFonts.cairo(color: AppColors.textPrimary),
          decoration: InputDecoration(
              labelText: 'اسم العادة', hintText: 'مثال: مشي 30 دقيقة'),
        ),
        const Gap(14),
        Text('اختار أيقونة', style: GoogleFonts.cairo(
            fontSize: 13, color: AppColors.textSecondary)),
        const Gap(8),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: _icons.map((ic) => GestureDetector(
            onTap: () => setState(() => _icon = ic),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _icon == ic
                    ? AppColors.primary.withValues(alpha: 0.2)
                    : AppColors.surfaceVariant,
                border: Border.all(
                    color: _icon == ic ? AppColors.primary : Colors.transparent),
              ),
              child: Text(ic, style: const TextStyle(fontSize: 22)),
            ),
          )).toList(),
        ),
        const Gap(16),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: () async {
            if (_ctrl.text.trim().isEmpty) return;
            await widget.ref.read(habitsNotifierProvider.notifier)
                .add(name: _ctrl.text.trim(), icon: _icon);
            if (!mounted) return;
            Navigator.pop(context);
            HapticFeedback.lightImpact();
          },
          child: Text('حفظ العادة', style: GoogleFonts.cairo(fontSize: 16)),
        )),
        const Gap(8),
      ]),
    ),
  );
}
