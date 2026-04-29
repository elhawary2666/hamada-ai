// lib/core/services/background_service.dart
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:workmanager/workmanager.dart';

import '../database/database_helper.dart';
import 'ai_service.dart';
import 'memory_service.dart';
import 'pattern_service.dart';
import 'self_heal_service.dart';

part 'background_service.g.dart';

// ── Task names ────────────────────────────────────────────────
abstract class BgTask {
  static const morning    = 'hamada_morning';
  static const evening    = 'hamada_evening';
  static const overdue    = 'hamada_overdue';
  static const debt       = 'hamada_debt';
  static const finance    = 'hamada_finance';
  static const memClean   = 'hamada_mem_clean';
  static const timeline   = 'hamada_timeline';
  static const patterns   = 'hamada_patterns';
  static const selfHeal   = 'hamada_self_heal';
  static const apptPrep   = 'hamada_appt_prep';
}

// ── Notification IDs ──────────────────────────────────────────
abstract class NotifId {
  static const morning  = 1001;
  static const evening  = 1002;
  static const tasks    = 1003;
  static const finance  = 1004;
  static const debt     = 1005;
  static const insight  = 1006;
  static const apptPrep = 1007;
}

// ── Channels ──────────────────────────────────────────────────
abstract class NotifChannel {
  static const daily   = 'hamada_daily';
  static const tasks   = 'hamada_tasks';
  static const finance = 'hamada_finance';
}

// ══════════════════════════════════════════════════════════════
// WORKMANAGER CALLBACK
// ══════════════════════════════════════════════════════════════

@pragma('vm:entry-point')
void workmanagerCallback() {
  Workmanager().executeTask((taskName, _) async {
    final log = Logger(printer: PrettyPrinter(methodCount: 0));
    log.i('⚙️ BG task: $taskName');

    try {
      final db      = DatabaseHelper.instance;
      final memory  = MemoryService(db: db);
      final ai      = AiService(db: db, memoryService: memory);
      final notif   = NotificationService();

      await notif.init();
      await ai.initialize();

      switch (taskName) {
        case BgTask.morning:
          final tasks = await db.getTodayTasks();
          final appts = await db.getUpcomingAppointments(withinDays: 1);
          final msg   = await ai.generateMorningGreeting(
            todayTasks:        tasks.take(3).map((t) => t['title'] as String).toList(),
            todayAppointments: appts.take(2).map((a) => a['title'] as String).toList(),
          );
          await notif.show(id: NotifId.morning,
              title: '🌅 صباح الخير من حماده', body: msg,
              channel: NotifChannel.daily);
          break;

        case BgTask.evening:
          final pending = await db.getTodayTasks();
          final msg = await ai.generateEveningSummary(
            pendingTasks: pending.where((t) => t['status'] == 'pending')
                .take(3).map((t) => t['title'] as String).toList(),
          );
          await notif.show(id: NotifId.evening,
              title: '🌙 مساء الخير يا صاحبي', body: msg,
              channel: NotifChannel.daily);
          break;

        case BgTask.overdue:
          final overdue = await db.getOverdueTasks();
          if (overdue.isNotEmpty) {
            final count = overdue.length;
            await notif.show(
              id: NotifId.tasks,
              title: '⏰ عندك $count مهمة متأخرة',
              body: '${overdue.first['title']}${count > 1 ? ' وغيرها' : ''} — يلا نخلصها! 💪',
              channel: NotifChannel.tasks,
            );
          }
          break;

        case BgTask.debt:
          // Filter unpaid debts due within 3 days using existing getAllDebts()
          final allDebts  = await db.getAllDebts();
          final cutoffMs  = DateTime.now().add(const Duration(days: 3)).millisecondsSinceEpoch;
          final debts     = allDebts.where((d) =>
              d['is_paid'] == 0 &&
              d['due_date'] != null &&
              (d['due_date'] as int) <= cutoffMs).toList();
          for (final d in debts.take(2)) {
            // direction: 'owe' = I owe (عليك), 'owed' = they owe me (عندك)
            final dir    = d['direction'] == 'owe' ? 'عليك' : 'عندك';
            final amount = d['amount'];
            final person = d['name'] as String;
            await notif.show(
              id: NotifId.debt,
              title: '💸 تذكير مالي',
              body: '$dir دين لـ $person بـ $amount جنيه — الموعد قرب 🔒',
              channel: NotifChannel.finance,
            );
          }
          break;

        case BgTask.finance:
          final now     = DateTime.now();
          // Correct method name is getMonthSummary (not getMonthlySummary)
          final summary = await db.getMonthSummary(now.year, now.month);
          final inc     = (summary['income']  ?? 0.0).toStringAsFixed(0);
          final exp     = (summary['expense'] ?? 0.0).toStringAsFixed(0);
          final net     = (summary['income'] ?? 0.0) - (summary['expense'] ?? 0.0);
          final netStr  = net >= 0
              ? '+ ${net.toStringAsFixed(0)}'
              : '- ${net.abs().toStringAsFixed(0)}';
          await notif.show(
            id: NotifId.finance,
            title: '📊 ملخص مالي أسبوعي',
            body: 'دخل: $inc ج | مصروف: $exp ج | صافي: $netStr ج\nالكلام ده بينا 🔒',
            channel: NotifChannel.finance,
          );
          break;

        case BgTask.memClean:
          await memory.pruneOldMemories();
          break;

        case BgTask.selfHeal:
          final healer = SelfHealService(db: db);
          final report = await healer.runHealthCheck();
          final anomalies = await healer.detectAnomalies();
          if (anomalies.isNotEmpty) {
            await notif.show(
              id:      NotifId.insight,
              title:   'حماده لاحظ حاجة',
              body:    anomalies.first,
              channel: NotifChannel.daily,
            );
          }
          break;

        case BgTask.timeline:
          final pSvc = PatternService(db: db, ai: ai);
          await pSvc.buildDailyTimeline(DateTime.now());
          break;

        case BgTask.patterns:
          final patSvc   = PatternService(db: db, ai: ai);
          final insights = await patSvc.analyzePatterns();
          if (insights.isNotEmpty && insights.first.confidence > 0.7) {
            await notif.show(
              id:      NotifId.insight,
              title:   'حماده لاحظ pattern',
              body:    insights.first.message,
              channel: NotifChannel.daily,
            );
          }
          break;

        case BgTask.apptPrep:
          final appts = await db.getUpcomingAppointments(withinDays: 1);
          if (appts.isNotEmpty) {
            final prepSvc = PatternService(db: db, ai: ai);
            final brief   = await prepSvc.getAppointmentBrief(appts.first);
            if (brief.isNotEmpty) {
              await notif.show(
                id:      NotifId.apptPrep,
                title:   'تجهيز لموعد بكرة: ${appts.first['title']}',
                body:    brief,
                channel: NotifChannel.daily,
              );
            }
          }
          break;
      }

      await ai.dispose();
      return true;
    } catch (e, st) {
      log.e('BG task failed', error: e, stackTrace: st);
      return false;
    }
  });
}

// ══════════════════════════════════════════════════════════════
// BACKGROUND SERVICE
// ══════════════════════════════════════════════════════════════

@riverpod
BackgroundService backgroundService(BackgroundServiceRef ref) =>
    BackgroundService();

class BackgroundService {
  final _log = Logger(printer: PrettyPrinter(methodCount: 0));

  Future<void> registerAllTasks() async {
    await Workmanager().cancelAll();

    final tasks = [
      (BgTask.morning,  const Duration(hours: 24),  _delayUntil(9)),
      (BgTask.evening,  const Duration(hours: 24),  _delayUntil(21)),
      (BgTask.overdue,  const Duration(hours: 24),  _delayUntil(8)),
      (BgTask.debt,     const Duration(hours: 24),  _delayUntil(10)),
      (BgTask.finance,  const Duration(days: 7),    _delayUntilFriday(19)),
      (BgTask.memClean, const Duration(days: 7),    const Duration(days: 1)),
      // New tasks
      (BgTask.timeline,  const Duration(hours: 24),  _delayUntil(23)),
      (BgTask.patterns,  const Duration(days: 3),    const Duration(hours: 6)),
      (BgTask.selfHeal,  const Duration(hours: 24),  const Duration(hours: 2)),
      (BgTask.apptPrep,  const Duration(hours: 12),  _delayUntil(20)),
    ];

    for (final t in tasks) {
      await Workmanager().registerPeriodicTask(
        t.$1, t.$1,
        frequency:          t.$2,
        initialDelay:       t.$3,
        existingWorkPolicy: ExistingWorkPolicy.replace,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    }

    _log.i('✅ Registered ${tasks.length} background tasks');
  }

  static Duration _delayUntil(int hour) {
    final now    = DateTime.now();
    var   target = DateTime(now.year, now.month, now.day, hour);
    if (target.isBefore(now)) target = target.add(const Duration(days: 1));
    return target.difference(now);
  }

  static Duration _delayUntilFriday(int hour) {
    final now  = DateTime.now();
    final days = (5 - now.weekday + 7) % 7;
    final t    = DateTime(now.year, now.month, now.day + (days == 0 ? 7 : days), hour);
    return t.difference(now);
  }
}

// ══════════════════════════════════════════════════════════════
// NOTIFICATION SERVICE
// ══════════════════════════════════════════════════════════════

@riverpod
NotificationService notificationService(NotificationServiceRef ref) =>
    NotificationService();

class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool  _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _createChannels();
    _initialized = true;
  }

  Future<void> _createChannels() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    for (final ch in [
      const AndroidNotificationChannel(
        NotifChannel.daily,   'رسائل حماده اليومية',
        description: 'صباح الخير والملخص المسائي',
        importance:  Importance.high,
      ),
      const AndroidNotificationChannel(
        NotifChannel.tasks,   'تذكيرات المهام',
        description: 'تذكيرات بالمهام المتأخرة',
        importance:  Importance.high,
      ),
      const AndroidNotificationChannel(
        NotifChannel.finance, 'الملخص المالي',
        description: 'ملخصات مالية أسبوعية',
        importance:  Importance.defaultImportance,
      ),
    ]) { await android.createNotificationChannel(ch); }
  }

  Future<void> show({
    required int    id,
    required String title,
    required String body,
    required String channel,
  }) async {
    if (!_initialized) await init();
    await _plugin.show(
      id, title, body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel, channel,
          importance:        Importance.high,
          priority:          Priority.high,
          styleInformation:  BigTextStyleInformation(body),
          color:             const Color(0xFF1A1A2E),
        ),
      ),
    );
  }

  Future<void> cancel(int id) => _plugin.cancel(id);
  Future<void> cancelAll()    => _plugin.cancelAll();
}
