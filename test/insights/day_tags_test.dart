import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/day_tags.dart';
import 'package:tracker/insights/what_follows.dart';

final DateTime _start = DateTime(2026, 3, 2);

typedef _Journal = ({
  List<HabitUse> uses,
  List<DayTags> tags,
  DateTime through,
});

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

const List<String> _others = <String>[
  'work/deadline',
  'feeling/stressed',
  'social/friends',
  'Rest',
];

// Wine on a weekday pattern (Fridays and Saturdays heavier), some days with
// none, two thirds of days given a note and half of those tagged. Bad day is
// tagged with chance [badOnHeavy] on Fridays and Saturdays and [badOther] on
// the rest; the other tags, a nested path among them, at random.
// [planted] adds that many glasses on Bad days.
_Journal _journal(
  Random r, {
  int days = 120,
  double badOnHeavy = 0.3,
  double badOther = 0.3,
  int planted = 0,
}) {
  final List<HabitUse> uses = <HabitUse>[];
  final List<DayTags> tags = <DayTags>[];
  for (int k = 0; k < days; k++) {
    final DateTime day = addDays(_start, k);
    final bool heavy =
        day.weekday == DateTime.friday || day.weekday == DateTime.saturday;
    final List<String> on = <String>[
      if (r.nextDouble() < (heavy ? badOnHeavy : badOther)) 'Bad day',
      for (final String t in _others)
        if (r.nextDouble() < 0.25) t,
    ];
    final bool noted = r.nextDouble() < 2 / 3;
    final bool tagged = noted && r.nextBool();
    if (noted) {
      tags.add((day: day, triggers: tagged ? on : const <String>[]));
    }
    final bool bad = tagged && on.contains('Bad day');
    final int glasses = _poisson(r, heavy ? 3 : 1) + (bad ? planted : 0);
    for (int i = 0; i < glasses; i++) {
      uses.add(
        HabitUse(
          habitId: 'wine',
          at: DateTime(day.year, day.month, day.day, 18 + i % 6),
          amount: 1,
        ),
      );
    }
  }
  return (uses: uses, tags: tags, through: addDays(_start, days - 1));
}

List<HabitDayTags> _judge(_Journal j) => judgeDayTags(
  dayTagAmounts(uses: j.uses, tags: j.tags, through: j.through),
  alongside: const <double>[],
);

DayTagAmount? _of(List<HabitDayTags> judged, String tag) => judged
    .expand((HabitDayTags h) => h.tags)
    .where((DayTagAmount t) => t.tag == tag)
    .firstOrNull;

({double falseCards, double under5, int tested}) _null(
  int seed, {
  required double badOnHeavy,
  required double badOther,
  int journals = 1000,
}) {
  final Random r = Random(seed);
  int withCard = 0, tested = 0, under5 = 0;
  for (int j = 0; j < journals; j++) {
    final List<HabitDayTags> judged = _judge(
      _journal(r, badOnHeavy: badOnHeavy, badOther: badOther),
    );
    for (final DayTagAmount t in judged.expand((h) => h.tags)) {
      if (t.pValue case final double p) {
        tested++;
        if (p < 0.05) under5++;
      }
    }
    if (judged.any((h) => h.tags.any((t) => t.found))) withCard++;
  }
  return (
    falseCards: withCard / journals,
    under5: under5 / tested,
    tested: tested,
  );
}

void main() {
  test('a tag on heavier days is found, among tagged days only, with the '
      'figures the card shows', () {
    final _Journal j = _journal(Random(3), planted: 3);
    final List<HabitDayTags> judged = _judge(j);
    final HabitDayTags wine = judged.single;
    final DayTagAmount bad = _of(judged, 'Bad day')!;

    expect(bad.found, isTrue);
    expect(bad.effect, greaterThan(1.5));
    expect(bad.withMean, greaterThan(bad.withoutMean * 1.5));
    expect(bad.withDays + bad.withoutDays, wine.tagged);
    // Every tagged day in Wine's span, with half the notes untagged.
    final Set<DateTime> taggedDays = <DateTime>{
      for (final DayTags t in j.tags)
        if (t.triggers.isNotEmpty) startOfDay(t.day),
    };
    expect(wine.tagged, lessThanOrEqualTo(taggedDays.length));
    expect(wine.tagged, greaterThan(taggedDays.length - 3));
    expect(wine.days, greaterThan(wine.tagged * 2));
  });

  test('a day with no entry counts as 0, and untagged days are left out', () {
    final List<DayTags> tags = <DayTags>[
      for (int k = 0; k < 40; k++)
        (
          day: addDays(_start, k),
          triggers: k.isEven ? const <String>['Bad day'] : const <String>[],
        ),
    ];
    final List<HabitUse> uses = <HabitUse>[
      for (int k = 0; k < 40; k++)
        if (k % 4 == 1)
          HabitUse(
            habitId: 'wine',
            at: DateTime(_start.year, _start.month, _start.day + k, 20),
            amount: 2,
          ),
    ];
    final List<HabitDayTags> got = dayTagAmounts(
      uses: uses,
      tags: <DayTags>[
        ...tags,
        for (int k = 0; k < 40; k++)
          if (k % 4 == 3) (day: addDays(_start, k), triggers: <String>['Rest']),
      ],
      through: addDays(_start, 45),
    );
    final DayTagAmount bad = got.single.tags.firstWhere(
      (t) => t.tag == 'Bad day',
    );
    // Wine's span runs from day 1 to day 37: Bad day on the even days, none
    // with Wine (0 each); Rest on days 3, 7, ... with none either; Wine's own
    // days (1, 5, ...) carry no tag and are left out.
    expect(bad.withDays, 18);
    expect(bad.withMean, 0);
    expect(bad.withoutDays, 9);
    expect(bad.withoutMean, 0);
    expect(bad.refusal, RefusalReason.steadyAmount);
  });

  test('a tag on too few days, or on nearly every tagged day, is refused '
      'before it is tested', () {
    final _Journal j = _journal(Random(5), days: 30);
    final List<HabitDayTags> judged = _judge(j);
    for (final DayTagAmount t in judged.single.tags) {
      if (t.withDays < 7 || t.withoutDays < 7) {
        expect(t.refusal, RefusalReason.tooFewDays);
        expect(t.pValue, isNull);
      }
    }
  });

  test('the family can make a finding chance', () {
    final List<HabitDayTags> raw = dayTagAmounts(
      uses: _journal(Random(3), planted: 3).uses,
      tags: _journal(Random(3), planted: 3).tags,
      through: addDays(_start, 119),
    );
    expect(
      _of(judgeDayTags(raw, alongside: const <double>[]), 'Bad day')!.found,
      isTrue,
    );
    final List<HabitDayTags> crowded = judgeDayTags(
      raw,
      alongside: const <double>[],
      gates: const InsightGates(falseDiscoveryRate: 1e-12),
    );
    final DayTagAmount bad = _of(crowded, 'Bad day')!;
    expect(bad.refusal, RefusalReason.chance);
  });

  // Every tag is independent of Wine given the weekday, so any card is false.
  // The family's rate is q = 0.1 across journals; each test alone should
  // reject at its nominal 5%.
  test('on tags unrelated to use, false cards stay within the family\'s '
      'rate', () {
    final ({double falseCards, double under5, int tested}) got = _null(
      20261116,
      badOnHeavy: 0.3,
      badOther: 0.3,
    );
    // ignore: avoid_print
    print('independent: $got');
    expect(got.tested, greaterThan(2000));
    expect(got.under5, lessThan(0.06));
    expect(got.falseCards, lessThanOrEqualTo(0.1));
  });

  test('a tag kept mostly for the heavy weekdays is not taken for their '
      'drinking', () {
    final ({double falseCards, double under5, int tested}) got = _null(
      20261117,
      badOnHeavy: 0.7,
      badOther: 0.1,
    );
    // ignore: avoid_print
    print('weekday-shared: $got');
    expect(got.tested, greaterThan(2000));
    expect(got.under5, lessThan(0.06));
    expect(got.falseCards, lessThanOrEqualTo(0.1));
  });

  // Bad day takes about a quarter of the tagged days, mostly Fridays and
  // Saturdays: some 11 days against 29 over four months.
  test('a planted 2 or 3 glasses on Bad days is found most of the time', () {
    double power(int planted) {
      final Random r = Random(11 + planted);
      const int journals = 300;
      int found = 0;
      for (int j = 0; j < journals; j++) {
        final DayTagAmount? bad = _of(
          _judge(_journal(r, badOnHeavy: 0.7, badOther: 0.1, planted: planted)),
          'Bad day',
        );
        if (bad?.found ?? false) found++;
      }
      return found / journals;
    }

    final double two = power(2), three = power(3);
    // ignore: avoid_print
    print('power: +2 $two, +3 $three');
    expect(two, greaterThan(0.45));
    expect(three, greaterThan(0.8));
  });
}
