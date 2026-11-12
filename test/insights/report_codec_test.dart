import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/insights/after_event.dart';
import 'package:tracker/insights/before_use.dart';
import 'package:tracker/insights/habit_follows.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/measure_shifts.dart';
import 'package:tracker/insights/payoff.dart';
import 'package:tracker/insights/recovery.dart';
import 'package:tracker/insights/replacement.dart';
import 'package:tracker/insights/report_codec.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/step_changes.dart';
import 'package:tracker/insights/trigger_amounts.dart';
import 'package:tracker/insights/what_follows.dart';
import 'package:tracker/providers/insights_provider.dart';

import '../insights_harness.dart';

final DateTime _day = DateTime(2026, 10, 1);

HabitFall _fall(String id) => HabitFall(
  habitId: id,
  day: _day,
  from: DateTime(2026, 8, 1),
  before: 3.5,
  since: 0,
  sinceDays: 40,
);

const HabitRefusal _bedtimeRefusal = HabitRefusal(
  habitId: 'tea',
  metricId: 'sleepAsleep',
  lagDays: 1,
  usableDays: 30,
  exposedDays: 30,
  raw: null,
  kind: InsightKind.dose,
  reason: RefusalReason.followsBedtime,
);

/// Every section, with each optional field set somewhere and left out
/// somewhere, and the non-finite values JSON cannot hold.
InsightsReport everySection() => InsightsReport(
  hoursAfterChecks: 12,
  floors: const <String, double>{'sleepDeep': 10, 'stepCount': 512.5},
  findings: <HabitFinding>[
    const HabitFinding(
      habitId: 'coffee',
      metricId: 'sleepDeep',
      lagDays: 1,
      usableDays: 90,
      exposedDays: 44,
      raw: Comparison(
        exposedMean: 52.25,
        unexposedMean: 70.5,
        exposedDays: 44,
        unexposedDays: 46,
        interval: Interval(-25, -11.5),
      ),
      effect: -18.25,
      interval: Interval(-24, -12),
      standardized: -1.4,
      pValue: 1e-9,
    ),
    const HabitFinding(
      habitId: 'coffee',
      metricId: 'sleepAsleep',
      lagDays: 1,
      usableDays: 44,
      exposedDays: 44,
      raw: null,
      kind: InsightKind.lastUse,
      step: 60,
      effect: -11,
      interval: Interval(-17, -5),
      standardized: -0.6,
      pValue: 0.001,
      spread: 95,
      sameBedtime: HabitFinding(
        habitId: 'coffee',
        metricId: 'sleepAsleep',
        lagDays: 1,
        usableDays: 40,
        exposedDays: 40,
        raw: null,
        kind: InsightKind.lastUse,
        step: 60,
        effect: -4,
        interval: Interval(-7, -1),
        standardized: -0.2,
        pValue: 0.01,
      ),
    ),
    const HabitFinding(
      habitId: 'water',
      metricId: 'heartRate',
      lagDays: 0,
      usableDays: 60,
      exposedDays: 30,
      raw: null,
      kind: InsightKind.hoursAfter,
      window: (start: 60, end: 120),
      effect: 6,
      interval: Interval(3, 9),
      standardized: 0.8,
      pValue: 0.0001,
      sameBedtime: _bedtimeRefusal,
    ),
    const HabitFinding(
      habitId: 'tea',
      metricId: 'restingHeartRate',
      lagDays: 1,
      usableDays: 50,
      exposedDays: 20,
      raw: null,
      kind: InsightKind.doseLine,
      cut: 2.5,
      effect: 2,
      interval: Interval(1, 3),
      standardized: 0.5,
      pValue: 0.002,
      heldFixed: <String>{'cyclePhase'},
    ),
  ],
  refused: <HabitRefusal>[
    const HabitRefusal(
      habitId: 'tea',
      metricId: 'sleepDeep',
      lagDays: 1,
      usableDays: 90,
      exposedDays: 45,
      raw: Comparison(
        exposedMean: 70,
        unexposedMean: 70.1,
        exposedDays: 45,
        unexposedDays: 45,
        interval: Interval(double.negativeInfinity, double.infinity),
      ),
      reason: RefusalReason.entangled,
      entangledWith: 'coffee',
      effect: -0.1,
      interval: Interval(-3, 2.8),
      pValue: 0.9,
    ),
    const HabitRefusal(
      habitId: 'water',
      metricId: 'heartRate',
      lagDays: 0,
      usableDays: 8,
      exposedDays: 3,
      raw: null,
      kind: InsightKind.hoursAfter,
      window: (start: 0, end: 30),
      reason: RefusalReason.tooFewDays,
      shortfall: HoursAfterShortfall.readings,
    ),
  ],
  follows: const <HabitFollows>[
    HabitFollows(
      leadId: 'coffee',
      followerId: 'tea',
      days: 40,
      followedDays: 22,
      uses: 51,
      share: 0.45,
      chance: 0.1,
      pValue: 0.0003,
      verdict: FollowsVerdict.found,
    ),
    HabitFollows(
      leadId: 'tea',
      followerId: 'water',
      days: 3,
      followedDays: 1,
      uses: 4,
      share: 0.25,
      chance: 0.2,
      pValue: null,
    ),
  ],
  beforeUse: const <BeforeUse>[
    BeforeUse(
      habitId: 'coffee',
      metricId: 'sleepAsleep',
      kind: BeforeUseKind.whether,
      usableDays: 90,
      exposedDays: 44,
      effect: -30,
      interval: Interval(-45, -15),
      pValue: 0.0002,
    ),
    BeforeUse(
      habitId: 'coffee',
      metricId: 'heartRate',
      kind: BeforeUseKind.hourBefore,
      usableDays: 5,
      exposedDays: 2,
      step: 60,
      spread: 30,
      refusal: RefusalReason.tooFewDays,
      shortfall: HoursAfterShortfall.noSleep,
    ),
  ],
  payoffs: <Payoff>[
    Payoff(
      fall: _fall('coffee'),
      metricId: 'restingHeartRate',
      baselineValues: 60,
      sinceValues: 40,
      capped: true,
      effect: -2.5,
      interval: const Interval(-4, -1),
      pValue: 0.004,
      autocorrelation: 0.3,
    ),
    Payoff(
      fall: _fall('tea'),
      metricId: 'sleepAsleep',
      baselineValues: 60,
      sinceValues: 40,
      capped: false,
      refusal: PayoffRefusal.otherFall,
      otherHabitId: 'coffee',
    ),
  ],
  replacements: <Replacement>[
    Replacement(
      fall: _fall('coffee'),
      riserId: 'tea',
      before: 0,
      since: 2,
      baselineDays: 60,
      sinceDays: 40,
      effect: 1.8,
      interval: const Interval(1, 2.6),
      pValue: 0.001,
      began: true,
    ),
    Replacement(
      fall: _fall('coffee'),
      riserId: 'water',
      before: 1,
      since: 1.1,
      baselineDays: 60,
      sinceDays: 40,
      refusal: ReplacementRefusal.noRise,
    ),
  ],
  shifts: <MeasureShift>[
    MeasureShift(
      metricId: 'restingHeartRate',
      shift: LevelShift(
        at: _day,
        before: 58,
        after: 62.5,
        daysBefore: 80,
        daysAfter: 40,
        pValue: 0.0001,
      ),
      habits: const <HabitChange>[
        HabitChange(habitId: 'coffee', before: 2, after: 4),
      ],
      found: true,
    ),
  ],
  afterEvent: const <AfterEvent>[
    AfterEvent(
      habitId: 'coffee',
      eventDays: 30,
      controlDays: 28,
      eventRate: 0.4,
      controlRate: 0.15,
      effect: 0.25,
      interval: Interval(0.1, 0.4),
      pValue: 0.002,
    ),
    AfterEvent(
      habitId: 'tea',
      eventDays: 4,
      controlDays: 4,
      eventRate: 0,
      controlRate: 0,
      refusal: RefusalReason.tooFewDays,
    ),
  ],
  recovery: const <Recovery>[
    Recovery(
      habitId: 'coffee',
      metricId: 'heartRateVariabilitySDNN',
      usableDays: 90,
      heavyDays: 20,
      cut: 4,
      floor: 3.2,
      nights: <RecoveryNight>[
        RecoveryNight(
          effect: -6,
          interval: Interval(-9, -3),
          pValue: 0.001,
          off: true,
          back: false,
        ),
        RecoveryNight(
          effect: double.nan,
          interval: Interval(-1, 1),
          pValue: 0.8,
          off: false,
          back: true,
        ),
      ],
    ),
    Recovery(
      habitId: 'tea',
      metricId: 'sleepAsleep',
      usableDays: 10,
      heavyDays: 2,
      refusal: RefusalReason.tooFewDays,
    ),
  ],
  triggers: const <HabitTriggers>[
    HabitTriggers(
      habitId: 'coffee',
      entries: 120,
      tagged: 64,
      triggers: <TriggerAmount>[
        TriggerAmount(
          trigger: 'social/friends',
          entries: 30,
          withDays: 18,
          withoutDays: 25,
          withMean: 2.9,
          withoutMean: 2,
          pValue: 0.001,
          verdict: TriggerVerdict.found,
        ),
        TriggerAmount(
          trigger: 'Bored at the bus stop',
          entries: 2,
          withDays: 2,
          withoutDays: 30,
          withMean: 1,
          withoutMean: 2.1,
          pValue: null,
        ),
      ],
    ),
  ],
);

InsightsView _view(InsightsReport report, {bool hoursPending = false}) => (
  health: HealthReady(<DailyOutcome>[
    DailyOutcome(_day, 'sleepDeep', 71.5),
    DailyOutcome(DateTime(2026, 10, 2), 'stepCount', 9000),
  ]),
  result: InsightsComputed(
    report,
    firstDays: <String, DateTime>{'coffee': DateTime(2026, 6, 1)},
  ),
  hoursPending: hoursPending,
  updating: false,
);

Map<String, Object?> _json(List<int> bytes) =>
    jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;

void main() {
  test('every section round trips', () {
    final List<int> bytes = encodeInsightsView(
      _view(everySection(), hoursPending: true),
    )!;
    final InsightsView? back = decodeInsightsView(bytes);
    expect(back, isNotNull);
    expect(back!.updating, isFalse);
    expect(back.hoursPending, isTrue);
    expect(encodeInsightsView(back), bytes);
    final InsightsReport report = (back.result! as InsightsComputed).report;
    expect(report.findings[2].window, (start: 60, end: 120));
    expect(report.findings[2].sameBedtime, isA<HabitRefusal>());
    expect(report.findings[3].heldFixed, <String>{'cyclePhase'});
    expect(report.findings[0].heldFixed, isEmpty);
    expect(report.refused.first.raw!.interval.high, double.infinity);
    expect(report.recovery.first.nights[1].effect, isNaN);
    expect(report.payoffs.first.fall.day, _day);
    expect(report.triggers.single.triggers[1].trigger, 'Bored at the bus stop');
    expect(report.triggers.single.triggers.first.verdict, TriggerVerdict.found);
  });

  test('a computed report round trips', () {
    final journal = insightsJournal();
    final InsightsReport report = computeInsights(
      InsightsInput.from(
        activities: journal.activities,
        health: journal.health,
        today: insightsToday,
      ),
    );
    expect(report.findings, isNotEmpty);
    final List<int> bytes = encodeInsightsView(_view(report))!;
    expect(encodeInsightsView(decodeInsightsView(bytes)!), bytes);
  });

  test('a view without a computed report is not kept', () {
    expect(
      encodeInsightsView((
        health: const HealthNotConnected(),
        result: null,
        hoursPending: false,
        updating: false,
      )),
      isNull,
    );
    expect(
      encodeInsightsView((
        health: const HealthReady(<DailyOutcome>[]),
        result: const InsightsFailed(),
        hoursPending: false,
        updating: false,
      )),
      isNull,
    );
  });

  test('garbage, another version or a missing field reads as absent', () {
    expect(decodeInsightsView(<int>[0xff, 0x00, 0x13]), isNull);
    expect(decodeInsightsView(utf8.encode('[1, 2]')), isNull);
    final Map<String, Object?> good = _json(
      encodeInsightsView(_view(everySection()))!,
    );
    List<int> bytes(Map<String, Object?> m) => utf8.encode(jsonEncode(m));
    expect(decodeInsightsView(bytes(good)), isNotNull);
    expect(
      decodeInsightsView(bytes(<String, Object?>{...good, 'version': 0})),
      isNull,
    );
    expect(
      decodeInsightsView(
        bytes(<String, Object?>{...good, 'version': insightsViewFormat + 1}),
      ),
      isNull,
    );
    expect(decodeInsightsView(bytes({...good}..remove('firstDays'))), isNull);
    final Map<String, Object?> report = <String, Object?>{
      ...good['report']! as Map<String, Object?>,
    };
    final List<Object?> findings = <Object?>[...report['findings']! as List];
    findings[0] = <String, Object?>{...findings[0]! as Map<String, Object?>}
      ..remove('standardized');
    expect(
      decodeInsightsView(
        bytes(<String, Object?>{
          ...good,
          'report': <String, Object?>{...report, 'findings': findings},
        }),
      ),
      isNull,
    );
    findings[0] = <String, Object?>{
      ...findings[0]! as Map<String, Object?>,
      'standardized': 1,
      'kind': 'someKindNotYetMade',
    };
    expect(
      decodeInsightsView(
        bytes(<String, Object?>{
          ...good,
          'report': <String, Object?>{...report, 'findings': findings},
        }),
      ),
      isNull,
    );
  });
}
