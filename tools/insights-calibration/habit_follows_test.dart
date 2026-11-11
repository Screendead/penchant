// Monte Carlo rates for one habit following another within minutes
// (habitFollows in lib/insights/habit_follows.dart), on synthetic journals
// only. Slow, so it lives outside test/:
//   flutter test tools/insights-calibration/habit_follows_test.dart
// Each line prints one scenario for Cigarettes after Coffee, by the clock
// alone and then with each night's waking from the time in bed: how many
// seeds had a p-value under 0.05 before any correction (a pair too short to
// test counts as none), how many were a finding judged with the reverse pair
// alone, and the mean share and chance. A scenario with no waking of its own
// gets one that owes nothing to its habits: 06:30, sd 30 minutes.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/habit_follows.dart';
import 'package:tracker/insights/health_source.dart';

import '../../test/insights/habit_follows_synthetic.dart';

const int seeds = 400;

typedef Woke = void Function(DateTime day, double minutes);
typedef Journal = List<HabitUse> Function(Random r, int days, Woke woke);

List<HabitUse> eachDay(
  int days,
  Iterable<HabitUse> Function(DateTime day, int index) of,
) => <HabitUse>[
  for (int d = 0; d < days; d++) ...of(addDays(followsStart, d), d),
];

Iterable<HabitUse> scattered(
  String habit,
  DateTime day,
  Random r,
  int count,
  double from,
  double to,
) sync* {
  for (int k = 0; k < count; k++) {
    yield useAt(habit, day, from + r.nextDouble() * (to - from));
  }
}

final Map<String, Journal> noise = <String, Journal>{
  'times of their own (Coffee 2 a morning, Cigarettes 8 a day)': (r, days, _) =>
      eachDay(
        days,
        (day, _) => <HabitUse>[
          ...scattered('coffee', day, r, 2, 7 * 60, 12 * 60),
          ...scattered('cigarettes', day, r, 8, 7 * 60, 23 * 60),
        ],
      ),
  'a shared morning peak (each near 08:00, sd 20 min, apart)': (r, days, _) =>
      eachDay(
        days,
        (day, _) => <HabitUse>[
          useAt('coffee', day, 8 * 60 + 20 * gaussian(r)),
          useAt('cigarettes', day, 8 * 60 + 10 + 20 * gaussian(r)),
          ...scattered('cigarettes', day, r, 5, 9 * 60, 23 * 60),
        ],
      ),
  'both at weekends only': (r, days, _) => eachDay(
    days,
    (day, _) => day.weekday < DateTime.saturday
        ? const <HabitUse>[]
        : <HabitUse>[
            ...scattered('coffee', day, r, 3, 10 * 60, 22 * 60),
            ...scattered('cigarettes', day, r, 8, 10 * 60, 24 * 60),
          ],
  ),
  'late, heavy days (3 in 10: both 4 h later and doubled)': (r, days, _) =>
      eachDay(days, (day, _) {
        final bool late = r.nextDouble() < 0.3;
        final double shift = late ? 240 : 0;
        return <HabitUse>[
          ...scattered(
            'coffee',
            day,
            r,
            late ? 4 : 2,
            8 * 60 + shift,
            12 * 60 + shift,
          ),
          ...scattered(
            'cigarettes',
            day,
            r,
            late ? 12 : 6,
            8 * 60 + shift,
            20 * 60 + shift,
          ),
        ];
      }),
  'Cigarettes in two bursts of four': (r, days, _) => eachDay(days, (day, _) {
    final List<HabitUse> uses = <HabitUse>[
      ...scattered('coffee', day, r, 2, 7 * 60, 12 * 60),
    ];
    for (int b = 0; b < 2; b++) {
      final double at = 7 * 60 + r.nextDouble() * 900;
      uses.addAll(scattered('cigarettes', day, r, 4, at, at + 10));
    }
    return uses;
  }),
  'Cigarettes move from mornings to evenings halfway': (r, days, _) =>
      eachDay(days, (day, d) {
        final double from = d < days ~/ 2 ? 7 * 60 : 17 * 60;
        return <HabitUse>[
          ...scattered('coffee', day, r, 2, 7 * 60, 12 * 60),
          ...scattered('cigarettes', day, r, 6, from, from + 5 * 60),
        ];
      }),
  'Cigarettes logged on 6 days in 10': (r, days, _) => eachDay(
    days,
    (day, _) => <HabitUse>[
      ...scattered('coffee', day, r, 2, 7 * 60, 12 * 60),
      if (r.nextDouble() < 0.6)
        ...scattered('cigarettes', day, r, 8, 7 * 60, 23 * 60),
    ],
  ),
  'waking varies (sd 1 h): Coffee 5 to 60 min after, Cigarettes 10 through '
      'the 16 h awake': (r, days, woke) => eachDay(days, (day, _) {
    final double wake = 7.5 * 60 + 60 * gaussian(r);
    woke(day, wake);
    return <HabitUse>[
      useAt('coffee', day, wake + 5 + r.nextDouble() * 55),
      ...scattered('cigarettes', day, r, 10, wake, wake + 16 * 60),
    ];
  }),
  'bedtime varies (sd 1 h): Coffee in the last hour up, Cigarettes 10 '
      'through the 16 h awake': (r, days, woke) => eachDay(days, (day, _) {
    final double bed = 22.5 * 60 + 60 * gaussian(r);
    woke(day, bed - 16 * 60);
    return <HabitUse>[
      useAt('coffee', day, bed - 5 - r.nextDouble() * 55),
      ...scattered('cigarettes', day, r, 10, bed - 16 * 60, bed),
    ];
  }),
};

const String sharedWaking =
    'waking varies (sd 1 h): Coffee 5 to 20 min after, a Cigarette 5 to 40 '
    'min after, each on its own';

String pct(num n) => '${(100 * n / seeds).toStringAsFixed(1)}%';

class Tally {
  int under = 0, found = 0, tested = 0;
  double share = 0, chance = 0;

  void add(HabitFollows pair) {
    if (pair.verdict == FollowsVerdict.found) found++;
    if (pair.pValue case final double p) {
      tested++;
      if (p < 0.05) under++;
      share += pair.share;
      chance += pair.chance;
    }
  }

  @override
  String toString() =>
      'p < 0.05 ${pct(under)}, found ${pct(found)}, tested $tested, share '
      '${tested == 0 ? '-' : (100 * share / tested).toStringAsFixed(1)}% '
      'against '
      '${tested == 0 ? '-' : (100 * chance / tested).toStringAsFixed(1)}%';
}

// [wakeError]: the sd, in minutes, of Health's waking around the true one.
// [missingNights]: the share of nights Health has nothing for.
void run(
  String name,
  Journal journal, {
  int days = 120,
  double wakeError = 0,
  double missingNights = 0,
}) {
  final Tally byClock = Tally(), withWaking = Tally();
  for (int seed = 0; seed < seeds; seed++) {
    final Map<DateTime, double> wakes = <DateTime, double>{};
    final List<HabitUse> uses = journal(
      Random(seed),
      days,
      (DateTime day, double minutes) => wakes[day] = minutes,
    );
    final Random health = Random(seed * 7919 + 104729);
    final List<HealthSample> bed = <HealthSample>[];
    for (int d = 0; d < days; d++) {
      final DateTime day = addDays(followsStart, d);
      final double wake = wakes[day] ?? 6.5 * 60 + 30 * gaussian(health);
      final double seen = wake + wakeError * gaussian(health);
      if (health.nextDouble() >= missingNights) {
        bed.add(nightEnding(day, seen));
      }
    }
    final DateTime through = uses
        .map((HabitUse u) => startOfDay(u.at))
        .reduce((a, b) => a.isAfter(b) ? a : b);
    HabitFollows pair(List<HealthSample> bed) => judgeHabitFollows(
      habitFollows(uses: uses, through: through, bed: bed),
    ).singleWhere((HabitFollows f) => f.leadId == 'coffee');
    byClock.add(pair(const <HealthSample>[]));
    withWaking.add(pair(bed));
  }
  stdout.writeln(
    '$name, $days days ($seeds seeds)\n'
    '    by the clock: $byClock\n'
    '    with waking:  $withWaking',
  );
}

void main() {
  test('noise', () {
    noise.forEach(run);
  }, timeout: Timeout.none);

  test('a shared anchor', () {
    run(sharedWaking, bothAfterWaking);
    run('$sharedWaking; Health 10 min off (sd)', bothAfterWaking, wakeError: 10);
    run(
      '$sharedWaking; Health 20 min off (sd)',
      bothAfterWaking,
      wakeError: 20,
    );
    run(
      '$sharedWaking; half the nights missing',
      bothAfterWaking,
      missingNights: 0.5,
    );
    run(sharedWaking, bothAfterWaking, days: 60);
  }, timeout: Timeout.none);

  test('a planted effect', () {
    for (final double follow in <double>[0.1, 0.2, 0.3, 0.5]) {
      for (final int days in <int>[30, 60, 120]) {
        run(
          'a Cigarette 3 to 12 min after ${(follow * 100).round()}% of Coffees',
          (Random r, int days, _) => coffeeThenCigarettes(
            r.nextInt(1 << 31),
            days: days,
            follow: follow,
          ),
          days: days,
        );
      }
    }
  }, timeout: Timeout.none);
}
