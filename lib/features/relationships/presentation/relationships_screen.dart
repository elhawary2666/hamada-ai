// lib/features/relationships/presentation/relationships_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/di/providers.dart';
import '../../../core/theme/app_colors.dart';

class RelationshipsScreen extends ConsumerStatefulWidget {
  const RelationshipsScreen({super.key});
  @override
  ConsumerState<RelationshipsScreen> createState() => _RelationshipsScreenState();
}

class _RelationshipsScreenState extends ConsumerState<RelationshipsScreen> {
  List<Map<String, dynamic>> _rels = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db   = ref.read(databaseHelperProvider);
    final data = await db.getAllRelationships();
    if (mounted) setState(() { _rels = data; _loading = false; });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      backgroundColor: AppColors.surface,
      title: Text('👥 علاقاتي', style: GoogleFonts.cairo(
          fontSize: 18, fontWeight: FontWeight.bold)),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_outlined, color: AppColors.textSecondary),
          onPressed: _load,
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      backgroundColor: AppColors.primary, foregroundColor: Colors.white,
      icon: const Icon(Icons.person_add_outlined),
      label: Text('شخص جديد', style: GoogleFonts.cairo()),
      onPressed: () => _showAdd(context),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
        : _rels.isEmpty
            ? _EmptyState()
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                itemCount: _rels.length,
                itemBuilder: (_, i) => _RelCard(
                  rel: _rels[i],
                  onChanged: _load,
                ),
              ),
  );

  void _showAdd(BuildContext context) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddRelSheet(onSaved: _load),
    );
  }
}

class _RelCard extends ConsumerWidget {
  const _RelCard({required this.rel, required this.onChanged});
  final Map<String, dynamic> rel;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name     = rel['name']     as String? ?? '';
    final relation = rel['relation'] as String? ?? '';
    final birthday = rel['birthday'] as int?;
    final notes    = rel['notes']    as String? ?? '[]';

    int noteCount = 0;
    try {
      final list = List<dynamic>.from(
          (notes.trim().isEmpty || notes == '[]') ? [] : List.from([]));
      noteCount = list.length;
    } catch (_) {}

    final bdayStr = birthday != null
        ? _formatDate(DateTime.fromMillisecondsSinceEpoch(birthday))
        : null;

    return Dismissible(
      key: ValueKey(rel['id']),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('حذف؟', style: GoogleFonts.cairo(color: AppColors.textPrimary)),
          content: Text('هتحذف $name من علاقاتك',
              style: GoogleFonts.cairo(color: AppColors.textSecondary)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
                child: Text('لا', style: GoogleFonts.cairo())),
            TextButton(onPressed: () => Navigator.pop(context, true),
                child: Text('حذف', style: GoogleFonts.cairo(color: AppColors.error))),
          ],
        ),
      ),
      onDismissed: (_) async {
        await ref.read(databaseHelperProvider).delete(Tables.relationships, rel['id'] as String);
        onChanged();
        HapticFeedback.mediumImpact();
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: AppColors.error.withValues(alpha: 0.2),
        child: const Icon(Icons.delete_outline, color: AppColors.error),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.surface, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.inputBorder, width: 0.5),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: CircleAvatar(
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            child: Text(
              name.isNotEmpty ? name[0] : '?',
              style: GoogleFonts.cairo(
                  fontSize: 18, color: AppColors.primary, fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(name, style: GoogleFonts.cairo(
              fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (relation.isNotEmpty)
              Text(relation, style: GoogleFonts.cairo(
                  fontSize: 12, color: AppColors.textSecondary)),
            if (bdayStr != null)
              Text('🎂 $bdayStr', style: GoogleFonts.cairo(
                  fontSize: 11, color: AppColors.textHint)),
          ]),
          trailing: noteCount > 0
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('$noteCount ملاحظة',
                      style: GoogleFonts.cairo(fontSize: 11, color: AppColors.primary)),
                )
              : null,
          onTap: () => _showNotes(context, ref),
        ),
      ),
    );
  }

  void _showNotes(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _NotesSheet(rel: rel, ref: ref, onChanged: onChanged),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year}';
}

class _NotesSheet extends StatelessWidget {
  const _NotesSheet({required this.rel, required this.ref, required this.onChanged});
  final Map<String, dynamic>  rel;
  final WidgetRef ref;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final name  = rel['name'] as String? ?? '';
    final notes = rel['notes'] as String? ?? '[]';
    List<dynamic> notesList = [];
    try {
      if (notes.trim().isNotEmpty && notes.trim() != '[]') {
        final decoded = jsonDecode(notes);
        if (decoded is List) notesList = decoded;
      }
    } catch (_) { notesList = []; }

    return DraggableScrollableSheet(
      initialChildSize: 0.6, maxChildSize: 0.9, minChildSize: 0.4,
      expand: false,
      builder: (_, ctrl) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Container(width: 36, height: 4,
              decoration: BoxDecoration(
                  color: AppColors.textHint, borderRadius: BorderRadius.circular(2))),
          const Gap(16),
          Text('ملاحظات عن $name', style: GoogleFonts.cairo(
              fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const Gap(16),
          if (notesList.isEmpty)
            Text('لا توجد ملاحظات بعد — كلم حماده عن $name',
                style: GoogleFonts.cairo(fontSize: 13, color: AppColors.textSecondary))
          else
            Expanded(child: ListView.builder(
              controller: ctrl,
              itemCount: notesList.length,
              itemBuilder: (_, i) {
                final n = notesList[i] as Map<String, dynamic>;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(n['note'] as String? ?? '',
                        style: GoogleFonts.cairo(
                            fontSize: 13, color: AppColors.textPrimary, height: 1.5)),
                  ),
                );
              },
            )),
          const Gap(8),
          Text('💡 قول لحماده: "فلان بيحب..." لإضافة ملاحظة',
              style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textHint)),
        ]),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Text('👥', style: TextStyle(fontSize: 52)),
      const Gap(12),
      Text('مفيش علاقات محفوظة', style: GoogleFonts.cairo(
          fontSize: 15, color: AppColors.textSecondary)),
      const Gap(6),
      Text('قول لحماده: "أحمد صاحبي بيحب..." وهيحفظ تلقائياً',
          style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textHint)),
    ],
  ));
}

class _AddRelSheet extends StatefulWidget {
  const _AddRelSheet({required this.onSaved});
  final VoidCallback onSaved;
  @override
  State<_AddRelSheet> createState() => _AddRelSheetState();
}

class _AddRelSheetState extends State<_AddRelSheet> {
  final _nameCtrl     = TextEditingController();
  final _relationCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() { _nameCtrl.dispose(); _relationCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Consumer(
    builder: (context, ref, _) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: AppColors.textHint,
                  borderRadius: BorderRadius.circular(2)))),
          const Gap(16),
          Text('شخص جديد', style: GoogleFonts.cairo(
              fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const Gap(14),
          TextField(
            controller: _nameCtrl, textDirection: TextDirection.rtl, autofocus: true,
            style: GoogleFonts.cairo(color: AppColors.textPrimary),
            decoration: InputDecoration(labelText: 'الاسم', hintText: 'مثال: أحمد'),
          ),
          const Gap(10),
          TextField(
            controller: _relationCtrl, textDirection: TextDirection.rtl,
            style: GoogleFonts.cairo(color: AppColors.textPrimary),
            decoration: InputDecoration(labelText: 'العلاقة (اختياري)', hintText: 'صاحب / أخ / زميل'),
          ),
          const Gap(16),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _saving ? null : () async {
              if (_nameCtrl.text.trim().isEmpty) return;
              setState(() => _saving = true);
              final db  = ref.read(databaseHelperProvider);
              final now = DateTime.now().millisecondsSinceEpoch;
              await db.insert(Tables.relationships, {
                'id': const Uuid().v4(),
                'name': _nameCtrl.text.trim(),
                'relation': _relationCtrl.text.trim(),
                'notes': '[]', 'birthday': null,
                'last_contact': now, 'created_at': now,
              });
              widget.onSaved();
              if (mounted) Navigator.pop(context);
              HapticFeedback.lightImpact();
            },
            child: _saving
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('حفظ', style: GoogleFonts.cairo(fontSize: 16)),
          )),
          const Gap(8),
        ]),
      ),
    ),
  );
}
