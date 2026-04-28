// lib/features/notes/presentation/notes_screen.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/di/providers.dart';
import '../../../core/theme/app_colors.dart';

part 'notes_screen.g.dart';

@riverpod
class NotesNotifier extends _$NotesNotifier {
  @override
  Future<List<Map<String, dynamic>>> build() =>
      ref.read(databaseHelperProvider).getAllNotes(limit: 200);

  Future<void> add({required String content, String? title}) async {
    final db  = ref.read(databaseHelperProvider);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(Tables.userNotes, {
      'id': const Uuid().v4(), 'title': title, 'content': content,
      'tags': '[]', 'color': 'default',
      'is_pinned': 0,
      'created_at': now, 'updated_at': now,
    });
    ref.invalidateSelf();
  }

  Future<void> togglePin(String id, bool pinned) async {
    await ref.read(databaseHelperProvider).update(Tables.userNotes,
        {'is_pinned': pinned ? 0 : 1}, id);
    ref.invalidateSelf();
  }

  Future<void> archive(String id) async {
    await ref.read(databaseHelperProvider).delete(Tables.userNotes, id);
    ref.invalidateSelf();
  }


  Future<void> edit(String id, {required String content, String? title}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await ref.read(databaseHelperProvider).update(Tables.userNotes, {
      'title':      title?.isEmpty == true ? null : title,
      'content':    content,
      'updated_at': now,
    }, id);
    ref.invalidateSelf();
  }

  Future<void> delete(String id) async {
    await ref.read(databaseHelperProvider).delete(Tables.userNotes, id);
    ref.invalidateSelf();
  }

  Future<List<Map<String, dynamic>>> search(String q) =>
      ref.read(databaseHelperProvider).searchNotes(q);
}

class NotesScreen extends ConsumerWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesNotifierProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('📝 ملاحظاتي', style: GoogleFonts.cairo(
            fontSize: 18, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_outlined, color: AppColors.textSecondary),
            onPressed: () => showSearch(
                context: context, delegate: _SearchDelegate(ref)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary, foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text('ملاحظة', style: GoogleFonts.cairo()),
        onPressed: () => _showAdd(context, ref),
      ),
      body: notes.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error:   (e, _) => Center(child: Text('خطأ: $e')),
        data:    (list) => list.isEmpty
            ? _EmptyNotes()
            : ListView.builder(
                padding:     const EdgeInsets.fromLTRB(12, 12, 12, 100),
                itemCount:   list.length,
                itemBuilder: (_, i) => _NoteCard(note: list[i], index: i, ref: ref),
              ),
      ),
    );
  }

  void _showAdd(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddNoteSheet(ref: ref),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.index, required this.ref});
  final Map<String, dynamic> note;
  final int index;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final isPinned = (note['is_pinned'] as int? ?? 0) == 1;
    final isAuto   = note['source'] == 'auto_extracted';
    final content  = note['content'] as String;
    final title    = note['title']   as String?;

    return Container(
      margin:     const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPinned ? AppColors.primary.withValues(alpha: 0.4) : AppColors.inputBorder,
          width: isPinned ? 1.5 : 0.5),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
        title: title != null ? Text(title, style: GoogleFonts.cairo(
            fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary))
            : null,
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null) const Gap(4),
          Text(content.length > 100 ? '${content.substring(0, 100)}...' : content,
            style: GoogleFonts.cairo(fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
          const Gap(4),
          Row(children: [
            if (isAuto) _Badge(label: '🤖 تلقائي', color: AppColors.primary),
            if (isPinned) _Badge(label: '📌 مثبت', color: AppColors.warning),
          ]),
        ]),
        trailing: PopupMenuButton<String>(
          color: AppColors.surfaceVariant, iconColor: AppColors.textHint,
          onSelected: (v) {
            switch (v) {
              case 'edit':
                showModalBottomSheet(
                  context: context, isScrollControlled: true,
                  backgroundColor: AppColors.surface,
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                  builder: (_) => _EditNoteSheet(ref: ref, note: note),
                );
                break;
              case 'pin':     ref.read(notesNotifierProvider.notifier).togglePin(note['id'], isPinned); break;
              case 'archive': ref.read(notesNotifierProvider.notifier).archive(note['id']); break;
              case 'delete':  ref.read(notesNotifierProvider.notifier).delete(note['id']); break;
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'edit',    child: Text('تعديل',   style: GoogleFonts.cairo())),
            PopupMenuItem(value: 'pin',     child: Text(isPinned ? 'إلغاء التثبيت' : 'تثبيت', style: GoogleFonts.cairo())),
            PopupMenuItem(value: 'archive', child: Text('أرشفة',  style: GoogleFonts.cairo())),
            PopupMenuItem(value: 'delete',  child: Text('حذف',    style: GoogleFonts.cairo(color: AppColors.error))),
          ],
        ),
      ),
    ).animate().fadeIn(delay: Duration(milliseconds: index * 25), duration: 200.ms);
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label; final Color color;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 6),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10)),
    child: Text(label, style: GoogleFonts.cairo(fontSize: 10, color: color)),
  );
}

class _EmptyNotes extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Text('📝', style: TextStyle(fontSize: 48)), const Gap(12),
      Text('لا يوجد ملاحظات بعد',
          style: GoogleFonts.cairo(fontSize: 15, color: AppColors.textSecondary)),
      const Gap(6),
      Text('حماده بيسجل تلقائياً لما تتكلم معاه',
          style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textHint)),
    ],
  ));
}

class _AddNoteSheet extends StatefulWidget {
  const _AddNoteSheet({required this.ref});
  final WidgetRef ref;
  @override
  State<_AddNoteSheet> createState() => _AddNoteSheetState();
}

class _AddNoteSheetState extends State<_AddNoteSheet> {
  final _title   = TextEditingController();
  final _content = TextEditingController();
  @override
  void dispose() { _title.dispose(); _content.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: Padding(padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('ملاحظة جديدة', style: GoogleFonts.cairo(
            fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const Gap(14),
        TextField(controller: _title, textDirection: ui.TextDirection.rtl,
          style: GoogleFonts.cairo(color: AppColors.textPrimary),
          decoration: InputDecoration(labelText: 'العنوان (اختياري)')),
        const Gap(10),
        TextField(controller: _content, textDirection: ui.TextDirection.rtl, maxLines: 5,
          style: GoogleFonts.cairo(color: AppColors.textPrimary),
          decoration: InputDecoration(labelText: 'المحتوى', alignLabelWithHint: true)),
        const Gap(14),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: () async {
            if (_content.text.trim().isEmpty) return;
            await widget.ref.read(notesNotifierProvider.notifier).add(
              content: _content.text.trim(),
              title:   _title.text.trim().isEmpty ? null : _title.text.trim(),
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

class _SearchDelegate extends SearchDelegate {
  _SearchDelegate(this.ref);
  final WidgetRef ref;
  @override
  String get searchFieldLabel => 'ابحث في ملاحظاتك...';
  @override
  List<Widget> buildActions(BuildContext context) =>
      [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];
  @override
  Widget buildLeading(BuildContext context) =>
      IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));
  @override
  Widget buildResults(BuildContext context) => _buildList();
  @override
  Widget buildSuggestions(BuildContext context) =>
      query.isEmpty ? const SizedBox.shrink() : _buildList();

  Widget _buildList() => FutureBuilder<List<Map<String, dynamic>>>(
    future: ref.read(notesNotifierProvider.notifier).search(query),
    builder: (_, s) {
      if (!s.hasData) return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
      return ListView.builder(
        itemCount:   s.data!.length,
        itemBuilder: (_, i) => _NoteCard(note: s.data![i], index: i, ref: ref),
      );
    },
  );
}


// ── EDIT NOTE SHEET ───────────────────────────────────────────

class _EditNoteSheet extends StatefulWidget {
  const _EditNoteSheet({required this.ref, required this.note});
  final WidgetRef ref;
  final Map<String, dynamic> note;
  @override
  State<_EditNoteSheet> createState() => _EditNoteSheetState();
}

class _EditNoteSheetState extends State<_EditNoteSheet> {
  late final TextEditingController _title;
  late final TextEditingController _content;

  @override
  void initState() {
    super.initState();
    _title   = TextEditingController(text: widget.note['title']   as String? ?? '');
    _content = TextEditingController(text: widget.note['content'] as String? ?? '');
  }

  @override
  void dispose() { _title.dispose(); _content.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: Padding(padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: AppColors.textHint, borderRadius: BorderRadius.circular(2)))),
        const Gap(16),
        Text('تعديل الملاحظة', style: GoogleFonts.cairo(
            fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const Gap(14),
        TextField(controller: _title, textDirection: ui.TextDirection.rtl,
          style: GoogleFonts.cairo(color: AppColors.textPrimary),
          decoration: InputDecoration(labelText: 'العنوان (اختياري)')),
        const Gap(10),
        TextField(controller: _content, textDirection: ui.TextDirection.rtl, maxLines: 5,
          style: GoogleFonts.cairo(color: AppColors.textPrimary),
          decoration: InputDecoration(labelText: 'المحتوى', alignLabelWithHint: true)),
        const Gap(14),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: () async {
            if (_content.text.trim().isEmpty) return;
            await widget.ref.read(notesNotifierProvider.notifier).edit(
              widget.note['id'] as String,
              content: _content.text.trim(),
              title:   _title.text.trim().isEmpty ? null : _title.text.trim(),
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
