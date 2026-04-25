// test/unit/rate_limiter_test.dart
import 'package:flutter_test/flutter_test.dart';

// Extracted rate limiter logic for testing
class RateLimiter {
  static const _minGapMs     = 500;
  static const _maxPerMinute = 25;

  final _timestamps = <int>[];
  int _lastMs       = 0;

  bool canSend() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastMs < _minGapMs) return false;
    final cutoff = now - 60000;
    _timestamps.removeWhere((t) => t < cutoff);
    return _timestamps.length < _maxPerMinute;
  }

  void record() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastMs = now;
    _timestamps.add(now);
  }

  int get remaining {
    final now    = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - 60000;
    _timestamps.removeWhere((t) => t < cutoff);
    return _maxPerMinute - _timestamps.length;
  }
}

void main() {
  group('RateLimiter', () {
    test('allows first send', () {
      final rl = RateLimiter();
      expect(rl.canSend(), true);
    });

    test('blocks immediate re-send', () {
      final rl = RateLimiter();
      rl.record();
      expect(rl.canSend(), false);
    });

    test('remaining starts at max', () {
      final rl = RateLimiter();
      expect(rl.remaining, 25);
    });

    test('remaining decreases on record', () {
      final rl = RateLimiter();
      rl.record();
      expect(rl.remaining, 24);
    });

    test('blocks after 25 records', () {
      final rl = RateLimiter();
      // Simulate 25 sends with time gaps
      for (int i = 0; i < 25; i++) {
        rl._timestamps.add(DateTime.now().millisecondsSinceEpoch);
      }
      rl._lastMs = DateTime.now().millisecondsSinceEpoch - 1000;
      expect(rl.canSend(), false);
      expect(rl.remaining, 0);
    });
  });
}
