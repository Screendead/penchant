import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/health_source.dart'
    show HealthMetric, HealthSample;
import 'package:tracker/insights/hours_after.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/what_follows.dart';

import 'hours_after_synthetic.dart';

List<HabitInsight> judge(Synthetic s) => hoursAfter(
  plan: planHoursAfter(s.uses, s.through),
  uses: s.uses,
  samples: s.samples,
);

HabitInsight at(
  List<HabitInsight> insights,
  HourWindow window, {
  String habit = 'Coffee',
  String metric = 'heartRate',
}) => insights.singleWhere(
  (i) => i.habitId == habit && i.metricId == metric && i.window == window,
);

int findings(List<HabitInsight> insights, {String metric = 'heartRate'}) =>
    insights
        .whereType<HabitFinding>()
        .where((f) => f.metricId == metric)
        .length;

void main() {
  group('planHoursAfter', () {
    test('reads one span a day at most, and caps the events', () {
      final Synthetic s = synthetic(1, days: 400);
      final HoursAfterPlan plan = planHoursAfter(s.uses, s.through);
      final List<HoursAfterPoint> events = <HoursAfterPoint>[
        for (final HoursAfterPoint p in plan.points)
          if (!p.control) p,
      ];
      expect(events, hasLength(hoursAfterMaxEvents));
      final Set<DateTime> days = <DateTime>{
        for (final HoursAfterPoint p in plan.points) startOfDay(p.at),
      };
      expect(plan.reads.length, lessThanOrEqualTo(days.length));
      for (int i = 1; i < plan.reads.length; i++) {
        expect(plan.reads[i].start.isAfter(plan.reads[i - 1].end), isTrue);
      }
      // A control lies on another day, at the same clock time, clear of it.
      for (final HoursAfterPoint p in plan.points.where((p) => p.control)) {
        for (final HabitUse u in s.uses) {
          expect(u.at.difference(p.at).inMinutes.abs(), greaterThan(239));
        }
      }
    });

    test('a habit at the same time every day has no controls', () {
      final List<HabitUse> uses = <HabitUse>[
        for (int i = 0; i < 60; i++)
          HabitUse(
            habitId: 'Coffee',
            at: addDays(syntheticStart, i).add(const Duration(hours: 7)),
            amount: 1,
          ),
      ];
      final HoursAfterPlan plan = planHoursAfter(
        uses,
        addDays(syntheticStart, 60),
      );
      expect(plan.points.where((p) => p.control), isEmpty);
    });
  });

  test('a rise one to two hours after Coffee is found there alone', () {
    final List<HabitInsight> insights = judge(
      synthetic(
        3,
        effect: (h, m) => h == 'Coffee' && m >= 60 && m < 120 ? 6 : 0,
      ),
    );
    final HabitInsight hit = at(insights, (start: 60, end: 120));
    expect(hit, isA<HabitFinding>());
    expect((hit as HabitFinding).effect, closeTo(6, 2));
    expect(at(insights, (start: 0, end: 30)), isA<HabitRefusal>());
    expect(
      findingSentence(hit, 'Coffee', 'en'),
      matches(
        RegExp(
          r'^One to two hours after Coffee, your heart rate is \d bpm higher '
          r'than before it\.$',
        ),
      ),
    );
    expect(
      findingBasis(hit, 'Coffee'),
      startsWith(
        'From ${hit.exposedDays} days with Coffee, against the same '
        'hours on ',
      ),
    );
  });

  // 20 seeds x 4 windows; at a 5% false rate per check, 10 or more is
  // under 1 in 100 (binomial).
  int falseFindings(Synthetic Function(int seed) make) => <int>[
    for (int seed = 0; seed < 20; seed++) findings(judge(make(seed))),
  ].reduce((a, b) => a + b);

  test('a morning rise with no habit effect is not a finding', () {
    expect(
      falseFindings((seed) => synthetic(seed, morningRise: 20)),
      lessThan(10),
    );
  });

  test('a walk after Coffee is not a finding', () {
    expect(
      falseFindings((seed) => synthetic(seed, walkAfterCoffee: 0.7)),
      lessThan(10),
    );
  });

  test('sparse HRV is refused for too few readings', () {
    final List<HabitInsight> insights = judge(synthetic(2));
    final HabitInsight hrv = at(insights, (
      start: 0,
      end: 30,
    ), metric: 'heartRateVariabilitySDNN');
    expect(hrv, isA<HabitRefusal>());
    expect(
      refusalReason(hrv as HabitRefusal, (id) => id),
      'Hours after it: too few uses with heart rate variability readings '
      'around them yet: 0 days of 10',
    );
  });

  test('a habit at the same time every day is refused in plain words', () {
    final Synthetic s = synthetic(
      4,
      habits: const <String, HabitPattern>{
        'Coffee': (chance: 1, from: 7 * 60, to: 7 * 60 + 20),
      },
    );
    final HabitRefusal r = at(judge(s), (start: 0, end: 30)) as HabitRefusal;
    expect(
      refusalReason(r, (id) => id),
      'Hours after it: used at about the same time each day, so there are '
      'too few other days at that time to compare',
    );
  });

  test('no heart rate readings at all adds nothing', () {
    final Synthetic s = synthetic(5);
    expect(
      hoursAfter(
        plan: planHoursAfter(s.uses, s.through),
        uses: s.uses,
        samples: const <String, List<HealthSample>>{},
      ),
      isEmpty,
    );
  });

  test('the report puts hours-after results in the same family', () {
    final Synthetic s = synthetic(
      3,
      effect: (h, m) => h == 'Coffee' && m >= 60 && m < 120 ? 6 : 0,
    );
    final InsightsReport report = computeInsights(
      InsightsInput(
        uses: s.uses,
        outcomes: const <DailyOutcome>[],
        from: syntheticStart,
        through: s.through,
        samples: s.samples,
      ),
    );
    expect(
      report.findings.map((f) => (f.kind, f.window)),
      contains((InsightKind.hoursAfter, (start: 60, end: 120))),
    );
  });

  test('sleeping heart rate is a night metric with words', () {
    final MetricCopy copy = metricCopy(HealthMetric.sleepingHeartRate.id)!;
    expect(copy.name, 'heart rate while asleep');
    expect(copy.night, isTrue);
    expect(copy.unit, 'bpm');
  });
}
