import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/check_in.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/check_in_urges.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/what_follows.dart';

final DateTime _start = DateTime(2026, 3, 2);

DateTime _at(int day, int hour) =>
    addDays(_start, day).add(Duration(hours: hour));

HabitUse _entry(int day, int? urge, {String habit = 'wine', int hour = 20}) =>
    HabitUse(habitId: habit, at: _at(day, hour), amount: 1, urge: urge);

CheckInAnswer _checkIn(int day, int strength, {int hour = 13}) =>
    (at: _at(day, hour), strength: strength);

List<CheckInUrge> _judge(
  List<HabitUse> uses,
  List<CheckInAnswer> checkIns, {
  int through = 200,
  Set<String> skip = const <String>{},
  InsightGates gates = const InsightGates(),
}) => judgeCheckInUrges(
  checkInUrges(
    uses: uses,
    checkIns: checkIns,
    through: addDays(_start, through),
    skip: skip,
  ),
  alongside: const <double>[],
  gates: gates,
);

double _gaussian(Random r) =>
    sqrt(-2 * log(1 - r.nextDouble())) * cos(2 * pi * r.nextDouble());

int _poisson(Random r, double rate) {
  final double limit = exp(-rate);
  double product = r.nextDouble();
  int n = 0;
  while (product > limit) {
    n++;
    product *= r.nextDouble();
  }
  return n;
}

// One urge runs through each day: a level that drifts from day to day
// ([dayDrift] its lag-1 correlation) plus noise at each moment. A check-in
// reads it as 0 to 5; an entry reads the same urge, plus [planted], as 1 to
// 5, a 0 written as 1, and is likelier on a day of strong urges. With
// [entryDrift], entries alone also carry a level of mean 0 that drifts
// across days: stretches when they run higher or lower, none on average.
({List<HabitUse> uses, List<CheckInAnswer> checkIns}) _journal(
  Random r, {
  int days = 60,
  double dayDrift = 0.7,
  double entryDrift = 0,
  double planted = 0,
}) {
  final List<HabitUse> uses = <HabitUse>[];
  final List<CheckInAnswer> checkIns = <CheckInAnswer>[];
  double level = _gaussian(r), apart = _gaussian(r);
  for (int k = 0; k < days; k++) {
    level = dayDrift * level + sqrt(1 - dayDrift * dayDrift) * _gaussian(r);
    apart = 0.7 * apart + sqrt(1 - 0.49) * _gaussian(r);
    final double urge = 1.8 + 0.8 * level;
    for (int i = 0; i < 3; i++) {
      if (r.nextDouble() < 0.7) {
        checkIns.add(
          _checkIn(
            k,
            (urge + _gaussian(r)).round().clamp(0, 5),
            hour: 9 + 4 * i,
          ),
        );
      }
    }
    final int entries = _poisson(r, (0.6 + 0.5 * urge).clamp(0.2, 4));
    for (int i = 0; i < entries; i++) {
      final int noted = (urge + planted + entryDrift * apart + _gaussian(r))
          .round()
          .clamp(1, 5);
      // One entry in five has its urge left unanswered.
      uses.add(_entry(k, r.nextDouble() < 0.8 ? noted : null, hour: 17 + i));
    }
  }
  return (uses: uses, checkIns: checkIns);
}

({double falseCards, double under5, double clear, int tested}) _null(
  int seed, {
  double entryDrift = 0,
  int journals = 2500,
}) {
  final Random r = Random(seed);
  int cards = 0, tested = 0, under5 = 0, clear = 0;
  for (int j = 0; j < journals; j++) {
    final ({List<HabitUse> uses, List<CheckInAnswer> checkIns}) made = _journal(
      r,
      entryDrift: entryDrift,
    );
    final CheckInUrge u = _judge(made.uses, made.checkIns).single;
    if (u.pValue case final double p) {
      tested++;
      if (p < 0.05) under5++;
      if (u.refusal != RefusalReason.withinNoise) clear++;
    }
    if (u.found) cards++;
  }
  return (
    falseCards: cards / journals,
    under5: under5 / tested,
    clear: clear / tested,
    tested: tested,
  );
}

void main() {
  test('nothing is compared while no check-in is answered', () {
    expect(
      _judge(<HabitUse>[
        for (int k = 0; k < 30; k++) _entry(k, 4),
      ], const <CheckInAnswer>[]),
      isEmpty,
    );
  });

  test('under 14 days with both, it is refused with the count and no '
      'p-value', () {
    final CheckInUrge u = _judge(
      <HabitUse>[for (int k = 0; k < 30; k++) _entry(k, 4)],
      <CheckInAnswer>[for (int k = 0; k < 13; k++) _checkIn(k, 1)],
    ).single;

    expect(u.refusal, RefusalReason.tooFewDays);
    expect(u.pValue, isNull);
    expect(u.days, 13);
    expect(
      checkInUrgeRefusal(u),
      'Urge at entries against check-ins: too few days with both yet: 13 of '
      '14',
    );
  });

  test('a steady higher urge at entries is found, days as the unit, with '
      'the figures the card shows', () {
    final CheckInUrge u = _judge(
      <HabitUse>[
        for (int k = 0; k < 20; k++) ...<HabitUse>[
          _entry(k, 4),
          _entry(k, 4, hour: 21),
          // Unanswered, so not counted.
          _entry(k, null, hour: 22),
        ],
        // Days with no check-in.
        for (int k = 20; k < 40; k++) _entry(k, 1),
      ],
      <CheckInAnswer>[
        for (int k = 0; k < 20; k++) _checkIn(k, k.isEven ? 0 : 2),
      ],
    ).single;

    expect(u.found, isTrue);
    expect(u.days, 20);
    expect(u.entries, 40);
    expect(u.checkIns, 20);
    expect(u.noUrge, 10);
    expect(u.entryMean, 4);
    // A 0 is read as 1, where an entry's scale starts.
    expect(u.checkInMean, 1.5);
    expect(
      checkInUrgeSentence(u, 'Wine', 'en_GB'),
      'At entries of Wine you put the urge at 4 of 5 on average, against 1.5 '
      'at random check-ins.',
    );
    expect(
      checkInUrgeBasis(u),
      'Over 20 days with both: 40 entries with an urge and 20 check-ins, 10 '
      'of them answered 0 and counted as 1, where an entry’s scale starts. '
      'Check-ins ask about any urge at moments picked at random; entries are '
      'moments you chose.',
    );
  });

  test('the scales alone make no difference: entries at 1 against check-ins '
      'at 0', () {
    final CheckInUrge u = _judge(
      <HabitUse>[for (int k = 0; k < 20; k++) _entry(k, 1)],
      <CheckInAnswer>[for (int k = 0; k < 20; k++) _checkIn(k, 0)],
    ).single;

    expect(u.difference, 0);
    expect(u.refusal, RefusalReason.withinNoise);
  });

  test('a clear difference under one point is too small to show', () {
    final CheckInUrge u = _judge(
      <HabitUse>[
        for (int k = 0; k < 20; k++) ...<HabitUse>[
          _entry(k, 2),
          _entry(k, 3, hour: 21),
        ],
      ],
      <CheckInAnswer>[for (int k = 0; k < 20; k++) _checkIn(k, 2)],
    ).single;

    expect(u.difference, 0.5);
    expect(u.refusal, RefusalReason.tooSmall);
    expect(
      checkInUrgeRefusal(u),
      'Urge at entries against check-ins: too small to matter, under 1 point '
      'of 5',
    );
  });

  test('an entry after midnight pairs with the evening before, and an '
      'archived habit is left out', () {
    final List<CheckInUrge> got = _judge(
      <HabitUse>[
        // 01:00 on the day after each check-in.
        for (int k = 0; k < 20; k++) _entry(k + 1, 4, hour: 1),
        for (int k = 0; k < 20; k++) _entry(k, 4, habit: 'old'),
      ],
      <CheckInAnswer>[for (int k = 0; k < 20; k++) _checkIn(k, 1)],
      skip: const <String>{'old'},
    );

    expect(got.single.habitId, 'wine');
    expect(got.single.days, 20);
  });

  test('days after the last whole day are not read', () {
    final CheckInUrge u = _judge(
      <HabitUse>[for (int k = 0; k < 20; k++) _entry(k, 4)],
      <CheckInAnswer>[for (int k = 0; k < 20; k++) _checkIn(k, 1)],
      through: 9,
    ).single;

    expect(u.days, 10);
    expect(u.refusal, RefusalReason.tooFewDays);
  });

  test('the family can make a finding chance', () {
    final ({List<HabitUse> uses, List<CheckInAnswer> checkIns}) made = _journal(
      Random(5),
      days: 24,
      planted: 2,
    );
    expect(_judge(made.uses, made.checkIns).single.found, isTrue);
    expect(
      _judge(
        made.uses,
        made.checkIns,
        gates: const InsightGates(falseDiscoveryRate: 1e-12),
      ).single.refusal,
      RefusalReason.chance,
    );
  });

  // The urge at an entry is the urge at any moment of that day, so any card
  // is false. The family's rate is q = 0.1; the test alone should reject at
  // its nominal 5%.
  test('on one urge read at entries and at check-ins alike, false cards '
      'stay within the family\'s rate', () {
    final ({double falseCards, double under5, double clear, int tested}) got =
        _null(20261116);
    // ignore: avoid_print
    print('same urge: $got');
    expect(got.tested, greaterThan(2000));
    expect(got.under5, lessThan(0.06));
    expect(got.falseCards, lessThanOrEqualTo(0.1));
  });

  // The lag-1 widening and week-long blocks under-correct a slow drift
  // buried in moment-to-moment noise: the test alone rejects at about 8%
  // here, not 5%. Such a drift moves the mean by far less than
  // [checkInUrgeFloor], which is what keeps a card out.
  test('stretches when entries run higher or lower, none on average, are '
      'not taken for a difference', () {
    final ({double falseCards, double under5, double clear, int tested}) got =
        _null(20261117, entryDrift: 0.5);
    // ignore: avoid_print
    print('entry drift: $got');
    expect(got.tested, greaterThan(2000));
    expect(got.under5, lessThan(0.1));
    expect(got.falseCards, lessThanOrEqualTo(0.1));
  });

  test('a planted 1.5 or 2 points at entries is found most of the time', () {
    double power(double planted) {
      final Random r = Random(11 + (planted * 10).round());
      const int journals = 300;
      int found = 0;
      for (int j = 0; j < journals; j++) {
        final ({List<HabitUse> uses, List<CheckInAnswer> checkIns}) made =
            _journal(r, planted: planted);
        if (_judge(made.uses, made.checkIns).single.found) found++;
      }
      return found / journals;
    }

    final double onePointFive = power(1.5), two = power(2);
    // ignore: avoid_print
    print('power: +1.5 $onePointFive, +2 $two');
    expect(onePointFive, greaterThan(0.8));
    expect(two, greaterThan(0.95));
  });
}
