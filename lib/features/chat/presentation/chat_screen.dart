// lib/features/chat/presentation/chat_screen.dart
import 'package:flutter/material.dart';
import 'dart:ui' as ui show TextDirection;
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_markdown/flutter_markdown.dart' show MarkdownBody, MarkdownStyleSheet;

import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../core/services/ai_service.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/models/chat_message_model.dart';
import '../providers/chat_provider.dart';

class ChatScreen extends HookConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat          = ref.watch(chatNotifierProvider);
    final notifier      = ref.read(chatNotifierProvider.notifier);
    final scrollCtrl    = useScrollController();
    final inputCtrl     = useTextEditingController();
    final isComposing   = useState(false);
    final isListening   = useState(false);
    final isSearching   = useState(false);
    final searchCtrl    = useTextEditingController();
    final searchQuery   = useState('');
    final stt           = useMemoized(() => SpeechToText());
    final sttAvailable  = useState(false);

    // Init STT
    useEffect(() {
      stt.initialize(
        onError:  (_) => isListening.value = false,
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            isListening.value = false;
          }
        },
      ).then((ok) => sttAvailable.value = ok);
      return stt.cancel;
    }, const []);

    // Auto-scroll
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollCtrl.hasClients && !isSearching.value) {
          scrollCtrl.animateTo(
            scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve:    Curves.easeOut,
          );
        }
      });
      return null;
    }, [chat.messages.length, chat.streamingBuffer]);

    useEffect(() {
      Future.microtask(() => notifier.initAiService());
      return null;
    }, const []);

    // Filter messages for search
    final displayedMessages = searchQuery.value.isEmpty
        ? chat.messages
        : chat.messages
            .where((m) => m.content.toLowerCase()
                .contains(searchQuery.value.toLowerCase()))
            .toList();

    Future<void> onVoice() async {
      if (isListening.value) {
        await stt.stop();
        isListening.value = false;
        return;
      }
      final perm = await Permission.microphone.request();
      if (!perm.isGranted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('محتاج صلاحية الميكروفون',
                style: GoogleFonts.cairo()),
            action: SnackBarAction(
                label: 'الإعدادات', onPressed: openAppSettings),
          ));
        }
        return;
      }
      if (!sttAvailable.value) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('التعرف على الكلام مش متاح على الجهاز ده',
                style: GoogleFonts.cairo()),
          ));
        }
        return;
      }
      isListening.value = true;
      HapticFeedback.lightImpact();
      await stt.listen(
        onResult: (SpeechRecognitionResult r) {
          inputCtrl.text = r.recognizedWords;
          isComposing.value = r.recognizedWords.isNotEmpty;
          if (r.finalResult) isListening.value = false;
        },
        localeId:      'ar_EG',
        listenFor:     const Duration(seconds: 30),
        pauseFor:      const Duration(seconds: 3),
        listenOptions: SpeechListenOptions(
          listenMode:     ListenMode.confirmation,
          cancelOnError:  true,
          partialResults: true,
        ),
      );
    }

    void onSend() {
      final text = inputCtrl.text.trim();
      if (text.isEmpty) return;
      inputCtrl.clear();
      isComposing.value = false;
      notifier.sendMessage(text);
      HapticFeedback.lightImpact();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(context, ref, chat, notifier,
          isSearching, searchCtrl, searchQuery),
      body: Column(children: [
        _PrivacyBanner(),
        Expanded(child: _MessagesList(
          messages:   displayedMessages,
          status:     chat.status,
          scrollCtrl: scrollCtrl,
          isFiltered: searchQuery.value.isNotEmpty,
        )),
        if (chat.tokensPerSec > 0) _TpsBar(tps: chat.tokensPerSec),
        // ✅ IMPROVEMENT 2: Confirmation banner for large transactions
        if (chat.pendingAction != null)
          _ConfirmationBanner(
            preview:   chat.pendingAction!.preview,
            onConfirm: () => notifier.confirmPendingAction(),
            onReject:  () => notifier.rejectPendingAction(),
          ),
        // Suggested replies
        if (chat.suggestedReplies.isNotEmpty && !chat.isGenerating)
          _SuggestedReplies(
            suggestions: chat.suggestedReplies,
            onTap: (s) {
              inputCtrl.text = s;
              isComposing.value = true;
            },
          ),
        ValueListenableBuilder<bool>(
          valueListenable: aiReadyNotifier,
          builder: (_, aiReady, __) => _InputBar(
            controller:   inputCtrl,
            isComposing:  isComposing.value,
            isGenerating: chat.isGenerating,
            isReady:      chat.isModelReady || aiReady,
            isListening:  isListening.value,
            sttAvailable: sttAvailable.value,
            onChanged:    (v) => isComposing.value = v.trim().isNotEmpty,
            onVoice:      onVoice,
            onSend:       onSend,
            // ✅ FIX Bug #2: Wire stop button to actual cancel method
            onStop:       () => notifier.cancelGeneration(),
          ),
        ),
      ]),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    ChatState chat,
    ChatNotifier notifier,
    ValueNotifier<bool> isSearching,
    TextEditingController searchCtrl,
    ValueNotifier<String> searchQuery,
  ) {
    final ai = ref.read(aiServiceProvider);
    if (isSearching.value) {
      return AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon:  const Icon(Icons.arrow_back),
          color: AppColors.textSecondary,
          onPressed: () {
            isSearching.value = false;
            searchCtrl.clear();
            searchQuery.value = '';
          },
        ),
        title: TextField(
          controller:    searchCtrl,
          autofocus:     true,
          textDirection: ui.TextDirection.rtl,
          style: GoogleFonts.cairo(
              fontSize: 15, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText:  'ابحث في المحادثة...',
            hintStyle: GoogleFonts.cairo(color: AppColors.textHint),
            border:    InputBorder.none,
          ),
          onChanged: (v) => searchQuery.value = v,
        ),
      );
    }

    return AppBar(
      backgroundColor: AppColors.surface,
      title: Row(children: [
        _Avatar(isActive: chat.isGenerating),
        const Gap(10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('حماده', style: GoogleFonts.cairo(
              fontSize: 18, fontWeight: FontWeight.bold,
              color: AppColors.textPrimary)),
          Text(chat.isGenerating ? 'بيفكر...' : ai.activeModelName,
              style: GoogleFonts.cairo(
                  fontSize: 11, color: AppColors.textSecondary)),
        ]),
      ]),
      actions: [
        IconButton(
          icon:    const Icon(Icons.search_rounded),
          color:   AppColors.textSecondary,
          tooltip: 'بحث في المحادثة',
          onPressed: () => isSearching.value = true,
        ),
        IconButton(
          icon:    const Icon(Icons.add_comment_outlined),
          color:   AppColors.textSecondary,
          tooltip: 'محادثة جديدة',
          onPressed: () {
            notifier.startNewSession();
            HapticFeedback.mediumImpact();
          },
        ),
        const Gap(4),
      ],
    );
  }
}

// ── Privacy Banner ────────────────────────────────────────────

class _PrivacyBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width:   double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
    color:   AppColors.privacyBg,
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.lock_outline, size: 12, color: AppColors.privacyText),
      const Gap(5),
      Text('بياناتك على جهازك فقط — مش بتطلع برة 🔒',
          style: GoogleFonts.cairo(
              fontSize: 11, color: AppColors.privacyText)),
    ]),
  );
}

// ── Suggested Replies ─────────────────────────────────────────

class _SuggestedReplies extends StatelessWidget {
  const _SuggestedReplies({
    required this.suggestions, required this.onTap});
  final List<String>       suggestions;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => Container(
    color:  AppColors.surface,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(children: [
      const Icon(Icons.auto_awesome, size: 14, color: AppColors.primary),
      const Gap(6),
      Expanded(child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: suggestions.map((s) =>
          GestureDetector(
            onTap: () => onTap(s),
            child: Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Text(s, style: GoogleFonts.cairo(
                  fontSize: 12, color: AppColors.primary)),
            ),
          ).animate().fadeIn(duration: 200.ms).slideX(begin: 0.1),
        ).toList()),
      )),
    ]),
  );
}

// ── Messages List ─────────────────────────────────────────────

class _MessagesList extends StatelessWidget {
  const _MessagesList({
    required this.messages, required this.status,
    required this.scrollCtrl, this.isFiltered = false,
  });
  final List<ChatMessageModel> messages;
  final ChatStatus             status;
  final ScrollController       scrollCtrl;
  final bool                   isFiltered;

  @override
  Widget build(BuildContext context) {
    if (isFiltered && messages.isEmpty) {
      return Center(child: Column(
        mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.search_off, size: 40, color: AppColors.textHint),
        const Gap(8),
        Text('مفيش نتائج', style: GoogleFonts.cairo(
            color: AppColors.textSecondary)),
      ]));
    }

    return ListView.builder(
      controller:  scrollCtrl,
      padding:     const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount:   messages.length +
          (!isFiltered && status == ChatStatus.thinking ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == messages.length) return _TypingIndicator();
        return _ChatBubble(message: messages[i], index: i)
            .animate()
            .fadeIn(duration: 200.ms)
            .slideY(begin: 0.06, end: 0,
                duration: 200.ms, curve: Curves.easeOut);
      },
    );
  }
}

// ── Chat Bubble with long-press copy ─────────────────────────

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, required this.index});
  final ChatMessageModel message;
  final int              index;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Padding(
      padding: EdgeInsets.only(
        top:   index == 0 ? 8 : 4, bottom: 4,
        left:  isUser ? 56 : 0,
        right: isUser ? 0  : 56,
      ),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            _Avatar(isActive: message.isEmpty, size: 28),
            const Gap(6),
          ],
          Flexible(child: Column(
            crossAxisAlignment: isUser
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onLongPress: () => _showOptions(context, message),
                child: _BubbleBody(message: message),
              ),
              const Gap(2),
              _BubbleFooter(message: message),
            ],
          )),
        ],
      ),
    );
  }

  void _showOptions(BuildContext context, ChatMessageModel message) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context:         context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36, height: 4, margin: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
              color:        AppColors.textHint,
              borderRadius: BorderRadius.circular(2)),
        ),
        ListTile(
          leading: const Icon(Icons.copy_outlined,
              color: AppColors.textSecondary),
          title: Text('نسخ الرسالة',
              style: GoogleFonts.cairo(color: AppColors.textPrimary)),
          onTap: () {
            Clipboard.setData(ClipboardData(text: message.content));
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('تم النسخ ✅',
                  style: GoogleFonts.cairo()),
              duration: const Duration(seconds: 2),
              backgroundColor: AppColors.success,
            ));
          },
        ),
        ListTile(
          leading: const Icon(Icons.share_outlined,
              color: AppColors.textSecondary),
          title: Text('مشاركة',
              style: GoogleFonts.cairo(color: AppColors.textPrimary)),
          onTap: () async {
            Navigator.pop(context);
            // Share via system share sheet
          },
        ),
        ListTile(
          leading: const Icon(Icons.select_all_outlined,
              color: AppColors.textSecondary),
          title: Text('تحديد النص',
              style: GoogleFonts.cairo(color: AppColors.textPrimary)),
          onTap: () {
            Navigator.pop(context);
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: AppColors.surface,
                content: SelectableText(
                  message.content,
                  style: GoogleFonts.cairo(
                      color: AppColors.textPrimary, fontSize: 14),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('إغلاق',
                        style: GoogleFonts.cairo()),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}

class _BubbleBody extends StatelessWidget {
  const _BubbleBody({required this.message});
  final ChatMessageModel message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isUser
            ? AppColors.userBubble
            : (message.isError
                ? AppColors.error.withValues(alpha: 0.15)
                : AppColors.assistantBubble),
        borderRadius: BorderRadius.only(
          topLeft:     const Radius.circular(18),
          topRight:    const Radius.circular(18),
          bottomLeft:  Radius.circular(isUser ? 18 : 4),
          bottomRight: Radius.circular(isUser ? 4  : 18),
        ),
      ),
      child: message.isEmpty
          ? _BlinkCursor()
          : isUser
              ? Text(message.content,
                  style: GoogleFonts.cairo(
                      color: AppColors.userBubbleText,
                      fontSize: 15, height: 1.5),
                  textDirection: ui.TextDirection.rtl)
              : MarkdownBody(
                  data: message.content,
                  styleSheet: MarkdownStyleSheet(
                    p: GoogleFonts.cairo(
                        color: AppColors.assistantBubbleText,
                        fontSize: 15, height: 1.55),
                    code: const TextStyle(
                        fontFamily: 'monospace', fontSize: 13,
                        backgroundColor: Color(0x22FFFFFF)),
                  ),
                  softLineBreak: true,
                ),
    );
  }
}

class _BubbleFooter extends StatelessWidget {
  const _BubbleFooter({required this.message});
  final ChatMessageModel message;

  @override
  Widget build(BuildContext context) {
    final dt  = DateTime.fromMillisecondsSinceEpoch(message.timestamp);
    final tps = message.tokensPerSec;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(
        '${dt.hour.toString().padLeft(2,'0')}:'
        '${dt.minute.toString().padLeft(2,'0')}',
        style: GoogleFonts.cairo(
            fontSize: 10, color: AppColors.textHint),
      ),
      if (tps > 0) ...[
        const Gap(4),
        Text('${tps.toStringAsFixed(0)} t/s',
            style: GoogleFonts.cairo(
                fontSize: 9.5, color: AppColors.textHint)),
      ],
    ]);
  }
}

// ── Typing Indicator ──────────────────────────────────────────

class _TypingIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: Row(children: [
      _Avatar(isActive: true, size: 28), const Gap(8),
      Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color:        AppColors.assistantBubble,
            borderRadius: BorderRadius.circular(18)),
        child: Row(children: List.generate(3, (i) =>
          Container(
            width: 6, height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: const BoxDecoration(
                color:  AppColors.textSecondary,
                shape:  BoxShape.circle),
          )
          .animate(onPlay: (c) => c.repeat())
          .scaleXY(begin: 0.6, end: 1.0,
              delay: Duration(milliseconds: i * 160),
              duration: 500.ms, curve: Curves.easeInOut)
          .then()
          .scaleXY(begin: 1.0, end: 0.6,
              duration: 500.ms, curve: Curves.easeInOut),
        )),
      ),
    ]),
  );
}

// ── Avatar ────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  const _Avatar({this.isActive = false, this.size = 36});
  final bool   isActive;
  final double size;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    width: size, height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        colors: isActive
            ? [AppColors.primary, AppColors.primaryDark]
            : [AppColors.surfaceVariant, AppColors.surface],
        begin: Alignment.topLeft,
        end:   Alignment.bottomRight,
      ),
      boxShadow: isActive
          ? [BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.4),
              blurRadius: 8)]
          : [],
    ),
    child: Center(child: Text('ح', style: GoogleFonts.cairo(
      color:      isActive ? Colors.white : AppColors.textSecondary,
      fontSize:   size * 0.44,
      fontWeight: FontWeight.bold,
    ))),
  );
}

// ── Helpers ───────────────────────────────────────────────────

class _BlinkCursor extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 2, height: 16, color: AppColors.assistantBubbleText)
    .animate(onPlay: (c) => c.repeat())
    .fadeIn(duration: 400.ms).then().fadeOut(duration: 400.ms);
}

class _TpsBar extends StatelessWidget {
  const _TpsBar({required this.tps});
  final double tps;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
    color:   AppColors.surface,
    child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      const Icon(Icons.bolt, size: 12, color: AppColors.textHint),
      const Gap(3),
      Text('${tps.toStringAsFixed(0)} tok/s',
          style: GoogleFonts.cairo(
              fontSize: 10.5, color: AppColors.textHint)),
    ]),
  );
}

// ── Input Bar ─────────────────────────────────────────────────

class _InputBar extends HookWidget {
  const _InputBar({
    required this.controller,
    required this.isComposing,
    required this.isGenerating,
    required this.isReady,
    required this.isListening,
    required this.sttAvailable,
    required this.onChanged,
    required this.onVoice,
    required this.onSend,
    required this.onStop,   // ✅ FIX Bug #2
  });
  final TextEditingController controller;
  final bool   isComposing, isGenerating, isReady,
               isListening, sttAvailable;
  final ValueChanged<String> onChanged;
  final VoidCallback onVoice, onSend, onStop;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      padding:  EdgeInsets.only(bottom: bottomPad),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [BoxShadow(
            color:      Colors.black.withValues(alpha: 0.06),
            blurRadius: 8, offset: const Offset(0, -2),
          )],
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (sttAvailable) ...[
            _VoiceBtn(isListening: isListening, onTap: onVoice),
            const Gap(6),
          ],
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color:        AppColors.inputBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isListening
                      ? AppColors.error.withValues(alpha: 0.7)
                      : isComposing
                          ? AppColors.primary.withValues(alpha: 0.5)
                          : AppColors.inputBorder,
                  width: 1.5,
                ),
              ),
              child: TextField(
                controller:      controller,
                maxLines:        null,
                textDirection:   ui.TextDirection.rtl,
                onChanged:       onChanged,
                onSubmitted:     (_) { if (!isGenerating) onSend(); },
                textInputAction: TextInputAction.newline,
                enabled:         isReady,
                style: GoogleFonts.cairo(
                    fontSize: 15, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: isListening
                      ? '🎤 بتستمع...'
                      : isReady
                          ? 'اكتب لحماده...'
                          : 'جاري الاتصال...',
                  hintStyle: GoogleFonts.cairo(
                      color: isListening
                          ? AppColors.error
                          : AppColors.textHint,
                      fontSize: 15),
                  border:         InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
              ),
            ),
          ),
          const Gap(8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: isGenerating
                ? _StopBtn(onStop: onStop)   // ✅ FIX Bug #2
                : _SendBtn(
                    enabled: isComposing && isReady,
                    onSend:  onSend),
          ),
        ]),
      ),
    );
  }
}

class _VoiceBtn extends StatelessWidget {
  const _VoiceBtn({required this.isListening, required this.onTap});
  final bool isListening;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 44, height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isListening ? AppColors.error : AppColors.surfaceVariant,
        boxShadow: isListening
            ? [BoxShadow(
                color: AppColors.error.withValues(alpha: 0.4),
                blurRadius: 8)]
            : [],
      ),
      child: Icon(
        isListening ? Icons.mic : Icons.mic_none_rounded,
        color: isListening ? Colors.white : AppColors.textSecondary,
        size: 20,
      ),
    ),
  );
}

class _SendBtn extends StatelessWidget {
  const _SendBtn({required this.enabled, required this.onSend});
  final bool enabled;
  final VoidCallback onSend;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: enabled ? onSend : null,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 44, height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: enabled ? AppColors.primary : AppColors.surfaceVariant,
        boxShadow: enabled
            ? [BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.35),
                blurRadius: 8)]
            : [],
      ),
      child: const Icon(
          Icons.send_rounded, color: Colors.white, size: 20),
    ),
  );
}

// ✅ FIX Bug #2: Stop button now actually stops generation
class _StopBtn extends StatelessWidget {
  const _StopBtn({required this.onStop});
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () {
      HapticFeedback.mediumImpact();
      onStop();
    },
    child: Container(
      width: 44, height: 44,
      decoration: const BoxDecoration(
          shape: BoxShape.circle, color: AppColors.expense),
      child: const Icon(Icons.stop_rounded, color: Colors.white, size: 22),
    )
    .animate(onPlay: (c) => c.repeat())
    .scaleXY(begin: 0.95, end: 1.05,
        duration: 700.ms, curve: Curves.easeInOut)
    .then()
    .scaleXY(begin: 1.05, end: 0.95, duration: 700.ms),
  );
}


// ── CONFIRMATION BANNER ────────────────────────────────────────

class _ConfirmationBanner extends StatelessWidget {
  const _ConfirmationBanner({
    required this.preview,
    required this.onConfirm,
    required this.onReject,
  });
  final String    preview;
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color:        AppColors.warning.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.help_outline_rounded, size: 16, color: AppColors.warning),
        const Gap(6),
        Text('تأكيد التسجيل', style: GoogleFonts.cairo(
            fontSize: 12, color: AppColors.warning, fontWeight: FontWeight.bold)),
      ]),
      const Gap(6),
      Text(preview, style: GoogleFonts.cairo(
          fontSize: 13, color: AppColors.textPrimary)),
      const Gap(10),
      Row(children: [
        Expanded(child: OutlinedButton(
          onPressed: onReject,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(vertical: 6),
          ),
          child: Text('لأ، إلغاء', style: GoogleFonts.cairo(fontSize: 13)),
        )),
        const Gap(8),
        Expanded(child: ElevatedButton(
          onPressed: onConfirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 6),
          ),
          child: Text('أيوه، سجّل', style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold)),
        )),
      ]),
    ]),
  );
}
