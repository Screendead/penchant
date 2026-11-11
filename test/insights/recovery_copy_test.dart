import 'package:flutter/material.dart' hide Interval;
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/recovery.dart';
import 'package:tracker/insights/recovery_copy.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/what_follows.dart';
import 'package:tracker/widgets/recovery_card.dart';

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

  test('the sentence names each night still off, then the night it is back '
      'within the floor', () {
    expect(
      recoverySentence(sleep, 'Beer', 'en', unit: Unit.drink),
      'After a day with 4 drinks or more logged for Beer, your time asleep '
      'averages 31 min less than your usual that night and 16 min less the '
      'second night. By '
      'the third night it is back within 21 min of your usual.',
    );
    expect(
      recoverySentence(resting, 'Beer', 'en', unit: Unit.drink),
      'After a day with 4 drinks or more logged for Beer, your resting '
      'heart rate averages 3.0 bpm higher than your usual the next day. By the second day '
      'after it is back within 1.0 bpm of your usual.',
    );
  });

  test('with no night shown to be back, it says that is not clear', () {
    expect(
      recoverySentence(unclear, 'Beer', 'en', unit: Unit.drink),
      'After a day with 4 drinks or more logged for Beer, your heart rate '
      'variability averages 9 ms lower than your usual the next day. When it '
      'comes back to '
      'your usual isn’t clear yet.',
    );
  });

  test('a habit counted in times reads as uses', () {
    expect(
      recoverySentence(unclear, 'Vaping', 'en', unit: Unit.time),
      startsWith('After a day with 4 uses or more logged for Vaping, '),
    );
  });

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

  test('the range and basis are the first night\'s', () {
    expect(recoveryRange(sleep, 'en'), 'Range that night: 12 to 50 min less');
    expect(
      recoveryRange(sleep, 'en', joined: true),
      'Range against your usual that night: 12 to 50 min less',
    );
    expect(
      recoveryRange(resting, 'en'),
      'Range the next day: 1.2 to 4.8 bpm higher',
    );
    expect(
      recoveryBasis(sleep, unit: Unit.drink),
      'From 118 nights, 14 of them straight after a day with 4 drinks or more',
    );
    expect(
      recoveryBasis(resting, unit: Unit.drink),
      'From 118 days, 14 of them straight after a day with 4 drinks or more',
    );
  });

  test('a line says when it is back, how long it is still off, or that it '
      'is not clear', () {
    expect(
      recoveryLine(resting, 'en', unit: Unit.drink),
      'After a day with 4 drinks or more: resting heart rate 3.0 bpm higher '
      'the next day, back by the second day after',
    );
    expect(
      recoveryLine(unclear, 'en', unit: Unit.drink),
      'After a day with 4 drinks or more: heart rate variability 9 ms lower '
      'the next day, not clear yet when it comes back',
    );
    expect(
      recoveryLine(
        recovery('sleepAsleep', 21, <RecoveryNight>[
          night(-31, 9, off: true),
          night(-30, 9, off: true),
          night(-29, 9, off: true),
        ]),
        'en',
        unit: Unit.drink,
      ),
      'After a day with 4 drinks or more: time asleep 31 min less that '
      'night, still off the third night',
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

  test('copied as text: the heading, sentence, range, basis, then lines', () {
    final RecoveryCard card = recoveryCards(<Recovery>[sleep, resting]).single;

    expect(recoveryText(card, 'Beer', 'en', unit: Unit.drink), <String>[
      'Beer · after a heavy day',
      recoverySentence(resting, 'Beer', 'en', unit: Unit.drink),
      'Range the next day: 1.2 to 4.8 bpm higher',
      'From 118 days, 14 of them straight after a day with 4 drinks or more',
      'After a day with 4 drinks or more: time asleep 31 min less that '
          'night, back by the third night',
    ]);
  });

  testWidgets('the card shows the headline, its range and basis, then the '
      'rest as lines', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: Scaffold(
          body: RecoveryCardView(
            card: recoveryCards(<Recovery>[sleep, resting]).single,
            habit: 'Beer',
            unit: Unit.drink,
            mark: const HabitMark(0),
            locale: 'en',
            top: 0,
          ),
        ),
      ),
    );

    expect(find.text('Beer · after a heavy day'), findsOneWidget);
    expect(
      find.text(recoverySentence(resting, 'Beer', 'en', unit: Unit.drink)),
      findsOneWidget,
    );
    expect(
      find.text('Range the next day: 1.2 to 4.8 bpm higher'),
      findsOneWidget,
    );
    expect(
      find.text(
        'From 118 days, 14 of them straight after a day with 4 drinks or more',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'After a day with 4 drinks or more: time asleep 31 min less that '
        'night, back by the third night',
      ),
      findsOneWidget,
    );
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

    test('says "such a day" for the same cut and the heavy day in full for '
        'another', () {
      expect(
        recoveryJoinedSentence(
          line('sleepAsleep', 4),
          sleep,
          'Beer',
          'en',
          unit: Unit.drink,
        ),
        'On days with 4 drinks or more logged for Beer, your time asleep that '
        'night averages 25 min less than on days with fewer; after such a day '
        'it averages 31 min less than your usual that night and 16 min less the '
        'second night. '
        'By the third night it is back within 21 min of your usual.',
      );
      expect(
        recoveryJoinedLine(
          line('sleepAsleep', 3),
          sleep,
          'en',
          unit: Unit.drink,
        ),
        'From 3 drinks a day: time asleep 25 min less; after a day with 4 '
        'drinks or more 31 min less that night, back by the third night',
      );
      expect(
        recoveryJoinedBasis(line('sleepAsleep', 3), sleep, unit: Unit.drink),
        'From 118 nights, 14 of them straight after a day with 4 drinks or '
        'more',
      );
    });
  });
}
