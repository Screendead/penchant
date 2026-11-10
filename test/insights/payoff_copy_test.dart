import 'package:flutter/material.dart' hide Interval;
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/insights/payoff.dart';
import 'package:tracker/insights/payoff_copy.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights_page.dart';
import 'package:tracker/widgets/payoff_card.dart';

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
  String? other,
  bool capped = false,
  double half = 8,
}) => Payoff(
  fall: fall(habit),
  metricId: metricId,
  baselineValues: 88,
  sinceValues: 41,
  capped: capped,
  effect: effect,
  interval: Interval(effect - half, effect + half),
  pValue: 0.001,
  refusal: refusal,
  otherHabitId: other,
);

void main() {
  final Payoff sleep = result('sleepAsleep', 24);
  final Payoff resting = result('restingHeartRate', -6, half: 1);

  test('the fall reads as what the journal holds, never as cutting down', () {
    expect(
      fallSentence(fall('coffee'), 'Coffee', 'en', unit: Unit.drink),
      'Your logged amount of Coffee fell from about 3.6 drinks a day to 1.5 '
      'around Mar 3, 2026.',
    );
    expect(
      fallSentence(
        fall('coffee', before: 0.5, since: 0.1),
        'Coffee',
        'en',
        unit: Unit.time,
      ),
      'Your logged amount of Coffee fell from about 3.5 uses a week to 0.7 '
      'around Mar 3, 2026.',
    );
    expect(
      fallSentence(
        fall('coffee', before: 12.2, since: 0),
        'Coffee',
        'en',
        unit: Unit.puff,
      ),
      'No entries for Coffee since Mar 3, 2026, from about 12 puffs a day '
      'before.',
    );
  });

  test('a finding says since when, against which weeks, and that the trend '
      'is allowed for', () {
    expect(
      payoffSentence(sleep, 'en'),
      'Since then, your time asleep averages 24 min more than in the 13 '
      'weeks before, allowing for the trend it was already on.',
    );
    expect(
      payoffSentence(result('restingHeartRate', -6, capped: true), 'en'),
      'In the 13 weeks after, your resting heart rate averages 6.0 bpm lower '
      'than in the 13 weeks before, allowing for the trend it was already '
      'on.',
    );
    expect(payoffBasis(sleep), 'From 88 nights before and 41 since');
    expect(payoffBasis(resting), 'From 88 days before and 41 since');
    expect(
      payoffLine(resting, 'en'),
      'Also since: resting heart rate 6.0 bpm lower',
    );
  });

  test('each refusal says why in plain words', () {
    String why(PayoffRefusal reason) => payoffRefusal(
      result('sleepAsleep', 24, refusal: reason, other: 'tea'),
      (String id) => id == 'tea' ? 'Tea' : id,
    );
    expect(
      why(PayoffRefusal.tooFewDays),
      'Too few days of Apple Health on each side of it to compare yet.',
    );
    expect(
      why(PayoffRefusal.otherFall),
      'Your logged amount of Tea fell within two weeks of it, so what moved '
      'since can’t be put down to either.',
    );
    expect(
      why(PayoffRefusal.withinNoise),
      'No clear difference in your sleep, heart or activity since: within '
      'the noise.',
    );
    expect(
      why(PayoffRefusal.alreadyMoving),
      'Your time asleep was already shifting before it, so the change since '
      'can’t be told apart from that.',
    );
    expect(
      why(PayoffRefusal.chance),
      'What moved since could be chance: one of many comparisons.',
    );
    expect(
      why(PayoffRefusal.tooSmall),
      'What moved since is too small to matter.',
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

  test('Copy as text carries the section under its heading', () {
    final List<PayoffCard> cards = payoffCards(<Payoff>[
      sleep,
      resting,
      result(
        'sleepAsleep',
        2,
        habit: 'tea',
        refusal: PayoffRefusal.withinNoise,
      ),
    ]);
    String name(String id) => id == 'tea' ? 'Tea' : 'Coffee';
    final String text = insightsText(
      cards: const [],
      refused: const [],
      firstDay: null,
      nameOf: name,
      locale: 'en',
      cuttingDown: <List<String>>[
        for (final PayoffCard card in cards)
          payoffText(card, name(card.habitId), 'en', nameOf: name),
      ],
    );
    expect(
      text,
      contains(
        '\n${InsightsPage.cuttingDownHeading}\n\nCoffee\n'
        '${fallSentence(fall('coffee'), 'Coffee', 'en')}\n'
        '${payoffSentence(resting, 'en')}\n'
        'Range: 5.0 to 7.0 bpm lower\n'
        'From 88 days before and 41 since\n'
        'Also since: time asleep 24 min more\n'
        '\nTea\n'
        '${fallSentence(fall('tea'), 'Tea', 'en')}\n'
        'No clear difference in your sleep, heart or activity since: within '
        'the noise.\n',
      ),
    );
    expect(
      insightsText(
        cards: const [],
        refused: const [],
        firstDay: null,
        nameOf: name,
        locale: 'en',
      ),
      isNot(contains(InsightsPage.cuttingDownHeading)),
    );
  });

  testWidgets('the card shows the fall, the headline with its range and '
      'basis, then the rest as lines', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: Scaffold(
          body: PayoffCardView(
            card: payoffCards(<Payoff>[sleep, resting]).single,
            habit: 'Coffee',
            unit: Unit.drink,
            mark: const HabitMark(0),
            locale: 'en',
            top: 0,
          ),
        ),
      ),
    );
    expect(find.text('Coffee'), findsOneWidget);
    expect(
      find.text(fallSentence(fall('coffee'), 'Coffee', 'en', unit: Unit.drink)),
      findsOneWidget,
    );
    expect(find.text(payoffSentence(resting, 'en')), findsOneWidget);
    expect(find.text('Range: 5.0 to 7.0 bpm lower'), findsOneWidget);
    expect(find.text('From 88 days before and 41 since'), findsOneWidget);
    expect(find.text('Also since: time asleep 24 min more'), findsOneWidget);
  });
}
