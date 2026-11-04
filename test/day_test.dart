import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/usage_graph_view.dart';

import 'fakes.dart';

DateTime? firstDstTransitionDay(int year) {
  for (int i = 0; i < 365; i++) {
    final DateTime day = DateTime(year, 1, 1 + i);

    if (day.timeZoneOffset != DateTime(year, 1, 2 + i).timeZoneOffset) {
      return day;
    }
  }

  return null;
}

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

  // Dart cannot change the process timezone, so this only discriminates when
  // the runner's local zone observes DST (e.g. TZ=Europe/London flutter test).
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
    skip: transition == null
        ? 'local timezone has no DST transition in 2026; '
              'run with TZ=Europe/London to exercise it'
        : false,
  );

  test('the usage graph buckets entries by calendar day and by week', () {
    final DateTime start = DateTime(2026, 3, 28);

    expect(
      UsageGraphView.bucketTotals(
        activities: [
          fakeActivity('v', 1, start),
          fakeActivity('v', 2, DateTime(2026, 3, 30, 23, 59)),
          fakeActivity('v', 4, DateTime(2026, 4, 3, 23, 59)),
          fakeActivity('v', 8, DateTime(2026, 4, 4)),
          fakeActivity('v', 16, DateTime(2026, 3, 27, 23, 59)),
        ],
        rangeStart: start,
        rangeDays: 7,
        stepDays: 1,
      ),
      [1, 0, 2, 0, 0, 0, 4],
    );
    expect(
      UsageGraphView.bucketTotals(
        activities: [
          fakeActivity('v', 1, DateTime(2026, 4, 3, 23, 59)),
          fakeActivity('v', 2, DateTime(2026, 4, 4)),
        ],
        rangeStart: start,
        rangeDays: 14,
        stepDays: 7,
      ),
      [1, 2],
    );
  });

  test(
    'the usage graph puts an entry just after midnight on its own day across '
    'a DST transition',
    () {
      final DateTime day = transition!;
      final DateTime next = addDays(day, 1);

      expect(
        UsageGraphView.bucketTotals(
          activities: [
            fakeActivity(
              'v',
              1,
              DateTime(day.year, day.month, day.day, 23, 30),
            ),
            fakeActivity(
              'v',
              2,
              DateTime(next.year, next.month, next.day, 0, 30),
            ),
          ],
          rangeStart: addDays(day, -1),
          rangeDays: 3,
          stepDays: 1,
        ),
        [0, 1, 2],
      );
    },
    skip: transition == null
        ? 'local timezone has no DST transition in 2026; '
              'run with TZ=Europe/London to exercise it'
        : false,
  );
}
