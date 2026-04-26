// lib/features/settings/presentation/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/di/providers.dart';
import '../../chat/providers/chat_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/ai_service.dart'; // includes aiReadyNotifier
import '../../../core/services/backup_service.dart';
import '../../../core/services/biometric_service.dart';
import '../../../core/services/export_service.dart';
import '../../../core/theme/app_colors.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _keyCtrl  = TextEditingController();
  bool  _obscure  = true;
  bool  _saving   = false;
  bool  _backing  = false;
  bool  _restoring = false;
  String? _keyMsg;

  @override
  void dispose() { _keyCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final ai = ref.read(aiServiceProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('⚙️ الإعدادات', style: GoogleFonts.cairo(
            fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [

        _Section(title: '🤖 حماده AI', children: [
          _InfoTile(label: 'النموذج',  value: ai.activeModelName),
          _InfoTile(label: 'المحرك',   value: ai.activeBackendName),
          ValueListenableBuilder<bool>(
            valueListenable: aiReadyNotifier,
            builder: (_, ready, __) => Column(children: [
              _InfoTile(label: 'الحالة', value: ready ? '✅ جاهز' : '⚠️ محتاج API key'),
              _InfoTile(label: 'باقي الطلبات/دقيقة',
                  value: ready ? '${ai.remainingRequests}/25' : '--'),
            ]),
          ),
        ]),
        const Gap(12),

        _Section(title: '🔑 Groq API Key', children: [
          Text('محفوظ على جهازك فقط — مش بيتبعت لأي مكان',
            style: GoogleFonts.cairo(
                fontSize: 11.5, color: AppColors.success)),
          const Gap(10),
          TextField(
            controller:    _keyCtrl,
            obscureText:   _obscure,
            textDirection: TextDirection.ltr,
            style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'gsk_... (فاضي = ما تغيرش)',
              hintStyle: GoogleFonts.cairo(
                  color: AppColors.textHint, fontSize: 11),
              suffixIcon: IconButton(
                icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: AppColors.textSecondary, size: 16),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const Gap(8),
          if (_keyMsg != null) Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_keyMsg!, style: GoogleFonts.cairo(
                fontSize: 12,
                color: _keyMsg!.contains('✅')
                    ? AppColors.success
                    : AppColors.error)),
          ),
          ElevatedButton(
            onPressed: _saving ? null : _saveKey,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text('حفظ الـ Key', style: GoogleFonts.cairo()),
          ),
        ]),
        const Gap(12),


        // ── BIOMETRIC SECTION ─────────────────────────────────
        _Section(title: '🔒 قفل التطبيق ببصمتك', children: [
          FutureBuilder<bool>(
            future: ref.read(biometricServiceProvider).isAvailable(),
            builder: (_, snap) {
              final available = snap.data ?? false;
              if (!available) {
                return Text(
                  'الجهاز ده مش بيدعم البصمة',
                  style: GoogleFonts.cairo(
                      fontSize: 12, color: AppColors.textHint),
                );
              }
              return FutureBuilder<bool>(
                future: ref.read(biometricServiceProvider).isEnabled(),
                builder: (_, snap2) {
                  final enabled = snap2.data ?? false;
                  return SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'تفعيل قفل البصمة',
                      style: GoogleFonts.cairo(
                          fontSize: 13, color: AppColors.textPrimary),
                    ),
                    subtitle: Text(
                      'محتاج بصمتك عشان تفتح التطبيق',
                      style: GoogleFonts.cairo(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                    value:   enabled,
                    activeColor: AppColors.primary,
                    onChanged: (v) async {
                      if (v) {
                        final ok = await ref
                            .read(biometricServiceProvider)
                            .authenticate();
                        if (ok) {
                          await ref
                              .read(biometricServiceProvider)
                              .setEnabled(true);
                          setState(() {});
                        }
                      } else {
                        await ref
                            .read(biometricServiceProvider)
                            .setEnabled(false);
                        setState(() {});
                      }
                    },
                  );
                },
              );
            },
          ),
        ]),
        const Gap(12),
        // ── BACKUP SECTION ────────────────────────────────────
        _Section(title: '💾 النسخ الاحتياطي', children: [
          Text(
            'النسخة الاحتياطية تشمل: كل المحادثات والذاكرة والملاحظات والفلوس والمهام',
            style: GoogleFonts.cairo(
                fontSize: 11.5, color: AppColors.textSecondary, height: 1.5),
          ),
          const Gap(12),
          Row(children: [
            Expanded(child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              icon:  _backing
                  ? const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.upload_outlined, size: 16),
              label: Text('تصدير نسخة احتياطية',
                  style: GoogleFonts.cairo(fontSize: 13)),
              onPressed: _backing || _restoring ? null : _exportBackup,
            )),
            const Gap(8),
            Expanded(child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
              ),
              icon: _restoring
                  ? const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary))
                  : const Icon(Icons.download_outlined, size: 16),
              label: Text('استرجاع نسخة',
                  style: GoogleFonts.cairo(fontSize: 13)),
              onPressed: _backing || _restoring ? null : _importBackup,
            )),
          ]),

          const Gap(8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.success,
                side: const BorderSide(color: AppColors.success),
              ),
              icon: const Icon(Icons.table_chart_outlined, size: 16),
              label: Text('تصدير Excel/CSV للبيانات المالية',
                  style: GoogleFonts.cairo(fontSize: 13)),
              onPressed: () async {
                try {
                  await ref.read(exportServiceProvider).exportAllDataCSV();
                } catch (e) {
                  if (mounted) _showSnack('فشل التصدير: $e', isError: true);
                }
              },
            ),
          ),
          const Gap(8),
          Text(
            '💡 احتفظ بالنسخة في Google Drive أو iCloud يدوياً',
            style: GoogleFonts.cairo(
                fontSize: 11, color: AppColors.textHint),
          ),
        ]),
        const Gap(12),

        _Section(title: '🔒 الخصوصية', children: [
          _InfoTile(label: 'ذاكرة + ملاحظات + فلوس', value: '📱 على جهازك'),
          _InfoTile(label: 'Groq بيشوف',              value: 'رسالتك + context'),
          _InfoTile(label: 'Groq بيحفظ',              value: 'لا (بحسب سياستهم)'),
        ]),
        const Gap(12),

        _Section(title: '🗃️ إحصائيات', children: [
          FutureBuilder<Map<String, int>>(
            future: ref.read(databaseHelperProvider).getDatabaseStats(),
            builder: (_, snap) {
              if (!snap.hasData) return const LinearProgressIndicator(
                  color: AppColors.primary);
              final s = snap.data!;
              return Column(children: [
                _InfoTile(label: 'رسائل',           value: '${s['messages']                ?? 0}'),
                _InfoTile(label: 'ذكريات حماده',    value: '${s['memories']                ?? 0}'),
                _InfoTile(label: 'ملاحظات',         value: '${s['user_notes']              ?? 0}'),
                _InfoTile(label: 'معاملات مالية',   value: '${s['finance_transactions']    ?? 0}'),
                _InfoTile(label: 'مهام',            value: '${s['tasks']                   ?? 0}'),
                _InfoTile(label: 'أهداف مالية',     value: '${s['financial_goals']         ?? 0}'),
                _InfoTile(label: 'معاملات متكررة',  value: '${s['recurring_transactions']  ?? 0}'),
              ]);
            },
          ),
          const Gap(10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
            ),
            icon:  const Icon(Icons.delete_outline, size: 16),
            label: Text('حذف كل البيانات والإعادة',
                style: GoogleFonts.cairo()),
            onPressed: () => _confirmClear(context),
          ),
        ]),
        const Gap(12),

        _Section(title: 'ℹ️ عن حماده AI', children: [
          _InfoTile(label: 'الإصدار', value: '2.0.0'),
          _InfoTile(label: 'الموديل', value: 'Llama 3.3 70B via Groq'),
          _InfoTile(label: 'الميزات', value: 'Voice • Backup • Goals • Recurring'),
          const Gap(8),
          Text(
            '"ذاكرتك وبياناتك على جهازك — حماده بس بيفكر على Groq" 🔒',
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
                fontSize: 11.5, color: AppColors.success, height: 1.5)),
        ]),
        const Gap(40),
      ]),
    );
  }

  Future<void> _saveKey() async {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) return;
    if (!key.startsWith('gsk_') || key.length < 20) {
      setState(() => _keyMsg = '❌ الـ key لازم يبدأ بـ gsk_');
      return;
    }
    setState(() { _saving = true; _keyMsg = null; });
    try {
      final ok = await ref.read(aiServiceProvider).setApiKey(key);
      if (ok) {
        ref.read(chatNotifierProvider.notifier).refreshReadyState();
      }
      if (mounted) setState(() {
        _saving = false;
        _keyMsg = ok ? '✅ تم الحفظ بنجاح — حماده جاهز!' : '❌ key غير صحيح';
      });
      _keyCtrl.clear();
    } catch (_) {
      setState(() { _saving = false; _keyMsg = '❌ حصل خطأ'; });
    }
  }

  Future<void> _exportBackup() async {
    setState(() => _backing = true);
    try {
      final svc    = ref.read(backupServiceProvider);
      final result = await svc.exportBackup();
      if (mounted) {
        _showSnack(result.message,
            isError: !result.isSuccess && !result.isCancelled);
      }
    } finally {
      if (mounted) setState(() => _backing = false);
    }
  }

  Future<void> _importBackup() async {
    // Confirm first
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('استرجاع نسخة احتياطية؟',
            style: GoogleFonts.cairo(color: AppColors.textPrimary)),
        content: Text(
            'ده هيستبدل كل البيانات الموجودة دلوقتي بالنسخة الاحتياطية. متعملش ده من غير نسخة احتياطية أولاً.',
            style: GoogleFonts.cairo(
                color: AppColors.textSecondary, height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('إلغاء', style: GoogleFonts.cairo())),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('استرجع',
                  style: GoogleFonts.cairo(color: AppColors.warning))),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _restoring = true);
    try {
      final svc    = ref.read(backupServiceProvider);
      final result = await svc.importBackup();
      if (mounted) {
        _showSnack(result.message,
            isError: !result.isSuccess && !result.isCancelled);
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.cairo()),
      backgroundColor: isError ? AppColors.error : AppColors.success,
      duration: const Duration(seconds: 4),
    ));
  }

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('حذف كل البيانات؟',
            style: GoogleFonts.cairo(color: AppColors.textPrimary)),
        content: Text(
            'هيتحذف كل المحادثات والملاحظات والبيانات المالية والأهداف.',
            style: GoogleFonts.cairo(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('إلغاء', style: GoogleFonts.cairo())),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(databaseHelperProvider).clearAll();
              await ref.read(aiServiceProvider).clearApiKey();
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('onboarding_complete', false);
              // ✅ Reset router onboarding cache so it re-reads from disk
              resetOnboardingCache();
              if (context.mounted) context.go(AppRoutes.onboarding);
            },
            child: Text('احذف',
                style: GoogleFonts.cairo(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String       title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    padding:    const EdgeInsets.all(14),
    decoration: BoxDecoration(
        color:        AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.inputBorder, width: 0.5)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: GoogleFonts.cairo(
          fontSize: 13, fontWeight: FontWeight.bold,
          color: AppColors.textSecondary)),
      const Divider(color: AppColors.inputBorder, height: 16),
      ...children,
    ]),
  );
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
      Expanded(child: Text(label, style: GoogleFonts.cairo(
          fontSize: 13, color: AppColors.textSecondary))),
      const Gap(8),
      Text(value, style: GoogleFonts.cairo(
          fontSize: 13,
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500)),
    ]),
  );
}
