// How long one report takes on a year of three habits, nine daily Health
// measures with noise that carries over from day to day, and heart-rate
// samples. Run alone, so nothing else shares the machine's clock:
//   flutter test tools/insights-calibration/report_timing_test.dart
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/health_source.dart' show HealthMetric;
import 'package:tracker/insights/insights_report.dart';

import '../../test/insights/hours_after_synthetic.dart';
import '../../test/insights_harness.dart';

double gaussian(Random r) =>
    sqrt(-2 * log(1 - r.nextDouble())) * cos(2 * pi * r.nextDouble());

InsightsInput yearInput() {
  final Synthetic s = insightsHoursYear();
  final Random random = Random(3);
  final Set<DateTime> coffeeDays = <DateTime>{
    for (final HabitUse u in s.uses)
      if (u.habitId == 'coffee') startOfDay(u.at),
  };
  final List<DailyOutcome> outcomes = <DailyOutcome>[];
  for (final HealthMetric m in <HealthMetric>[
    HealthMetric.sleepAsleep,
    HealthMetric.sleepCore,
    HealthMetric.sleepDeep,
    HealthMetric.sleepREM,
    HealthMetric.heartRateVariabilitySDNN,
    HealthMetric.restingHeartRate,
    HealthMetric.respiratoryRate,
    HealthMetric.stepCount,
    HealthMetric.activeEnergyBurned,
  ]) {
    double carried = 0;
    for (int back = 365; back >= 1; back--) {
      final DateTime day = addDays(insightsToday, -back);
      carried = 0.5 * carried + 20 * gaussian(random);
      final bool moved =
          m == HealthMetric.sleepDeep &&
          coffeeDays.contains(addDays(day, -1));
      outcomes.add(
        DailyOutcome(
          date: day,
          metricId: m.id,
          value: 300 + carried + (moved ? -25 : 0),
        ),
      );
    }
  }
  return InsightsInput(
    uses: s.uses,
    outcomes: outcomes,
    from: addDays(insightsToday, -365),
    through: addDays(insightsToday, -1),
    samples: s.samples,
  );
}

void main() {
  test('one report on the synthetic year', () {
    final InsightsInput input = yearInput();
    computeInsights(input);
    final List<int> runs = <int>[];
    late InsightsReport report;
    for (int i = 0; i < 3; i++) {
      final Stopwatch watch = Stopwatch()..start();
      report = computeInsights(input);
      runs.add(watch.elapsedMilliseconds);
    }
    stdout.writeln(
      'report on the synthetic year: $runs ms; findings '
      '${report.findings.length}, refused ${report.refused.length}',
    );
  }, timeout: const Timeout(Duration(minutes: 10)));
}
