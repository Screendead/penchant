import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/usage_series.dart';
import 'package:tracker/data/vice_activity.dart';

import 'dst.dart';
import 'fakes.dart';

final DateTime _today = DateTime(2026, 11, 4);

ViceActivity _at(int daysAgo, int quantity, {int hour = 12}) => fakeActivity(
  'coffee',
  quantity,
  addDays(_today, -daysAgo).add(Duration(hours: hour)),
);

void main() {
  group('usageRange', () {
    test('daily ranges are one bucket a day, ending today', () {
      for (final int days in const [7, 14, 30, 90, 180, 365]) {
        final UsageRange range = usageRange(_today, days, 1);
        expect(range.bucketCount, days);
        expect(range.days, days);
        expect(range.start, addDays(_today, 1 - days));
        expect(range.end, addDays(_today, 1));
        expect(range.bucketStart(days - 1), _today);
      }
    });

    test('weekly ranges cover every day picked, the newest week ending today '
        'and the oldest bucket holding the remainder', () {
      const Map<int, (int, int)> weeks = {
        7: (1, 7),
        14: (2, 7),
        30: (5, 2),
        90: (13, 6),
        180: (26, 5),
        365: (53, 1),
      };
      weeks.forEach((int days, (int, int) expected) {
        final (int count, int oldestDays) = expected;
        final UsageRange range = usageRange(_today, days, 7);
        expect(range.bucketCount, count, reason: '$days days');
        expect(range.days, days);
        expect(range.start, addDays(_today, 1 - days));
        expect(range.end, addDays(_today, 1));
        expect(range.bucketStart(0), range.start);
        expect(range.bucketStart(count - 1), addDays(_today, -6));
        final DateTime oldestEnd = count == 1
            ? range.end
            : range.bucketStart(1);
        expect(daysBetween(range.start, oldestEnd), oldestDays);
        for (int i = 1; i < count; i++) {
          final DateTime next = i + 1 < count
              ? range.bucketStart(i + 1)
              : range.end;
          expect(daysBetween(range.bucketStart(i), next), 7);
        }
      });
    });

    test('ignores the time of day of today', () {
      expect(
        usageRange(_today.add(const Duration(hours: 23)), 30, 1),
        usageRange(_today, 30, 1),
      );
    });

    test(
      'keeps calendar days across a daylight-saving change',
      () {
        // Each 365-day range spans a year, so it crosses every transition.
        for (final DateTime today in [
          DateTime(2026, 11, 4),
          DateTime(2026, 4, 2),
        ]) {
          final UsageRange range = usageRange(today, 365, 1);
          for (int i = 0; i < range.bucketCount; i++) {
            final DateTime start = range.bucketStart(i);
            expect(start, startOfDay(start));
          }
          expect(range.bucketStart(range.bucketCount - 1), today);
        }
      },
      skip: firstDstTransitionDay(2026) == null ? noDstSkipReason : false,
    );
  });

  group('bucketTotals', () {
    test('daily: one total per day, summing each day', () {
      final UsageRange range = usageRange(_today, 7, 1);
      expect(
        bucketTotals(range, [
          _at(0, 2),
          _at(0, 3, hour: 23),
          _at(1, 1, hour: 0),
          _at(6, 4),
        ]),
        [4, 0, 0, 0, 0, 1, 5],
      );
    });

    test('weekly: each bucket sums the seven days it covers', () {
      final UsageRange range = usageRange(_today, 14, 7);
      expect(
        bucketTotals(range, [_at(0, 1), _at(6, 2), _at(7, 4), _at(13, 8)]),
        [12, 3],
      );
    });

    test('the newest weekly bucket is a full week, not a remainder', () {
      // The two-day remainder of 30 days used to be the newest bucket.
      final UsageRange range = usageRange(_today, 30, 7);
      expect(range.bucketCount, 5);
      expect(daysBetween(range.bucketStart(4), range.end), 7);

      final List<double> totals = bucketTotals(range, [
        for (int day = 0; day < 30; day++) _at(day, 1),
      ]);
      expect(totals, [2, 7, 7, 7, 7]);
    });

    test('sparse: a single day in a long range', () {
      final List<double> totals = bucketTotals(usageRange(_today, 30, 1), [
        _at(12, 1),
      ]);
      expect(totals, hasLength(30));
      expect(totals[17], 1);
      expect(totals.where((double t) => t != 0), hasLength(1));
    });

    test('empty: every bucket is zero', () {
      expect(bucketTotals(usageRange(_today, 30, 7), const []), [
        0,
        0,
        0,
        0,
        0,
      ]);
    });

    test('drops activities before and after the range', () {
      // The days just before the range start would round into bucket 0.
      final UsageRange range = usageRange(_today, 14, 7);
      expect(
        bucketTotals(range, [_at(14, 1), _at(15, 1), _at(20, 1), _at(-1, 1)]),
        [0, 0],
      );
      expect(
        bucketTotals(usageRange(_today, 30, 7), [_at(30, 1), _at(34, 1)]),
        [0, 0, 0, 0, 0],
      );
    });
  });

  group('smoothing window', () {
    test('is at most seven buckets, and at most the bucket count', () {
      expect(smoothingLimit(30), 7);
      expect(smoothingLimit(4), 4);
      expect(smoothingLimit(1), 1);
      expect(smoothingLimit(0), 1);
    });

    test('a window picked for daily shrinks to fit weekly', () {
      final int weeks = usageRange(_today, 30, 7).bucketCount;
      expect(effectiveWindow(7, weeks), 5);
      expect(effectiveWindow(3, weeks), 3);
      expect(effectiveWindow(0, weeks), 1);
    });
  });

  group('movingAverage', () {
    test('a window of one is the totals', () {
      expect(movingAverage([1, 2, 3], 1), [1, 2, 3]);
    });

    test('averages the trailing window, fewer at the start', () {
      expect(movingAverage([3, 0, 0, 6, 3], 3), [3, 1.5, 1, 2, 3]);
    });

    test('a window wider than the data averages everything so far', () {
      expect(movingAverage([2, 4, 0], 7), [2, 3, 2]);
      expect(movingAverage([2, 4, 0], 7), movingAverage([2, 4, 0], 3));
    });

    test('sparse data averages to no less than zero', () {
      final List<double> totals = List<double>.filled(30, 0)..[17] = 1;
      final List<double> averages = movingAverage(totals, 7);
      expect(averages.every((double a) => a >= 0), isTrue);
      expect(averages.sublist(17, 24), everyElement(closeTo(1 / 7, 1e-12)));
      expect(averages[24], 0);
    });

    test('empty data stays empty', () {
      expect(movingAverage([], 7), isEmpty);
    });
  });
}
