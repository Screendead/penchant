import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/payoff.dart';
import 'package:tracker/insights/replacement.dart';
import 'package:tracker/insights/stats.dart';

import 'hours_after_synthetic.dart' show syntheticStart;
import 'replacement_synthetic.dart';

List<int> level(int from, int to, int aDay, {int days = 182}) => <int>[
  for (int i = 0; i < days; i++) i >= from && i < to ? aDay : 0,
];

List<Replacement> judge(
  ReplacementDays d, {
  Set<String> skip = const <String>{},
}) => replacement(uses: d.uses, through: d.through, skip: skip);

Replacement made(
  String fallen,
  String riser,
  double? p, {
  ReplacementRefusal? refusal,
}) => Replacement(
  fall: HabitFall(
    habitId: fallen,
    day: DateTime(2026, 6),
    from: DateTime(2026, 3),
    before: 3,
    since: 1,
    sinceDays: 60,
  ),
  riserId: riser,
  before: 1,
  since: 2,
  baselineDays: 91,
  sinceDays: 60,
  effect: p == null ? null : 1,
  interval: p == null ? null : const Interval(0.5, 1.5),
  pValue: p,
  refusal: refusal,
);

void main() {
  final DateTime through = addDays(syntheticStart, 181);

  test('a habit that rises as another falls is found, with its level on '
      'each side', () {
    final Replacement r = judge(
      replacementDays(1, riser: (i, r) => poisson(r, i < 91 ? 1 : 3)),
    ).single;
    expect(r.habitId, 'Cigarettes');
    expect(r.riserId, 'Vape');
    expect(r.refusal, isNull);
    expect(r.began, isFalse);
    expect(r.before, closeTo(1, 0.3));
    expect(r.since, closeTo(3, 0.5));
    expect(r.effect, greaterThan(0));
    expect(r.interval!.low, greaterThan(0));
    expect(r.baselineDays, 91);
    expect(daysBetween(addDays(syntheticStart, 91), r.fall.day).abs(), 
        lessThanOrEqualTo(7));
  });

  test('a habit with no entry before the fall reads as begun, and a '
      'baseline of nothing but zeros gives numbers, not a crash', () {
    final Replacement r = replacement(
      uses: <HabitUse>[
        ...usesOf('Cigarettes', <int>[
          for (int i = 0; i < 182; i++) i < 91 ? 3 : 1,
        ]),
        ...usesOf('Vape', level(91, 182, 2)),
      ],
      through: through,
    ).single;
    expect(r.fall.day, addDays(syntheticStart, 91));
    expect(r.refusal, isNull);
    expect(r.began, isTrue);
    expect(r.before, 0);
    expect(r.since, 2);
    expect(r.effect, closeTo(2, 1e-6));
    expect(r.pValue!.isNaN, isFalse);
    expect(r.interval!.low.isNaN || r.interval!.high.isNaN, isFalse);
  });

  test('a steady habit, and one that rose six weeks after the fall, are '
      'refused', () {
    final Replacement steady = judge(
      replacementDays(2, riser: (_, r) => poisson(r, 2)),
    ).single;
    expect(steady.refusal, ReplacementRefusal.noRise);
    expect(steady.pValue, isNotNull);

    final Replacement later = judge(
      replacementDays(3, riser: (i, r) => poisson(r, i < 133 ? 1 : 4)),
    ).single;
    expect(later.found, isFalse);
    expect(later.refusal, isNot(ReplacementRefusal.tooFewDays));
  });

  test('a habit with under $minRiserDays days of entries since the fall is '
      'not tested', () {
    final Replacement r = judge(
      replacementDays(1, riser: (i, _) => i == 100 || i == 120 ? 5 : 0),
    ).single;
    expect(r.refusal, ReplacementRefusal.tooFewDays);
    expect(r.pValue, isNull);
  });

  test('another habit falling the same fortnight refuses every rise '
      'unfitted', () {
    final List<Replacement> results = replacement(
      uses: <HabitUse>[
        ...usesOf('Cigarettes', <int>[
          for (int i = 0; i < 182; i++) i < 91 ? 3 : 1,
        ]),
        ...usesOf('Coffee', <int>[
          for (int i = 0; i < 182; i++) i < 98 ? 4 : 1,
        ]),
        ...usesOf('Vape', level(91, 182, 2)),
      ],
      through: through,
    );
    expect(results, isNotEmpty);
    for (final Replacement r in results) {
      expect(r.refusal, ReplacementRefusal.otherFall);
      expect(r.pValue, isNull);
    }
  });

  test('nothing is said of an archived habit, fallen or rising', () {
    final ReplacementDays d = replacementDays(
      1,
      riser: (i, r) => poisson(r, i < 91 ? 1 : 3),
    );
    expect(judge(d, skip: <String>{'Vape'}), isEmpty);
    expect(judge(d, skip: <String>{'Cigarettes'}), isEmpty);
  });

  test('a rise that also came over the same weeks a year before is put '
      'down to the time of year', () {
    const int days = 546;
    final Random a = Random(5), b = Random(6);
    final List<HabitUse> uses = <HabitUse>[
      ...usesOf('Cigarettes', <int>[
        for (int i = 0; i < days; i++) poisson(a, i < 455 ? 3 : 1),
      ]),
      ...usesOf('Vape', <int>[
        for (int i = 0; i < days; i++)
          poisson(b, (i >= 91 && i < 182) || i >= 455 ? 3 : 1),
      ]),
    ];
    final Replacement r = replacement(
      uses: uses,
      through: addDays(syntheticStart, days - 1),
    ).single;
    expect(r.refusal, ReplacementRefusal.sameLastYear);

    final Replacement firstYear = replacement(
      uses: <HabitUse>[
        for (final HabitUse use in uses)
          if (!use.at.isBefore(addDays(syntheticStart, 300))) use,
      ],
      through: addDays(syntheticStart, days - 1),
    ).single;
    expect(firstYear.refusal, isNull);
  });

  test('a finding must stand out among every comparison in the report', () {
    final List<Replacement> judged = judgeReplacements(
      <Replacement>[
        made('a', 'b', 0.04),
        made('a', 'c', 0.0001),
        made('a', 'd', null, refusal: ReplacementRefusal.tooFewDays),
        made('a', 'e', 0.5, refusal: ReplacementRefusal.noRise),
      ],
      alongside: <double>[for (int i = 0; i < 20; i++) 0.5 + i / 50],
    );
    expect(judged.map((r) => r.refusal), <ReplacementRefusal?>[
      ReplacementRefusal.chance,
      null,
      ReplacementRefusal.tooFewDays,
      ReplacementRefusal.noRise,
    ]);
  });

  test('one card per fallen habit, the clearest rise first; refusals make '
      'no card', () {
    final List<ReplacementCard> cards = replacementCards(<Replacement>[
      made('a', 'b', 0.01),
      made('a', 'c', 0.001),
      made('z', 'b', 0.0001),
      made('q', 'b', 0.0001, refusal: ReplacementRefusal.notThen),
    ]);
    expect(cards.map((c) => c.habitId), <String>['z', 'a']);
    expect(cards.last.risers.map((r) => r.riserId), <String>['c', 'b']);
  });

  test('the report carries it with no Health data at all, and leaves an '
      'archived habit out', () {
    final ReplacementDays d = replacementDays(
      1,
      riser: (i, r) => poisson(r, i < 91 ? 1 : 3),
    );
    InsightsReport report(Set<String> archived) => computeInsights(
      InsightsInput(
        uses: d.uses,
        outcomes: const <DailyOutcome>[],
        from: syntheticStart,
        through: addDays(d.through, 1),
        archived: archived,
      ),
    );
    final Replacement r = report(const <String>{}).replacements.single;
    expect(r.found, isTrue);
    expect(r.riserId, 'Vape');
    expect(report(<String>{'Vape'}).replacements, isEmpty);
  });
}
