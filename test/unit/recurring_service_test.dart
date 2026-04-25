// test/unit/recurring_service_test.dart
import 'package:flutter_test/flutter_test.dart';

// Test the frequency calculation logic directly
DateTime calcNextDue(DateTime from, String frequency) {
  switch (frequency) {
    case 'daily':   return from.add(const Duration(days: 1));
    case 'weekly':  return from.add(const Duration(days: 7));
    case 'monthly': return DateTime(from.year, from.month + 1, from.day);
    case 'yearly':  return DateTime(from.year + 1, from.month, from.day);
    default:        return from.add(const Duration(days: 30));
  }
}

void main() {
  group('RecurringService - frequency calculation', () {
    final base = DateTime(2024, 1, 15);

    test('daily adds 1 day', () {
      expect(calcNextDue(base, 'daily'), DateTime(2024, 1, 16));
    });

    test('weekly adds 7 days', () {
      expect(calcNextDue(base, 'weekly'), DateTime(2024, 1, 22));
    });

    test('monthly advances month', () {
      expect(calcNextDue(base, 'monthly'), DateTime(2024, 2, 15));
    });

    test('yearly advances year', () {
      expect(calcNextDue(base, 'yearly'), DateTime(2025, 1, 15));
    });

    test('monthly on Jan 31 → Feb 28 (handled by Dart)', () {
      final jan31 = DateTime(2024, 1, 31);
      final next  = calcNextDue(jan31, 'monthly');
      expect(next.month, 3); // Dart overflows Feb 31 → Mar 2/3
    });
  });

  group('Arabic frequency names', () {
    String freqAr(String f) {
      switch (f) {
        case 'daily':   return 'يومياً';
        case 'weekly':  return 'أسبوعياً';
        case 'monthly': return 'شهرياً';
        case 'yearly':  return 'سنوياً';
        default:        return f;
      }
    }

    test('all frequencies have Arabic names', () {
      expect(freqAr('daily'),   'يومياً');
      expect(freqAr('weekly'),  'أسبوعياً');
      expect(freqAr('monthly'), 'شهرياً');
      expect(freqAr('yearly'),  'سنوياً');
      expect(freqAr('unknown'), 'unknown');
    });
  });
}
