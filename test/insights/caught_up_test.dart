import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/activity_content.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/insights/before_use.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/from_journal.dart';
import 'package:tracker/insights/habit_follows.dart';
import 'package:tracker/insights/health_source.dart' show HealthMetric;
import 'package:tracker/insights/trigger_amounts.dart';
import 'package:tracker/insights/what_follows.dart';

final DateTime monday = DateTime(2026, 3, 2);

HabitUse use(DateTime at, {String habit = 'Wine', bool caughtUp = false}) =>
    HabitUse(habitId: habit, at: at, amount: 1, caughtUp: caughtUp);

ViceActivity activity(LoggedVia? via, {bool locked = false}) => ViceActivity(
  id: 'a',
  viceID: 'Wine',
  quantity: 2,
  ownerID: 'owner',
  createdAt: Timestamp.fromDate(monday.add(const Duration(hours: 20))),
  loggedVia: via,
  locked: locked,
);

void main() {
  test('a caught-up entry is flagged from its content; locked is not', () {
    expect(habitUsesFrom([activity(LoggedVia.caughtUp)]).single.caughtUp, true);
    expect(habitUsesFrom([activity(LoggedVia.spoken)]).single.caughtUp, false);
    expect(
      habitUsesFrom([activity(null, locked: true)]).single.caughtUp,
      false,
    );
  });

  group('day totals', () {
    // Recalled for Tuesday, the model guessing 01:00.
    final DateTime tuesday = addDays(monday, 1);
    final DailyHabitSeries series = DailyHabitSeries.fromUses(<HabitUse>[
      use(monday.add(const Duration(hours: 21))),
      use(tuesday.add(const Duration(hours: 1)), caughtUp: true),
    ]);

    test('count a caught-up entry on its calendar day', () {
      expect(series.total('Wine', tuesday), 1);
      expect(series.lateDayTotal('Wine', tuesday), 1);
      expect(series.lateDayTotal('Wine', monday), 1);
      expect(series.lateDays('Wine').toSet(), <DateTime>{monday, tuesday});
    });

    test('give no last-use time on a day holding a caught-up entry', () {
      expect(series.lastUseMinutes('Wine', monday), 21 * 60);
      expect(series.lastUseMinutes('Wine', tuesday), isNull);
      final DailyHabitSeries mixed = DailyHabitSeries.fromUses(<HabitUse>[
        use(monday.add(const Duration(hours: 19))),
        use(monday.add(const Duration(hours: 22)), caughtUp: true),
      ]);
      expect(mixed.lateDayTotal('Wine', monday), 2);
      expect(mixed.lastUseMinutes('Wine', monday), isNull);
    });
  });

  test('timed uses leave out every use of a habit on a caught-up day', () {
    final HabitUse live = use(monday.add(const Duration(hours: 19)));
    final HabitUse other = use(
      monday.add(const Duration(hours: 19)),
      habit: 'Coffee',
    );
    final HabitUse nextDay = use(
      addDays(monday, 1).add(const Duration(hours: 19)),
    );
    expect(
      timedUses(<HabitUse>[
        live,
        use(monday.add(const Duration(hours: 22)), caughtUp: true),
        other,
        nextDay,
      ]),
      <HabitUse>[other, nextDay],
    );
  });

  test('first use of the day leaves out a caught-up day', () {
    final Map<String, Map<DateTime, int>> first = firstUseMinutes(<HabitUse>[
      use(monday.add(const Duration(hours: 9))),
      use(monday.add(const Duration(hours: 18)), caughtUp: true),
      use(addDays(monday, 1).add(const Duration(hours: 10))),
    ]);
    expect(first['Wine'], <DateTime, int>{addDays(monday, 1): 10 * 60});
  });

  test('time of last use skips a caught-up day; amount keeps it', () {
    final String deep = HealthMetric.sleepDeep.id;
    final Random random = Random(3);
    final List<HabitUse> uses = <HabitUse>[];
    final List<DailyOutcome> outcomes = <DailyOutcome>[];
    for (int i = 0; i < 60; i++) {
      final DateTime day = addDays(monday, i);
      uses.add(
        use(
          day.add(Duration(minutes: 17 * 60 + random.nextInt(300))),
          caughtUp: i.isEven,
        ),
      );
      outcomes.add(
        DailyOutcome(
          date: addDays(day, 1),
          metricId: deep,
          value: 60 + random.nextDouble() * 20,
        ),
      );
    }
    final DailyHabitSeries habits = DailyHabitSeries.fromUses(uses);
    final OutcomeSeries series = OutcomeSeries.fromOutcomes(outcomes);
    final HabitInsight time = lastUseFollows(
      habits: habits,
      outcomes: series,
      metricId: deep,
    ).single;
    final HabitInsight amount = doseFollows(
      habits: habits,
      outcomes: series,
      metricId: deep,
    ).single;
    expect(time.usableDays, 30);
    expect(amount.usableDays, 60);
  });

  test('one habit after another ignores a caught-up use', () {
    // Coffee within minutes of every Wine, but every Coffee caught up.
    final List<HabitUse> uses = <HabitUse>[
      for (int i = 0; i < 40; i++) ...<HabitUse>[
        use(addDays(monday, i).add(const Duration(hours: 20))),
        use(
          addDays(monday, i).add(const Duration(hours: 20, minutes: 5)),
          habit: 'Coffee',
          caughtUp: true,
        ),
      ],
    ];
    expect(habitFollows(uses: uses, through: addDays(monday, 40)), isEmpty);
  });

  test('triggers count a caught-up entry on its calendar day', () {
    final DateTime tuesday = addDays(monday, 1);
    final List<HabitTriggers> live = triggerAmounts(
      uses: <HabitUse>[
        HabitUse(
          habitId: 'Wine',
          at: tuesday.add(const Duration(hours: 1)),
          amount: 1,
          triggers: const <String>['social'],
        ),
      ],
      through: monday,
    );
    final List<HabitTriggers> caughtUp = triggerAmounts(
      uses: <HabitUse>[
        HabitUse(
          habitId: 'Wine',
          at: tuesday.add(const Duration(hours: 1)),
          amount: 1,
          triggers: const <String>['social'],
          caughtUp: true,
        ),
      ],
      through: monday,
    );
    // Live, 01:00 Tuesday is Monday's evening; caught up, it is Tuesday's,
    // after the last day judged.
    expect(live, isNotEmpty);
    expect(caughtUp, isEmpty);
  });
}
