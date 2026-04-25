// lib/core/services/rate_limiter.dart
import 'package:shared_preferences/shared_preferences.dart';

/// يحمي من إرسال رسائل كتير بسرعة ويحافظ على الـ free tier
class RateLimiter {
  RateLimiter._();
  static final RateLimiter instance = RateLimiter._();

  static const _kMinIntervalMs    = 1500;  // 1.5 ثانية بين الرسائل
  static const _kDailyLimit       = 200;   // حد يومي آمن (الـ free tier = 14400)
  static const _kBurstLimit       = 5;     // ما أكترش من 5 رسائل في دقيقة
  static const _kBurstWindowMs    = 60000; // نافذة الـ burst = دقيقة

  int _lastRequestMs   = 0;
  final _burstTimestamps = <int>[];

  /// يرجع null لو مسموح، رسالة خطأ لو ممنوع
  Future<String?> checkAllowed() async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // تحقق من الفاصل الزمني الأدنى
    if (now - _lastRequestMs < _kMinIntervalMs) {
      return 'استنى ثانية بين الرسائل 😅';
    }

    // تحقق من الـ burst limit
    _burstTimestamps.removeWhere((t) => now - t > _kBurstWindowMs);
    if (_burstTimestamps.length >= _kBurstLimit) {
      return 'شوية شوية يا صاحبي — استنى دقيقة 🙏';
    }

    // تحقق من الحد اليومي
    final dailyCount = await _getDailyCount();
    if (dailyCount >= _kDailyLimit) {
      return 'وصلت للحد اليومي المحدد ($_kDailyLimit رسالة) — جرّب بكرة 🌙';
    }

    return null; // مسموح
  }

  void recordRequest() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastRequestMs = now;
    _burstTimestamps.add(now);
    _incrementDailyCount();
  }

  Future<int> _getDailyCount() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    if (prefs.getString('rl_date') != today) {
      await prefs.setString('rl_date', today);
      await prefs.setInt('rl_count', 0);
      return 0;
    }
    return prefs.getInt('rl_count') ?? 0;
  }

  Future<void> _incrementDailyCount() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    if (prefs.getString('rl_date') != today) {
      await prefs.setString('rl_date', today);
      await prefs.setInt('rl_count', 1);
    } else {
      final count = (prefs.getInt('rl_count') ?? 0) + 1;
      await prefs.setInt('rl_count', count);
    }
  }

  Future<int> getTodayCount() => _getDailyCount();

  String _todayKey() {
    final d = DateTime.now();
    return '${d.year}-${d.month}-${d.day}';
  }
}
