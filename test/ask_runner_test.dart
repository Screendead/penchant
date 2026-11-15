import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:tracker/ask/ask_query.dart';
import 'package:tracker/ask/ask_runner.dart';
import 'package:tracker/ask/describe_query.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/trigger_tree.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/formats.dart';

import 'dst.dart';
import 'fakes.dart';

final DateTime today = DateTime(2026, 11, 15); // a Sunday

Vice habit(String id, Unit unit, {bool archived = false, double? cost}) => Vice(
  id: id,
  name: id,
  unit: unit,
  ownerID: ownerID,
  createdAt: Timestamp.fromMillisecondsSinceEpoch(id.hashCode.abs() % 1000),
  archived: archived,
  costPerUnit: cost,
  currency: cost == null ? null : 'GBP',
);

final Vice wine = habit('Wine', Unit.drink, cost: 8);
final Vice cigs = habit('Cigarettes', Unit.item);
final Vice vape = habit('Vape', Unit.puff, archived: true);
final List<Vice> habits = <Vice>[wine, cigs, vape];

AskQuery q({
  int? habit = 0,
  AskMeasure measure = AskMeasure.amount,
  AskPeriod period = const AskPeriod(AskPeriodType.lastDays, count: 7),
  AskFilter filter = const AskFilter(),
  AskShape shape = AskShape.total,
  AskBucket? bucket,
  AskCondition? condition,
  double? threshold,
  AskLongest? longest,
  AskSide? versus,
}) => AskQuery(
  side: AskSide(habit: habit, period: period, filter: filter),
  measure: measure,
  shape: shape,
  bucket: bucket,
  condition: condition,
  threshold: threshold,
  longest: longest,
  versus: versus,
);

AskAnswer answer(AskQuery query, List<ViceActivity> entries, {DateTime? on}) =>
    runAskQuery(query, habits: habits, activities: entries, today: on ?? today);

String monthDay(DateTime d) => DateFormat.MMMMd(formatLocale).format(d);
String fullDate(DateTime d) => DateFormat.yMMMMd(formatLocale).format(d);

// Wine across early November, one entry on a Friday evening at a meeting.
final List<ViceActivity> november = <ViceActivity>[
  fakeActivity('Wine', 4, DateTime(2026, 11, 1, 19)),
  fakeActivity('Wine', 2, DateTime(2026, 11, 9, 18)),
  fakeActivity(
    'Wine',
    3,
    DateTime(2026, 11, 13, 21),
    triggers: <String>['work/meeting'],
  ),
  fakeActivity('Wine', 1, DateTime(2026, 11, 15, 12)),
  fakeActivity('Cigarettes', 1, DateTime(2026, 11, 1, 9)),
  fakeActivity('Cigarettes', 1, DateTime(2026, 11, 2, 9)),
  fakeActivity('Cigarettes', 1, DateTime(2026, 11, 8, 9)),
  fakeActivity('Cigarettes', 1, DateTime(2026, 11, 12, 9)),
  fakeActivity('Vape', 30, DateTime(2025, 6, 1, 9)),
  fakeActivity('Vape', 12, DateTime(2025, 6, 3, 9)),
];

void main() {
  group('total', () {
    test('adds up the measure over the period', () {
      final AskAnswer a = answer(q(), november);
      expect(a.headline, '6 drinks');
      expect(a.bars, hasLength(7));
      expect(a.bars!.last.label, 'today');
      expect(a.bars!.map((AskBar b) => b.value), <double>[2, 0, 0, 0, 3, 0, 1]);
    });

    test('filters by weekday, hour and tag', () {
      expect(
        answer(q(filter: const AskFilter(weekdays: <int>{5})), november).headline,
        '3 drinks',
      );
      expect(
        answer(q(filter: const AskFilter(fromHour: 20, toHour: 24)), november).headline,
        '3 drinks',
      );
      expect(answer(q(filter: const AskFilter(tag: 'work')), november).headline, '3 drinks');
    });

    test('counts entries, days with and days without', () {
      expect(answer(q(habit: null, measure: AskMeasure.entries), november).headline, '4 entries');
      expect(answer(q(measure: AskMeasure.daysWith), november).headline, '3 days');
      expect(answer(q(measure: AskMeasure.daysWithout), november).headline, '4 days');
    });

    test('days without start at the first entry', () {
      // Wine began on 1 November: 15 days, 4 of them with wine.
      expect(
        answer(
          q(measure: AskMeasure.daysWithout, period: const AskPeriod(AskPeriodType.allTime)),
          november,
        ).headline,
        '11 days',
      );
    });

    test('spend is the amount times the price, and needs one', () {
      expect(answer(q(measure: AskMeasure.spend), november).headline, formatMoney(48, 'GBP'));
      expect(
        answer(q(habit: 1, measure: AskMeasure.spend), november).headline,
        'Cigarettes has no price',
      );
    });

    test('an archived habit is counted like any other', () {
      expect(
        answer(q(habit: 2, period: const AskPeriod(AskPeriodType.allTime)), november).headline,
        '42 puffs',
      );
    });

    test('a habit with no entries says so', () {
      expect(
        answer(q(period: const AskPeriod(AskPeriodType.allTime)), const <ViceActivity>[])
            .headline,
        'No Wine entries yet',
      );
    });

    test('calendar weeks and months', () {
      // This week is Monday 9 to Sunday 15; last week 2 to 8.
      expect(answer(q(period: const AskPeriod(AskPeriodType.thisWeek)), november).headline, '6 drinks');
      expect(answer(q(period: const AskPeriod(AskPeriodType.lastWeek)), november).headline, '0 drinks');
      expect(answer(q(period: const AskPeriod(AskPeriodType.thisMonth)), november).headline, '10 drinks');
      expect(answer(q(period: const AskPeriod(AskPeriodType.lastMonth)), november).headline, '0 drinks');
    });
  });

  test('series in weeks counted back from today', () {
    final AskAnswer a = answer(
      q(
        shape: AskShape.series,
        bucket: AskBucket.week,
        period: const AskPeriod(AskPeriodType.lastWeeks, count: 4),
      ),
      november,
    );
    expect(a.bars!.map((AskBar b) => b.value), <double>[0, 4, 0, 6]);
    expect(a.bars!.map((AskBar b) => b.marked), <bool>[false, false, false, true]);
    expect(a.bars!.last.label, 'this week');
    expect(a.headline, '10 drinks');
    expect(a.detail, 'Most: the last 7 days, 6 drinks.');
  });

  test('series by calendar month, the last one cut at today', () {
    final AskAnswer a = answer(
      q(
        shape: AskShape.series,
        bucket: AskBucket.month,
        period: AskPeriod(AskPeriodType.between, from: DateTime(2026, 9), to: today),
      ),
      november,
    );
    expect(a.bars!.map((AskBar b) => b.value), <double>[0, 0, 10]);
    expect(a.bars!.last.label, 'this month');
  });

  group('last time', () {
    // Wine every third day from 1 October, none from 12 to 18 October.
    final List<ViceActivity> weekly = <ViceActivity>[
      for (int d = 1; d <= 45; d += 3)
        if (d < 12 || d > 18) fakeActivity('Wine', 2, DateTime(2026, 10, d, 20)),
    ];

    test('the last week with none', () {
      final AskAnswer a = answer(
        q(
          shape: AskShape.lastTime,
          bucket: AskBucket.week,
          condition: AskCondition.none,
          period: const AskPeriod(AskPeriodType.allTime),
        ),
        weekly,
      );
      expect(a.headline, 'The week of ${monthDay(DateTime(2026, 10, 12))}');
      expect(a.detail, '4 weeks with Wine since then.');
      // Six whole weeks since the first entry, the found one second.
      expect(a.bars, hasLength(6));
      expect(a.bars!.indexWhere((AskBar b) => b.marked), 1);
      expect(a.bars![1].value, 0);
    });

    test('the last day with any, above or below a threshold', () {
      final AskAnswer smoked = answer(
        q(habit: 1, shape: AskShape.lastTime, bucket: AskBucket.day, condition: AskCondition.any),
        november,
      );
      expect(smoked.headline, monthDay(DateTime(2026, 11, 12)));
      expect(smoked.detail, '3 days without Cigarettes since then.');
      final AskAnswer above = answer(
        q(
          shape: AskShape.lastTime,
          bucket: AskBucket.day,
          condition: AskCondition.above,
          threshold: 2,
          period: const AskPeriod(AskPeriodType.allTime),
        ),
        november,
      );
      expect(above.headline, monthDay(DateTime(2026, 11, 13)));
      final AskAnswer lowest = answer(
        q(
          shape: AskShape.lastTime,
          bucket: AskBucket.day,
          condition: AskCondition.below,
          threshold: 2,
          period: const AskPeriod(AskPeriodType.allTime),
        ),
        november,
      );
      expect(lowest.headline, 'Today');
      expect(lowest.detail, isNull);
    });

    test('never', () {
      final AskAnswer a = answer(
        q(
          habit: 1,
          shape: AskShape.lastTime,
          bucket: AskBucket.day,
          condition: AskCondition.above,
          threshold: 5,
          period: const AskPeriod(AskPeriodType.allTime),
        ),
        november,
      );
      expect(a.headline, 'Not since your first entry');
    });
  });

  group('longest', () {
    final AskQuery base = q(habit: 1, shape: AskShape.longest, period: const AskPeriod(AskPeriodType.allTime));

    test('the longest gap between entries', () {
      final AskAnswer a = answer(
        q(habit: 1, shape: AskShape.longest, longest: AskLongest.gap, period: base.side.period),
        november,
      );
      expect(a.headline, '5 days');
      expect(
        a.detail,
        'From ${fullDate(DateTime(2026, 11, 3))} to ${fullDate(DateTime(2026, 11, 7))}.',
      );
    });

    test('an open gap runs to today', () {
      final AskAnswer a = answer(
        q(habit: 2, shape: AskShape.longest, longest: AskLongest.gap, period: base.side.period),
        november,
      );
      expect(a.detail, 'Since ${fullDate(DateTime(2025, 6, 4))}, and counting.');
      expect(a.headline, '${daysBetween(DateTime(2025, 6, 3), today)} days');
    });

    test('runs of days with and without', () {
      final AskAnswer withRun = answer(
        q(
          habit: 1,
          shape: AskShape.longest,
          longest: AskLongest.runWith,
          bucket: AskBucket.day,
          period: base.side.period,
        ),
        november,
      );
      expect(withRun.headline, '2 days');
      final AskAnswer without = answer(
        q(
          habit: 1,
          shape: AskShape.longest,
          longest: AskLongest.runWithout,
          bucket: AskBucket.day,
          period: base.side.period,
        ),
        november,
      );
      expect(without.headline, '5 days');
    });
  });

  test('compare two periods as two numbers', () {
    final AskAnswer a = answer(
      q(
        shape: AskShape.compare,
        period: const AskPeriod(AskPeriodType.thisMonth),
        versus: const AskSide(habit: 0, period: AskPeriod(AskPeriodType.lastMonth)),
      ),
      november,
    );
    expect(a.headline, '10 drinks against 0 drinks');
    expect(a.bars!.map((AskBar b) => b.value), <double>[10, 0]);
    expect(a.bars!.map((AskBar b) => b.label), <String>['this month', 'last month']);
  });

  test('compare two habits', () {
    final AskAnswer a = answer(
      q(
        habit: 0,
        measure: AskMeasure.entries,
        shape: AskShape.compare,
        period: const AskPeriod(AskPeriodType.thisMonth),
        versus: const AskSide(habit: 1, period: AskPeriod(AskPeriodType.thisMonth)),
      ),
      november,
    );
    expect(a.headline, '4 entries against 4 entries');
    expect(a.bars!.map((AskBar b) => b.viceID), <String>['Wine', 'Cigarettes']);
  });

  test(
    'a DST week keeps each entry on its local day',
    () {
      final DateTime change = firstDstTransitionDay(2026)!;
      final DateTime on = addDays(change, 3);
      final List<ViceActivity> nightly = <ViceActivity>[
        for (int d = -3; d <= 3; d++)
          fakeActivity('Wine', 1, () {
            final DateTime day = addDays(change, d);
            return DateTime(day.year, day.month, day.day, 23, 30);
          }()),
      ];
      final AskAnswer days = answer(
        q(shape: AskShape.series, bucket: AskBucket.day),
        nightly,
        on: on,
      );
      expect(days.bars!.map((AskBar b) => b.value), List<double>.filled(7, 1));
      final AskAnswer week = answer(
        q(shape: AskShape.series, bucket: AskBucket.week),
        nightly,
        on: on,
      );
      expect(week.bars!.single.value, 7);
      expect(
        answer(q(measure: AskMeasure.daysWithout), nightly, on: on).headline,
        '0 days',
      );
    },
    skip: firstDstTransitionDay(2026) == null ? noDstSkipReason : false,
  );

  group('describeQuery', () {
    test('restates a last time', () {
      expect(
        describeQuery(
          q(
            shape: AskShape.lastTime,
            bucket: AskBucket.week,
            condition: AskCondition.none,
            period: const AskPeriod(AskPeriodType.allTime),
          ),
          habits,
        ),
        'The last week with no Wine entries, since your first entry, in weeks '
        'of 7 days counted back from today.',
      );
    });

    test('restates every filter', () {
      final String meeting = triggerLabels('work/meeting')!.join(' › ');
      expect(
        describeQuery(
          q(
            period: const AskPeriod(AskPeriodType.lastDays, count: 30),
            filter: const AskFilter(weekdays: <int>{5}, fromHour: 20, toHour: 24, tag: 'work/meeting'),
          ),
          habits,
        ),
        'Total drinks of Wine, in the last 30 days, on Fridays, from 20:00 to '
        'midnight, tagged $meeting.',
      );
      expect(
        describeQuery(
          q(habit: null, measure: AskMeasure.entries, filter: const AskFilter(weekdays: <int>{6, 7})),
          habits,
        ),
        'Number of entries, in the last 7 days, on weekends.',
      );
    });

    test('restates a series, a longest and a comparison', () {
      expect(
        describeQuery(
          q(shape: AskShape.series, bucket: AskBucket.month, period: const AskPeriod(AskPeriodType.lastMonths, count: 6)),
          habits,
        ),
        'Drinks of Wine per month, in the last 6 months.',
      );
      expect(
        describeQuery(
          q(habit: 1, shape: AskShape.longest, longest: AskLongest.gap, period: const AskPeriod(AskPeriodType.allTime)),
          habits,
        ),
        'The longest gap between Cigarettes entries, since your first entry.',
      );
      expect(
        describeQuery(
          q(
            shape: AskShape.compare,
            period: const AskPeriod(AskPeriodType.thisMonth),
            versus: const AskSide(habit: 0, period: AskPeriod(AskPeriodType.lastMonth)),
          ),
          habits,
        ),
        'Drinks of Wine, this month, against last month.',
      );
      expect(
        describeQuery(
          q(
            measure: AskMeasure.daysWith,
            period: AskPeriod(AskPeriodType.between, from: DateTime(2026, 10), to: DateTime(2026, 10, 31)),
          ),
          habits,
        ),
        'Number of days with Wine, from ${fullDate(DateTime(2026, 10))} to '
        '${fullDate(DateTime(2026, 10, 31))}.',
      );
    });
  });
}
