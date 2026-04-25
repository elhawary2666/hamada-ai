// lib/features/onboarding/presentation/onboarding_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/ai_service.dart';
import '../../../core/theme/app_colors.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _ctrl    = TextEditingController();
  bool  _loading = false;
  bool  _obscure = true;
  String? _error;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Gap(32),

            Center(child: _Logo()
                .animate().fadeIn(duration: 600.ms)
                .scale(begin: const Offset(0.8, 0.8))),
            const Gap(20),

            Center(child: Text('حماده AI', style: GoogleFonts.cairo(
              fontSize: 30, fontWeight: FontWeight.bold,
              color: AppColors.textPrimary)))
                .animate().fadeIn(delay: 200.ms),
            const Gap(6),
            Center(child: Text('مساعدك الشخصي الذكي — مجاني وسريع',
              style: GoogleFonts.cairo(fontSize: 14, color: AppColors.textSecondary)))
                .animate().fadeIn(delay: 300.ms),
            const Gap(36),

            ...[
              ('⚡', 'رد في أقل من ثانية'),
              ('🧠', 'بيتذكرك — ذاكرة دائمة على جهازك'),
              ('💰', 'مجاني تماماً — 14,400 رسالة يومياً'),
              ('🔒', 'بياناتك عندك مش عنده'),
            ].asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FeatureRow(icon: e.value.$1, text: e.value.$2)
                  .animate()
                  .fadeIn(delay: Duration(milliseconds: 400 + e.key * 80))
                  .slideX(begin: 0.15),
            )),
            const Gap(28),

            Container(
              padding:     const EdgeInsets.all(20),
              decoration:  BoxDecoration(
                color:        AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.inputBorder),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('خطوة واحدة بس 👇', style: GoogleFonts.cairo(
                  fontSize: 15, fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary)),
                const Gap(4),
                Text('روح groq.com ← سجّل مجاناً ← API Keys ← Create Key',
                  style: GoogleFonts.cairo(fontSize: 12,
                      color: AppColors.textSecondary, height: 1.5)),
                const Gap(14),

                TextField(
                  controller:    _ctrl,
                  obscureText:   _obscure,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontFamily: 'monospace',
                      fontSize: 13, color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText:  'gsk_...',
                    hintStyle: GoogleFonts.cairo(color: AppColors.textHint),
                    prefixIcon: const Icon(Icons.key_outlined,
                        color: AppColors.textSecondary, size: 18),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_outlined
                                 : Icons.visibility_off_outlined,
                        color: AppColors.textSecondary, size: 18,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    errorText: _error,
                    errorStyle: GoogleFonts.cairo(color: AppColors.error, fontSize: 11),
                  ),
                  onChanged: (_) { if (_error != null) setState(() => _error = null); },
                ),
                const Gap(14),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _save,
                    child: _loading
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text('ابدأ مع حماده ✨',
                            style: GoogleFonts.cairo(fontSize: 16)),
                  ),
                ),
              ]),
            ).animate().fadeIn(delay: 700.ms).slideY(begin: 0.15),
            const Gap(16),

            Center(child: Text(
              'الـ Key محفوظ على جهازك فقط — مش بيتبعت لأي حاجة تانية 🔒',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(fontSize: 11, color: AppColors.success),
            )),
            const Gap(24),
          ]),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final key = _ctrl.text.trim();
    if (key.isEmpty) { setState(() => _error = 'ادخل الـ API key'); return; }
    if (!key.startsWith('gsk_') || key.length < 20) {
      setState(() => _error = 'الـ key لازم يبدأ بـ gsk_'); return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final ai = ref.read(aiServiceProvider);
      final ok = await ai.setApiKey(key);
      if (!ok) { setState(() { _error = 'API key غير صحيح'; _loading = false; }); return; }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_complete', true);
      if (mounted) context.go(AppRoutes.chat);
    } catch (_) {
      setState(() { _error = 'حصل خطأ — جرب تاني'; _loading = false; });
    }
  }
}

class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 88, height: 88,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const LinearGradient(
        colors: [AppColors.primary, AppColors.primaryDark],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
      boxShadow: [BoxShadow(
        color: AppColors.primary.withOpacity(0.35), blurRadius: 24, spreadRadius: 4)],
    ),
    child: Center(child: Text('ح', style: GoogleFonts.cairo(
      color: Colors.white, fontSize: 46, fontWeight: FontWeight.bold))),
  );
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.text});
  final String icon, text;
  @override
  Widget build(BuildContext context) => Container(
    padding:    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.inputBorder, width: 0.5),
    ),
    child: Row(children: [
      Text(icon, style: const TextStyle(fontSize: 18)),
      const Gap(12),
      Expanded(child: Text(text, style: GoogleFonts.cairo(
          fontSize: 13, color: AppColors.textPrimary))),
    ]),
  );
}
