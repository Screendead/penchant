import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/trigger_amounts.dart';

final DateTime _start = DateTime(2026, 6, 1);
final DateTime _through = DateTime(2026, 9, 30);

HabitUse _use(int day, int hour, num amount, List<String> triggers) => HabitUse(
  habitId: 'coffee',
  at: DateTime(_start.year, _start.month, _start.day + day, hour),
  amount: amount,
  triggers: triggers,
);

List<HabitTriggers> _judge(List<HabitUse> uses) =>
    judgeTriggerAmounts(triggerAmounts(uses: uses, through: _through));

TriggerAmount? _of(HabitTriggers h, String trigger) =>
    h.triggers.where((TriggerAmount t) => t.trigger == trigger).firstOrNull;

// Noise: tags drawn independently of the amount, with what real journals
// have that would fool an entry-level test: a varying count of entries a
// day, days heavier than others, mostly one with the odd five, entries with
// two tags, nested paths, a free-text label and half the entries untagged.
List<HabitUse> _noise(Random r, {int days = 90}) {
  const List<String> tags = <String>[
    'work/meeting',
    'work/deadline',
    'feeling/stressed',
    'social/friends',
    'Bored',
  ];
  return <HabitUse>[
    for (int d = 0; d < days; d++)
      for (final (double heavy, int n) in <(double, int)>[
        (r.nextDouble() < 0.2 ? 2.0 : 1.0, r.nextInt(5)),
      ])
        for (int i = 0; i < n; i++)
          _use(
            d,
            8 + i * 3,
            (heavy * (r.nextDouble() < 0.15 ? 5 : 1 + r.nextInt(2))).round(),
            r.nextBool()
                ? const <String>[]
                : <String>{
                    tags[r.nextInt(tags.length)],
                    if (r.nextDouble() < 0.3) tags[r.nextInt(tags.length)],
                  }.toList(),
          ),
  ];
}

void main() {
  test('a trigger whose tagged entries hold more is found, among tagged '
      'entries only', () {
    final Random r = Random(7);
    final List<HabitUse> uses = <HabitUse>[
      for (int d = 0; d < 60; d++) ...<HabitUse>[
        _use(d, 9, 1 + r.nextInt(2), <String>['work/meeting']),
        if (d.isEven) _use(d, 19, 3 + r.nextInt(2), <String>['social/friends']),
        _use(d, 21, 10, const <String>[]),
      ],
    ];

    final HabitTriggers coffee = _judge(uses).single;

    expect(coffee.entries, 150);
    expect(coffee.tagged, 90);
    final TriggerAmount friends = _of(coffee, 'social/friends')!;
    expect(friends.verdict, TriggerVerdict.found);
    expect(friends.relative, greaterThan(0));
    expect(friends.withDays, 30);
    expect(_of(coffee, 'work/meeting')!.verdict, TriggerVerdict.found);
    // Each top-level area covers the same entries as its one path.
    expect(_of(coffee, 'social'), isNull);
    expect(_of(coffee, 'work'), isNull);

    final TriggerCard card = triggerCards(<HabitTriggers>[coffee]).single;
    expect(
      triggerBasis(card.habit, friends),
      'Among the 90 entries you tagged, of 150; Social › With friends is on '
      '30 of them, over 30 days',
    );
  });

  test('a top-level area with two paths under it is its own comparison, and '
      'a free-text label counts as itself', () {
    final List<HabitUse> uses = <HabitUse>[
      for (int d = 0; d < 30; d++) ...<HabitUse>[
        _use(d, 9, 1, <String>[d.isEven ? 'work/meeting' : 'work/deadline']),
        _use(d, 18, 2, const <String>['  Bored  ']),
      ],
    ];

    final HabitTriggers coffee = triggerAmounts(
      uses: uses,
      through: _through,
    ).single;

    expect(_of(coffee, 'work')!.entries, 30);
    expect(_of(coffee, 'Bored')!.entries, 30);
  });

  test('too few days with a trigger leaves it untested', () {
    final List<HabitUse> uses = <HabitUse>[
      for (int d = 0; d < 30; d++)
        _use(d, 9, 1 + d % 3, <String>[d < 5 ? 'Bored' : 'work/meeting']),
    ];

    final TriggerAmount bored = _of(_judge(uses).single, 'Bored')!;

    expect(bored.pValue, isNull);
    expect(bored.verdict, TriggerVerdict.tooFewDays);
  });

  test('the same amount on every tagged entry is refused as steady', () {
    final List<HabitUse> uses = <HabitUse>[
      for (int d = 0; d < 30; d++)
        _use(d, 9, 1, <String>[d.isEven ? 'Bored' : 'work/meeting']),
    ];

    expect(
      _of(_judge(uses).single, 'Bored')!.verdict,
      TriggerVerdict.steadyAmount,
    );
  });

  test('untagged habits and entries after the last day are left out', () {
    final List<HabitUse> uses = <HabitUse>[
      _use(0, 9, 1, const <String>[]),
      HabitUse(
        habitId: 'tea',
        at: _through.add(const Duration(days: 1, hours: 9)),
        amount: 1,
        triggers: const <String>['Bored'],
      ),
    ];

    expect(triggerAmounts(uses: uses, through: _through), isEmpty);
  });

  test('on noise, false findings stay within the false-discovery rate', () {
    final Random r = Random(20261112);
    const int journals = 2000;
    int withFinding = 0, tested = 0, under5 = 0;
    for (int j = 0; j < journals; j++) {
      final List<HabitTriggers> judged = _judge(_noise(r));
      for (final TriggerAmount t in judged.single.triggers) {
        if (t.pValue case final double p) {
          tested++;
          if (p < 0.05) under5++;
        }
      }
      if (triggerCards(judged).isNotEmpty) withFinding++;
    }

    // Several triggers are tested per journal, all null, so any finding is
    // false: Benjamini-Hochberg holds that to q = 0.1 under the global null.
    expect(tested, greaterThan(journals * 5));
    expect(under5 / tested, lessThan(0.055));
    expect(withFinding / journals, lessThan(0.1));
  });
}
