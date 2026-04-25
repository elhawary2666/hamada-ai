// lib/core/services/widget_service.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database_helper.dart';
import '../di/providers.dart';
import '../services/ai_service.dart';

part 'widget_service.g.dart';

@riverpod
WidgetService widgetService(WidgetServiceRef ref) => WidgetService(
      db: ref.watch(databaseHelperProvider),
      ai: ref.watch(aiServiceProvider),
    );

class WidgetService {
  WidgetService({required this.db, required this.ai});
  final DatabaseHelper db;
  final AiService      ai;

  /// Push latest data to Android HomeScreen widget via SharedPreferences
  Future<void> updateWidget() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Top task
      final task = await db.getTopTodayTask();
      final topTask = task != null
          ? (task['title'] as String? ?? 'مهمة اليوم')
          : 'لا توجد مهام اليوم';

      // Monthly balance
      final now     = DateTime.now();
      final summary = await db.getMonthSummary(now.year, now.month);
      final balance = ((summary['income'] ?? 0.0) - (summary['expense'] ?? 0.0))
          .toStringAsFixed(0);

      // Short AI message
      final message = await ai.getWidgetMessage();
      final hasKey  = await ai.hasApiKey();

      await prefs.setString('widget_top_task', topTask);
      await prefs.setString('widget_balance',  balance);
      await prefs.setString('widget_message',  message);
      await prefs.setBool('widget_has_key',    hasKey);
    } catch (_) {}
  }
}
