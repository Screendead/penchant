import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/health_source.dart' as hs;
import 'package:tracker/insights/hours_after.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/what_follows.dart';
import 'package:tracker/providers/insights_provider.dart';

import '../fakes.dart';
import '../insights_harness.dart';
import 'hours_after_synthetic.dart';

Future<InsightsView> run(FakeHealthSource health, Synthetic s) async {
  final List<ViceActivity> journal = <ViceActivity>[
    for (final HabitUse u in s.uses) fakeActivity(u.habitId, 1, u.at),
  ];
  final ProviderContainer container = ProviderContainer(
    overrides: [
      ...insightsOverrides(
        health: health,
        activities: AsyncData<List<ViceActivity>>(journal),
      ),
      healthConnectedProvider.overrideWith((ref) async => true),
    ],
  );
  addTearDown(container.dispose);
  final ProviderSubscription<AsyncValue<InsightsView>> sub = container.listen(
    insightsProvider,
    (_, _) {},
  );
  addTearDown(sub.close);
  InsightsView? view;
  for (
    int i = 0;
    i < 400 && (view?.result == null || view!.hoursPending);
    i++
  ) {
    await Future<void>.delayed(Duration.zero);
    view = container.read(insightsProvider).value;
  }
  return view!;
}

Map<hs.HealthSampleMetric, List<hs.HealthSample>> served(Synthetic s) =>
    <hs.HealthSampleMetric, List<hs.HealthSample>>{
      for (final hs.HealthSampleMetric m in hs.HealthSampleMetric.values)
        if (s.samples[m.id] case final List<hs.HealthSample> list) m: list,
    };

hs.HealthValues daily() => hs.HealthValues(<hs.DailyOutcome>[
  for (int i = 1; i < 60; i++)
    hs.DailyOutcome(
      addDays(insightsToday, -i),
      hs.HealthMetric.sleepDeep.id,
      70,
    ),
]);

void main() {
  test('reads samples around uses in day spans and finds the rise', () async {
    final Synthetic s = insightsHoursYear();
    final FakeHealthSource health = FakeHealthSource(
      read: daily(),
      sampleData: served(s),
    );
    final InsightsReport report =
        ((await run(health, s)).result! as InsightsComputed).report;
    expect(
      report.findings.any(
        (f) =>
            f.habitId == 'coffee' &&
            f.kind == InsightKind.hoursAfter &&
            f.window == (start: 60, end: 120),
      ),
      isTrue,
    );
    final List<hs.HealthSample> bed = s.samples[hs.HealthSampleMetric.bed.id]!;
    final HoursAfterPlan plan = insightsHoursAfterPlan(
      s.uses,
      insightsToday,
      bed: bed,
    );
    // The engine plans the same moments the provider read for.
    final InsightsInput input = InsightsInput.from(
      activities: <ViceActivity>[
        for (final HabitUse u in s.uses) fakeActivity(u.habitId, 1, u.at),
      ],
      health: const <hs.DailyOutcome>[],
      today: insightsToday,
    );
    expect(
      insightsHoursAfterPlan(
        input.uses,
        input.through,
        bed: bed,
      ).points.map((p) => p.at),
      plan.points.map((p) => p.at),
    );
    expect(report.hoursAfterChecks, greaterThan(0));
    // The time in bed in one call, then a call a span per measure.
    expect(
      health.sampleCalls,
      1 + insightsSampleMetrics.length * plan.reads.length,
    );
    expect(plan.reads.length, lessThanOrEqualTo(365));
    // ignore: avoid_print
    print(
      'hours-after read: ${plan.points.length} moments, '
      '${plan.reads.length} spans, ${health.sampleCalls} calls, '
      '${health.samplesServed} samples',
    );
  });

  test('the daily report shows while the sample read is going', () async {
    final Synthetic s = insightsHoursYear();
    final Completer<void> gate = Completer<void>();
    final FakeHealthSource health = FakeHealthSource(
      read: daily(),
      sampleData: served(s),
      sampleGate: gate.future,
    );
    final ProviderContainer container = ProviderContainer(
      overrides: [
        ...insightsOverrides(
          health: health,
          activities: AsyncData<List<ViceActivity>>(<ViceActivity>[
            for (final HabitUse u in s.uses) fakeActivity(u.habitId, 1, u.at),
          ]),
        ),
        healthConnectedProvider.overrideWith((ref) async => true),
      ],
    );
    addTearDown(container.dispose);
    final ProviderSubscription<AsyncValue<InsightsView>> sub = container.listen(
      insightsProvider,
      (_, _) {},
    );
    addTearDown(sub.close);
    InsightsView? view;
    for (int i = 0; i < 200 && view?.result == null; i++) {
      await Future<void>.delayed(Duration.zero);
      view = container.read(insightsProvider).value;
    }
    expect(view!.hoursPending, isTrue);
    expect((view.result! as InsightsComputed).report.hoursAfterChecks, 0);
    gate.complete();
    for (int i = 0; i < 400 && view!.hoursPending; i++) {
      await Future<void>.delayed(Duration.zero);
      view = container.read(insightsProvider).value;
    }
    expect(view!.hoursPending, isFalse);
    expect(
      (view.result! as InsightsComputed).report.hoursAfterChecks,
      greaterThan(0),
    );
  });

  test('a sample read Health has not been asked for leaves it out', () async {
    final FakeHealthSource health = FakeHealthSource(
      read: daily(),
      sampleFailure: PlatformException(code: hs.healthNotDetermined),
    );
    final InsightsResult? result = (await run(
      health,
      insightsHoursYear(),
    )).result;
    expect(result, isA<InsightsComputed>());
    expect(
      (result! as InsightsComputed).report.findings.where(
        (f) => f.kind == InsightKind.hoursAfter,
      ),
      isEmpty,
    );
    expect(health.sampleCalls, 1);
  });
}
