import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/insights/before_use.dart';
import 'package:tracker/insights/before_use_copy.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/what_follows.dart';

BeforeUse finding(
  BeforeUseKind kind,
  String metricId,
  double effect, {
  String habit = 'coffee',
  RefusalReason? refusal,
}) => BeforeUse(
  habitId: habit,
  metricId: metricId,
  kind: kind,
  usableDays: 64,
  exposedDays: kind == BeforeUseKind.whether ? 22 : 64,
  effect: effect,
  interval: Interval(effect - 8, effect + 8),
  pValue: 0.001,
  refusal: refusal,
);

void main() {
  final BeforeUse whether = finding(BeforeUseKind.whether, 'sleepAsleep', -24);
  final BeforeUse hour = BeforeUse(
    habitId: 'coffee',
    metricId: hourBeforeMetricId,
    kind: BeforeUseKind.hourBefore,
    usableDays: 50,
    exposedDays: 30,
    effect: 10,
    interval: const Interval(4, 16),
    pValue: 0.001,
  );

  test('one card per habit, its largest finding against its floor first, '
      'refusals left out', () {
    final List<BeforeUseCard> cards = beforeUseCards(<BeforeUse>[
      whether,
      hour,
      finding(
        BeforeUseKind.whether,
        'sleepAsleep',
        -90,
        refusal: RefusalReason.chance,
      ),
      finding(BeforeUseKind.whether, 'sleepAsleep', -30, habit: 'tea'),
    ]);
    expect(cards.map((c) => c.habitId), <String>['coffee', 'tea']);
    expect(cards.first.headline, hour);
    expect(cards.first.others, <BeforeUse>[whether]);
  });
}
