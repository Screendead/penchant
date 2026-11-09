import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/health_source.dart'
    show HealthMetric, HealthSample, HealthSampleMetric;
import 'package:tracker/insights/hours_after.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/what_follows.dart';

import 'hours_after_synthetic.dart';

HoursAfterPlan plan(Synthetic s) => planHoursAfter(
  s.uses,
  s.through,
  bed: s.samples[HealthSampleMetric.bed.id]!,
);

List<HabitInsight> judge(Synthetic s) =>
    hoursAfter(plan: plan(s), uses: s.uses, samples: s.samples);

String reason(HabitInsight i) => refusalReason(i as HabitRefusal, (id) => id);

// Coffee 15 to 60 minutes after waking on 85% of days.
int? afterWaking(int wake, bool weekend, List<double> w, Random r) =>
    r.nextDouble() < 0.85 ? wake + 15 + r.nextInt(45) : null;

// Coffee at a random time from 09:00 to 15:00 on 70% of days.
int? midday(int wake, bool weekend, List<double> w, Random r) =>
    r.nextDouble() < 0.7 ? 9 * 60 + 5 * r.nextInt(72) : null;

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
      final HoursAfterPlan planned = plan(s);
      final List<HoursAfterPoint> events = <HoursAfterPoint>[
        for (final HoursAfterPoint p in planned.points)
          if (!p.control) p,
      ];
      expect(events, hasLength(hoursAfterMaxEvents));
      final Set<DateTime> days = <DateTime>{
        for (final HoursAfterPoint p in planned.points) startOfDay(p.at),
      };
      expect(planned.reads.length, lessThanOrEqualTo(days.length));
      for (int i = 1; i < planned.reads.length; i++) {
        expect(
          planned.reads[i].start.isAfter(planned.reads[i - 1].end),
          isTrue,
        );
      }
      // A control lies on another day clear of it.
      for (final HoursAfterPoint p in planned.points.where((p) => p.control)) {
        for (final HabitUse u in s.uses) {
          expect(u.at.difference(p.at).inMinutes.abs(), greaterThan(239));
        }
      }
    });

    test('a habit at the same time every day has no controls', () {
      final Synthetic s = synthetic(1, days: 60);
      final List<HabitUse> uses = <HabitUse>[
        for (int i = 0; i < 60; i++)
          HabitUse(
            habitId: 'Coffee',
            at: addDays(syntheticStart, i).add(const Duration(hours: 7)),
            amount: 1,
          ),
      ];
      final HoursAfterPlan planned = planHoursAfter(
        uses,
        s.through,
        bed: s.samples[HealthSampleMetric.bed.id]!,
      );
      expect(planned.points.where((p) => !p.control), isNotEmpty);
      expect(planned.points.where((p) => p.control), isEmpty);
    });

    test('a control sits as long after waking as its use', () {
      final Synthetic s = wakingSynthetic(
        6,
        habits: const <String, UsePolicy>{'Coffee': midday},
      );
      final List<HealthSample> bed = s.samples[HealthSampleMetric.bed.id]!;
      DateTime wakeBefore(DateTime t) => bed
          .where((b) => b.end.isBefore(t))
          .map((b) => b.end)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      final List<HoursAfterPoint> points = plan(s).points;
      int controls = 0;
      for (int i = 0; i < points.length; i++) {
        if (!points[i].control) continue;
        controls++;
        final HoursAfterPoint event = points[i - 1];
        expect(event.control, isFalse);
        expect(
          points[i].at.difference(wakeBefore(points[i].at)),
          event.at.difference(wakeBefore(event.at)),
        );
      }
      expect(controls, greaterThan(40));
    });

    test('a use within the hour after waking, or near bed, is left out', () {
      final Synthetic s = wakingSynthetic(
        7,
        habits: const <String, UsePolicy>{'Coffee': afterWaking},
      );
      expect(plan(s).points, isEmpty);
      expect(
        reason(at(judge(s), (start: 0, end: 30))),
        'Hours after it: most uses come within an hour of waking or within '
        '4 hours of bed, when heart rate moves anyway',
      );
    });

    test('with no sleep recorded nothing is planned, and it says why', () {
      final Synthetic s = wakingSynthetic(
        8,
        missingNight: 1,
        habits: const <String, UsePolicy>{'Coffee': midday},
      );
      expect(plan(s).points, isEmpty);
      expect(
        reason(at(judge(s), (start: 0, end: 30))),
        'Hours after it: needs your sleep in Health, to time each use from '
        'waking: most uses have no night recorded before them',
      );
    });

    test('an event whose windows run past the cut-off waits', () {
      final Synthetic s = synthetic(1, days: 30);
      final DateTime late = addDays(
        s.through,
        -1,
      ).add(const Duration(hours: 21));
      final HoursAfterPlan planned = planHoursAfter(
        <HabitUse>[...s.uses, HabitUse(habitId: 'Coffee', at: late, amount: 1)],
        s.through,
        bed: s.samples[HealthSampleMetric.bed.id]!,
      );
      expect(planned.points.map((p) => p.at), isNot(contains(late)));
    });
  });

  test('a second use cuts the windows after the first short', () {
    final Synthetic s = synthetic(9);
    final List<HabitUse> again = <HabitUse>[
      ...s.uses,
      for (final HabitUse u in s.uses)
        if (u.habitId == 'Coffee')
          HabitUse(
            habitId: 'Coffee',
            at: u.at.add(const Duration(minutes: 90)),
            amount: 1,
          ),
    ]..sort((a, b) => a.at.compareTo(b.at));
    final List<HabitInsight> insights = hoursAfter(
      plan: planHoursAfter(
        again,
        s.through,
        bed: s.samples[HealthSampleMetric.bed.id]!,
      ),
      uses: again,
      samples: s.samples,
    );
    expect(at(insights, (start: 0, end: 30)).exposedDays, greaterThan(20));
    expect(
      reason(at(insights, (start: 120, end: 240))),
      'Hours after it: used again within a few hours most times, so the '
      'hours after one use run into the next',
    );
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
          r'^One to two hours after Coffee, your heart rate, set against the '
          r'hour before, averages \d bpm higher than at the same time after '
          r'waking without it\.$',
        ),
      ),
    );
    expect(
      findingBasis(hit, 'Coffee'),
      'From ${hit.exposedDays} days with Coffee, against '
      '${hit.usableDays - hit.exposedDays} days at the same time after '
      'waking with none of it within 4 hours',
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

  test('Coffee soon after waking, a lie-in at weekends, is not a finding', () {
    expect(
      falseFindings(
        (seed) => wakingSynthetic(
          seed,
          habits: const <String, UsePolicy>{'Coffee': _twoHoursAfterWaking},
        ),
      ),
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
      reason(hrv),
      'Hours after it: Health holds too few heart rate variability readings '
      'around its uses, 3 before and after each',
    );
  });

  test('a habit at the same time every day is refused in plain words', () {
    final Synthetic s = synthetic(
      4,
      habits: const <String, HabitPattern>{
        'Coffee': (chance: 1, from: 7 * 60, to: 7 * 60 + 20),
      },
    );
    expect(
      reason(at(judge(s), (start: 0, end: 30))),
      'Hours after it: too few nearby days clear of it at the same time '
      'after waking to compare with',
    );
  });

  test('another habit through the day is named as the cause', () {
    final Synthetic s = wakingSynthetic(
      10,
      habits: const <String, UsePolicy>{'Coffee': midday},
      frequent: const <String, int>{'Cigarettes': 8},
    );
    expect(
      reason(at(judge(s), (start: 60, end: 120))),
      'Hours after it: another habit is logged within 4 hours of most of its '
      'uses',
    );
  });

  test('no heart rate readings at all adds nothing', () {
    final Synthetic s = synthetic(5);
    expect(
      hoursAfter(
        plan: plan(s),
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

// Coffee two to three hours after waking on 85% of days, so its hour before
// is past waking.
int? _twoHoursAfterWaking(int wake, bool weekend, List<double> w, Random r) =>
    r.nextDouble() < 0.85 ? wake + 120 + r.nextInt(60) : null;
