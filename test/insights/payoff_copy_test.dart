import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/insights/payoff.dart';
import 'package:tracker/insights/payoff_copy.dart';
import 'package:tracker/insights/stats.dart';

HabitFall fall(
  String habit, {
  double before = 3.6,
  double since = 1.5,
  int sinceDays = 60,
}) => HabitFall(
  habitId: habit,
  day: DateTime(2026, 3, 3),
  from: DateTime(2025, 12, 2),
  before: before,
  since: since,
  sinceDays: sinceDays,
);

Payoff result(
  String metricId,
  double effect, {
  String habit = 'coffee',
  PayoffRefusal? refusal,
  double half = 8,
}) => Payoff(
  fall: fall(habit),
  metricId: metricId,
  baselineValues: 88,
  sinceValues: 41,
  capped: false,
  effect: effect,
  interval: Interval(effect - half, effect + half),
  pValue: 0.001,
  refusal: refusal,
);

void main() {
  final Payoff sleep = result('sleepAsleep', 24);
  final Payoff resting = result('restingHeartRate', -6, half: 1);

  test('the fall reads as what the journal holds, never as cutting down', () {
    expect(
      fallSentence(fall('coffee'), 'Coffee', 'en', unit: Unit.drink),
      'Your logged amount of Coffee fell from about 3.6 drinks a day to 1.5 '
      'around March 3, 2026.',
    );
    expect(
      fallSentence(
        fall('coffee', before: 0.5, since: 0.1),
        'Coffee',
        'en',
        unit: Unit.time,
      ),
      'Your logged amount of Coffee fell from about 3.5 uses a week to 0.7 '
      'around March 3, 2026.',
    );
    expect(
      fallSentence(
        fall('coffee', before: 12.2, since: 0),
        'Coffee',
        'en',
        unit: Unit.puff,
      ),
      'No entries for Coffee since March 3, 2026, from about 12 puffs a day '
      'before.',
    );
  });

  test('one card per habit: findings largest against the floor first, a '
      'habit with none keeps its most telling refusal and comes last', () {
    final List<PayoffCard> cards = payoffCards(<Payoff>[
      result(
        'sleepAsleep',
        2,
        habit: 'tea',
        refusal: PayoffRefusal.withinNoise,
      ),
      result('sleepDeep', 1, habit: 'tea', refusal: PayoffRefusal.tooSmall),
      sleep,
      resting,
      result('sleepDeep', 30, refusal: PayoffRefusal.chance),
    ]);
    expect(cards.map((c) => c.habitId), <String>['coffee', 'tea']);
    expect(cards.first.findings, <Payoff>[resting, sleep]);
    expect(cards.first.refusal, isNull);
    expect(cards.last.findings, isEmpty);
    expect(cards.last.refusal!.refusal, PayoffRefusal.tooSmall);
  });
}
