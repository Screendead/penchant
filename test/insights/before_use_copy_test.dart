import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/insights/before_use.dart';
import 'package:tracker/insights/before_use_copy.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/what_follows.dart';
import 'package:tracker/insights_page.dart';
import 'package:tracker/widgets/before_use_card.dart';

BeforeUse finding(
  BeforeUseKind kind,
  String metricId,
  double effect, {
  String habit = 'coffee',
  double step = 1,
  double? spread,
  RefusalReason? refusal,
}) => BeforeUse(
  habitId: habit,
  metricId: metricId,
  kind: kind,
  usableDays: 64,
  exposedDays: kind == BeforeUseKind.whether ? 22 : 64,
  step: step,
  effect: effect,
  interval: Interval(effect - 8, effect + 8),
  pValue: 0.001,
  spread: spread,
  refusal: refusal,
);

void main() {
  final BeforeUse whether = finding(BeforeUseKind.whether, 'sleepAsleep', -24);
  final BeforeUse amount = finding(
    BeforeUseKind.amount,
    'sleepAsleep',
    -12,
    spread: 2,
  );
  final BeforeUse early = finding(
    BeforeUseKind.firstUse,
    'sleepAsleep',
    -15,
    step: 60,
    spread: 90,
  );
  final BeforeUse hrv = finding(
    BeforeUseKind.whether,
    'heartRateVariabilitySDNN',
    -10,
  );
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

  test('each kind reads as what came before, never as a cause', () {
    expect(
      beforeUseSentence(whether, 'Coffee', 'en'),
      'The night before a day with Coffee, your time asleep averages 24 min '
      'less than before a day without it.',
    );
    expect(
      beforeUseSentence(amount, 'Coffee', 'en', unit: Unit.drink),
      'The night before a day with one more drink logged for Coffee, your '
      'time asleep averages 12 min less.',
    );
    expect(
      beforeUseSentence(early, 'Coffee', 'en'),
      'The night before a day your first use of Coffee comes an hour '
      'earlier, your time asleep averages 15 min less, at the same waking '
      'time.',
    );
    expect(
      beforeUseSentence(hrv, 'Coffee', 'en'),
      'The day before a day with Coffee, your heart rate variability '
      'averages 10 ms lower than before a day without it.',
    );
    expect(
      beforeUseSentence(hour, 'Coffee', 'en'),
      'In the hour before Coffee, your heart rate averages 10 bpm higher '
      'than in the same hour after waking on nearby days without it.',
    );
    expect(beforeUseBasis(whether, 'Coffee'), 'From 64 days, 22 of them with Coffee');
    expect(
      beforeUseBasis(hour, 'Coffee'),
      'From 30 days with Coffee, against 20 days at the same time after '
      'waking with none of it within 4 hours',
    );
    expect(
      beforeUseLine(hour, 'en'),
      'In the hour before it: heart rate 10 bpm higher',
    );
  });

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

  test('Copy as text carries the section under its heading', () {
    final BeforeUseCard card = beforeUseCards(<BeforeUse>[whether, hour]).single;
    final String text = insightsText(
      cards: const [],
      refused: const [],
      firstDay: null,
      nameOf: (_) => 'Coffee',
      locale: 'en',
      setsOff: <List<String>>[beforeUseText(card, 'Coffee', 'en')],
    );
    expect(
      text,
      contains(
        '\n${InsightsPage.setsOffHeading}\n\nCoffee\n'
        '${beforeUseSentence(hour, 'Coffee', 'en')}\n'
        'Range: 4 to 16 bpm higher\n',
      ),
    );
    expect(text, contains(beforeUseLine(whether, 'en')));
    expect(
      insightsText(
        cards: const [],
        refused: const [],
        firstDay: null,
        nameOf: (_) => 'Coffee',
        locale: 'en',
      ),
      isNot(contains(InsightsPage.setsOffHeading)),
    );
  });

  testWidgets('the card shows the headline, its range and basis, then the '
      'rest as lines', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: Scaffold(
          body: BeforeUseCardView(
            card: beforeUseCards(<BeforeUse>[whether, hour]).single,
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
    expect(find.text(beforeUseSentence(hour, 'Coffee', 'en')), findsOneWidget);
    expect(find.text('Range: 4 to 16 bpm higher'), findsOneWidget);
    expect(find.text(beforeUseBasis(hour, 'Coffee')), findsOneWidget);
    expect(
      find.text(
        'The night before a day with it: time asleep 24 min less',
      ),
      findsOneWidget,
    );
  });
}
