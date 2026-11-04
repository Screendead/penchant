import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';

import 'dst.dart';

void main() {
  test('day arithmetic stays on calendar days', () {
    final DateTime day = DateTime(2026, 3, 29);

    expect(addDays(day, 1), DateTime(2026, 3, 30));
    expect(addDays(day, -29), DateTime(2026, 2, 28));
    expect(addDays(DateTime(2026, 12, 31), 1), DateTime(2027));
    expect(startOfDay(DateTime(2026, 3, 29, 23, 59)), day);
    expect(daysBetween(DateTime(2026, 3, 28, 23), DateTime(2026, 3, 30, 1)), 2);
    expect(daysBetween(day, day), 0);
  });

  final DateTime? transition = firstDstTransitionDay(2026);

  test(
    'day arithmetic crosses a DST transition to the next local midnight',
    () {
      final DateTime day = transition!;
      final DateTime next = addDays(day, 1);

      expect(next.difference(day).inHours, isNot(24));
      expect(next, DateTime(day.year, day.month, day.day + 1));
      expect(next.hour, 0);
      expect(addDays(next, -1), day);
      expect(daysBetween(day, next), 1);
    },
    skip: transition == null ? noDstSkipReason : false,
  );
}
