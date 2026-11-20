import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/recovery.dart';
import 'package:tracker/insights/recovery_copy.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/what_follows.dart';

RecoveryNight night(
  double effect,
  double spread, {
  bool off = false,
  bool back = false,
}) => RecoveryNight(
  effect: effect,
  interval: Interval(effect - spread, effect + spread),
  pValue: off ? 0.001 : 0.5,
  off: off,
  back: back,
);

Recovery recovery(
  String metricId,
  double floor,
  List<RecoveryNight> nights, {
  String habit = 'beer',
}) => Recovery(
  habitId: habit,
  metricId: metricId,
  usableDays: 118,
  heavyDays: 14,
  cut: 4,
  floor: floor,
  nights: nights,
);

void main() {
  final Recovery sleep = recovery('sleepAsleep', 21, <RecoveryNight>[
    night(-31, 19, off: true),
    night(-16, 12, off: true),
    night(2, 12, back: true),
  ]);
  final Recovery resting = recovery('restingHeartRate', 1, <RecoveryNight>[
    night(3, 1.8, off: true),
    night(0.2, 0.7, back: true),
    night(0.1, 0.7, back: true),
  ]);
  final Recovery unclear = recovery(
    'heartRateVariabilitySDNN',
    4,
    <RecoveryNight>[night(-9, 4, off: true), night(-3, 5), night(-1, 5)],
  );

  test('the floor is rounded up, so "within" stays true', () {
    final Recovery r = recovery(
      'heartRateVariabilitySDNN',
      3.2,
      <RecoveryNight>[night(-9, 4, off: true), night(0, 2, back: true)],
    );

    expect(
      recoverySentence(r, 'Beer', 'en'),
      endsWith('By the second day after it is back within 4 ms of your usual.'),
    );
  });

  test('one card per habit, the largest first night against its floor '
      'leading, refusals left out', () {
    final List<RecoveryCard> cards = recoveryCards(<Recovery>[
      sleep,
      resting,
      unclear,
      recovery('sleepAsleep', 21, <RecoveryNight>[
        night(-25, 9, off: true),
        night(0, 9, back: true),
      ], habit: 'wine'),
      Recovery(
        habitId: 'tea',
        metricId: 'sleepAsleep',
        usableDays: 30,
        heavyDays: 2,
        refusal: RefusalReason.tooFewDays,
      ),
    ]);

    expect(cards.map((RecoveryCard c) => c.habitId), <String>['beer', 'wine']);
    expect(cards.first.headline, resting);
    expect(cards.first.others, <Recovery>[unclear, sleep]);
  });

  group('joined to a line in the amount', () {
    HabitFinding line(String metricId, double cut) => HabitFinding(
      habitId: 'beer',
      metricId: metricId,
      lagDays: 1,
      usableDays: 120,
      exposedDays: 41,
      raw: null,
      kind: InsightKind.doseLine,
      cut: cut,
      effect: -25,
      interval: Interval(-37, -12),
      standardized: -0.5,
      pValue: 0.001,
    );

    test('takes only the finding on the line\'s habit and measure', () {
      final ({Map<(String, String), Recovery> joined, List<Recovery> rest})
      split = joinRecovery(
        <InsightCard>[
          InsightCard(
            family: MetricFamily.sleep,
            headline: line('sleepAsleep', 4),
          ),
        ],
        <Recovery>[sleep, resting],
      );
      expect(split.joined, <(String, String), Recovery>{
        ('beer', 'sleepAsleep'): sleep,
      });
      expect(split.rest, <Recovery>[resting]);
    });
  });
}
