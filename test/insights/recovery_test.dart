import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/recovery.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/what_follows.dart';

import 'hours_after_synthetic.dart' show syntheticStart;
import 'recovery_synthetic.dart';

List<Recovery> run(RecoveryDays d, {Set<String> skip = const <String>{}}) =>
    recoveryAfterHeavyDays(
      uses: d.uses,
      outcomes: OutcomeSeries.fromOutcomes(d.outcomes),
      through: d.through,
      floors: syntheticFloors,
      skip: skip,
    );

Recovery sleepOf(List<Recovery> results) =>
    results.singleWhere((Recovery r) => r.metricId == 'sleepAsleep');

RecoveryNight night(
  double effect,
  double p, {
  bool off = false,
  bool back = false,
}) => RecoveryNight(
  effect: effect,
  interval: Interval(effect - 5, effect + 5),
  pValue: p,
  off: off,
  back: back,
);

Recovery fitted(List<RecoveryNight> nights, {RefusalReason? refusal}) =>
    Recovery(
      habitId: 'Beer',
      metricId: 'sleepAsleep',
      usableDays: 100,
      heavyDays: 20,
      cut: 5,
      floor: 20,
      nights: nights,
      refusal: refusal,
    );

// Beer every other day for [days] days, [amountOn] of it on use day i, and a
// flat night's sleep but for a ripple.
RecoveryDays everyOtherDay(int days, int Function(int i) amountOn) => (
  uses: <HabitUse>[
    for (int i = 0; i < days; i += 2)
      for (int k = 0; k < amountOn(i ~/ 2); k++)
        HabitUse(
          habitId: 'Beer',
          at: addDays(syntheticStart, i).add(Duration(hours: 18, minutes: k)),
          amount: 1,
        ),
  ],
  outcomes: <DailyOutcome>[
    for (int i = 0; i < days; i++)
      DailyOutcome(
        date: addDays(syntheticStart, i),
        metricId: 'sleepAsleep',
        value: 420 + 10.0 * ((i * 7) % 5),
      ),
  ],
  through: addDays(syntheticStart, days - 1),
);

void main() {
  group('heavyCut', () {
    test('is the smallest total at or over the upper quartile', () {
      expect(heavyCut(<double>[1, 2, 3, 4, 5, 6]), 5);
      expect(heavyCut(<double>[2, 2, 2, 3, 3, 3]), 3);
      expect(heavyCut(<double>[1, 1, 1, 1, 1, 1, 1, 2]), 2);
    });

    test('is null when no day is over the median', () {
      expect(heavyCut(<double>[2, 2, 2, 2]), isNull);
      expect(heavyCut(<double>[3]), isNull);
      expect(heavyCut(<double>[]), isNull);
    });
  });

  group('recoveryAfterHeavyDays', () {
    test('a heavy day that costs one night is off that night and back by '
        'the second', () {
      final Recovery r = sleepOf(
        run(recoveryDays(1, days: 600, costs: <double>[1.5])),
      );

      expect(r.refusal, isNull);
      expect(r.cut, syntheticHeavyFrom);
      expect(r.heavyDays, greaterThan(60));
      expect(r.nights, hasLength(recoveryNights));
      expect(r.nights.first.effect, closeTo(-60, 20));
      expect(r.nights.first.interval.high, lessThan(0));
      expect(r.offNights, 1);
      expect(r.backBy, 2);
    });

    test('one that costs two nights is off for both and back by the '
        'third', () {
      final Recovery r = sleepOf(
        run(recoveryDays(2, days: 600, costs: <double>[1.5, 1.5])),
      );

      expect(r.refusal, isNull);
      expect(r.nights[1].effect, closeTo(-60, 20));
      expect(r.offNights, 2);
      expect(r.backBy, 3);
    });

    test('a day measure reads the same way, with the heavy day itself held '
        'apart', () {
      final Recovery r = run(
        recoveryDays(3, days: 240, costs: <double>[1.5]),
      ).singleWhere((Recovery r) => r.metricId == 'restingHeartRate');

      expect(r.refusal, isNull);
      expect(r.nights.first.effect, closeTo(3, 1));
      expect(r.nights.first.off, isTrue);
    });

    test('noise is refused as within the noise, its nights still counted', () {
      final Recovery r = sleepOf(run(recoveryDays(4)));

      expect(r.refusal, RefusalReason.withinNoise);
      expect(r.nights, hasLength(recoveryNights));
      expect(recoveryPValues(<Recovery>[r]), hasLength(recoveryNights));
    });

    test('the first night of sleep rests only on nights whose night before '
        'the heavy day is known', () {
      final RecoveryDays d = recoveryDays(1, costs: <double>[1]);
      final Map<DateTime, int> beers = <DateTime, int>{};
      for (final HabitUse use in d.uses) {
        final DateTime day = startOfDay(use.at);
        beers[day] = (beers[day] ?? 0) + 1;
      }
      final List<Recovery> results = run((
        uses: d.uses,
        outcomes: <DailyOutcome>[
          for (final DailyOutcome o in d.outcomes)
            if ((beers[o.date] ?? 0) < syntheticHeavyFrom) o,
        ],
        through: d.through,
      ));

      final Recovery sleep = sleepOf(results);
      expect(sleep.cut, syntheticHeavyFrom);
      expect(sleep.heavyDays, greaterThanOrEqualTo(7));
      expect(sleep.refusal, RefusalReason.tooFewDays);
      expect(sleep.nights, isEmpty);
      expect(
        results
            .singleWhere((Recovery r) => r.metricId == 'restingHeartRate')
            .nights,
        hasLength(recoveryNights),
      );
    });

    test('too few days are refused unfitted', () {
      final Recovery r = sleepOf(run(recoveryDays(5, days: 15)));

      expect(r.refusal, RefusalReason.tooFewDays);
      expect(r.nights, isEmpty);
    });

    test('too few heavy days are refused unfitted', () {
      final Recovery r = sleepOf(
        run(everyOtherDay(80, (int i) => i % 10 == 0 ? 6 : 1)),
      );

      expect(r.cut, 6);
      expect(r.heavyDays, lessThan(7));
      expect(r.refusal, RefusalReason.tooFewDays);
      expect(r.nights, isEmpty);
    });

    test('a habit always logged at one amount has no heavy day', () {
      final Recovery r = sleepOf(run(everyOtherDay(80, (_) => 2)));

      expect(r.cut, isNull);
      expect(r.refusal, RefusalReason.steadyAmount);
      expect(r.nights, isEmpty);
    });

    test('a use before 05:00 counts toward the evening before', () {
      final RecoveryDays d = everyOtherDay(80, (int i) => i.isEven ? 1 : 2);
      final List<HabitUse> uses = <HabitUse>[
        for (final HabitUse u in d.uses)
          // The second of two moves to 01:00 the next morning.
          u.at.minute == 1
              ? HabitUse(
                  habitId: u.habitId,
                  at: addDays(
                    startOfDay(u.at),
                    1,
                  ).add(const Duration(hours: 1)),
                  amount: 1,
                )
              : u,
      ];
      final Recovery r = sleepOf(
        run((uses: uses, outcomes: d.outcomes, through: d.through)),
      );

      expect(r.cut, 2);
      expect(r.heavyDays, greaterThanOrEqualTo(7));
    });

    test('an archived habit and a measure without a floor are left out', () {
      final RecoveryDays d = recoveryDays(6);

      expect(run(d, skip: <String>{'Beer'}), isEmpty);
      expect(
        recoveryAfterHeavyDays(
          uses: d.uses,
          outcomes: OutcomeSeries.fromOutcomes(d.outcomes),
          through: d.through,
          floors: const <String, double>{'restingHeartRate': 1},
        ).map((Recovery r) => r.metricId),
        <String>['restingHeartRate'],
      );
    });
  });

  group('how the nights read', () {
    test('the run of nights off ends at one that is unclear, back or on '
        'the other side', () {
      expect(
        fitted(<RecoveryNight>[
          night(-30, 0.001, off: true),
          night(-25, 0.001, off: true),
          night(-22, 0.001, off: true),
        ]).offNights,
        3,
      );
      expect(
        fitted(<RecoveryNight>[
          night(-30, 0.001, off: true),
          night(-10, 0.2),
          night(-25, 0.001, off: true),
        ]).offNights,
        1,
      );
      expect(
        fitted(<RecoveryNight>[
          night(-30, 0.001, off: true),
          night(25, 0.001, off: true),
          night(0, 0.9, back: true),
        ]).offNights,
        1,
      );
    });

    test('back is the first night after them shown within the floor', () {
      expect(
        fitted(<RecoveryNight>[
          night(-30, 0.001, off: true),
          night(-10, 0.2),
          night(1, 0.9, back: true),
        ]).backBy,
        3,
      );
      expect(
        fitted(<RecoveryNight>[
          night(-30, 0.001, off: true),
          night(-10, 0.2),
          night(-8, 0.3),
        ]).backBy,
        isNull,
      );
    });
  });

  group('judgeRecovery', () {
    final List<double> many = List<double>.filled(50, 0.9);

    test('keeps a finding whose nights stand in the family', () {
      final Recovery r = judgeRecovery(<Recovery>[
        fitted(<RecoveryNight>[
          night(-30, 1e-6, off: true),
          night(-25, 1e-5, off: true),
          night(1, 0.9, back: true),
        ]),
      ], alongside: many).single;

      expect(r.refusal, isNull);
      expect(r.offNights, 2);
      expect(r.backBy, 3);
    });

    test('refuses a first night that may be chance among the page\'s '
        'comparisons', () {
      final List<Recovery> one = <Recovery>[
        fitted(<RecoveryNight>[
          night(-30, 0.04, off: true),
          night(-2, 0.8),
          night(1, 0.9),
        ]),
      ];

      expect(
        judgeRecovery(one, alongside: const <double>[]).single.refusal,
        RefusalReason.chance,
      );
      expect(
        judgeRecovery(one, alongside: many).single.refusal,
        RefusalReason.chance,
      );
      expect(
        judgeRecovery(<Recovery>[
          fitted(<RecoveryNight>[
            night(-30, 0.03, off: true),
            night(-2, 0.8),
            night(1, 0.9),
          ]),
        ], alongside: const <double>[]).single.refusal,
        isNull,
      );
    });

    test('refuses a first night under the floor as too small', () {
      final Recovery r = judgeRecovery(<Recovery>[
        fitted(<RecoveryNight>[
          night(-12, 1e-6, off: true),
          night(-2, 0.8),
          night(1, 0.9),
        ]),
      ], alongside: many).single;

      expect(r.refusal, RefusalReason.tooSmall);
    });

    test('a later night that may be chance is no longer off', () {
      final Recovery r = judgeRecovery(<Recovery>[
        fitted(<RecoveryNight>[
          night(-30, 1e-6, off: true),
          night(-25, 0.04, off: true),
          night(1, 0.9, back: true),
        ]),
      ], alongside: many).single;

      expect(r.refusal, isNull);
      expect(r.nights[1].off, isFalse);
      expect(r.offNights, 1);
      expect(r.backBy, 3);
    });

    test('leaves a refusal as it was', () {
      final Recovery r = judgeRecovery(<Recovery>[
        fitted(<RecoveryNight>[
          night(-30, 1e-6, off: true),
          night(-2, 0.8),
          night(1, 0.9),
        ], refusal: RefusalReason.oneDay),
        fitted(const <RecoveryNight>[], refusal: RefusalReason.tooFewDays),
      ], alongside: many).first;

      expect(r.refusal, RefusalReason.oneDay);
    });
  });
}
