import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/trend_breakdowns.dart';
import 'package:tracker/data/usage_series.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/insights/health_source.dart';

import 'fakes.dart';

final DateTime _today = DateTime(2026, 3, 31);

ViceActivity _tagged(int daysAgo, List<String> triggers) => fakeActivity(
  'coffee',
  1,
  addDays(_today, -daysAgo).add(const Duration(hours: 9)),
  triggers: triggers,
);

void main() {
  group('bucketOf', () {
    test('finds the bucket of a day, counting weeks back from today', () {
      final UsageRange weeks = usageRange(_today, 14, 7);
      expect(weeks.bucketOf(_today.add(const Duration(hours: 23))), 1);
      expect(weeks.bucketOf(addDays(_today, -6)), 1);
      expect(weeks.bucketOf(addDays(_today, -7)), 0);
      expect(weeks.bucketOf(addDays(_today, -14)), isNull);
      expect(weeks.bucketOf(addDays(_today, 1)), isNull);
    });
  });

  group('bucketHealth', () {
    test('averages the days with a value, and leaves a bucket of none '
        'empty rather than zero', () {
      final UsageRange weeks = usageRange(_today, 14, 7);
      final List<double?> values = bucketHealth(weeks, <DailyOutcome>[
        DailyOutcome(_today, 'restingHeartRate', 60),
        DailyOutcome(addDays(_today, -1), 'restingHeartRate', 64),
        DailyOutcome(addDays(_today, -1), 'stepCount', 9000),
        DailyOutcome(addDays(_today, -30), 'restingHeartRate', 90),
      ], 'restingHeartRate');
      expect(values, <double?>[null, 62]);
    });
  });

  group('triggerShares', () {
    test('splits each tagged entry across its areas, so a bucket sums to '
        'one, and counts free text as own words', () {
      final UsageRange days = usageRange(_today, 2, 1);
      final TriggerShares s = triggerShares(days, <ViceActivity>[
        _tagged(0, <String>['work/meeting', 'feeling/stressed']),
        _tagged(0, <String>['work/deadline', 'work/meeting']),
        _tagged(0, <String>['rainy walk']),
        _tagged(0, const <String>[]),
      ]);
      expect(s.areas, <String>['work', ownWordsArea, 'feeling']);
      expect(s.tagged, <int>[0, 3]);
      expect(s.shares[0], <double>[0, 0, 0]);
      expect(s.shares[1][0], closeTo(1.5 / 3, 1e-9));
      expect(s.shares[1][1], closeTo(1 / 3, 1e-9));
      expect(s.shares[1][2], closeTo(0.5 / 3, 1e-9));
      expect(triggerAreaLabel('work'), 'Work');
      expect(triggerAreaLabel(ownWordsArea), 'Own words');
    });

    test('merges the least tagged areas past the limit into Other', () {
      final UsageRange days = usageRange(_today, 1, 1);
      final TriggerShares s = triggerShares(days, <ViceActivity>[
        _tagged(0, <String>['work']),
        _tagged(0, <String>['work']),
        _tagged(0, <String>['feeling']),
        _tagged(0, <String>['social']),
        _tagged(0, <String>['place']),
      ], maxAreas: 3);
      expect(s.areas, <String>['work', 'feeling', otherArea]);
      expect(s.shares.single, <double>[0.4, 0.2, 0.4]);
      expect(s.overall, <double>[0.4, 0.2, 0.4]);
    });
  });
}
