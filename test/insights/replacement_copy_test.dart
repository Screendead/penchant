import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/insights/payoff.dart';
import 'package:tracker/insights/replacement.dart';
import 'package:tracker/insights/replacement_copy.dart';
import 'package:tracker/insights/stats.dart';

HabitFall fall({double since = 1.5}) => HabitFall(
  habitId: 'cigarettes',
  day: DateTime(2026, 3, 3),
  from: DateTime(2025, 12, 2),
  before: 12,
  since: since,
  sinceDays: 60,
);

Replacement rise(
  String riser, {
  double before = 2,
  double since = 5,
  double p = 0.001,
  double fallSince = 1.5,
  bool began = false,
}) => Replacement(
  fall: fall(since: fallSince),
  riserId: riser,
  before: before,
  since: since,
  baselineDays: 91,
  sinceDays: 60,
  effect: since - before,
  interval: Interval((since - before) / 2, (since - before) * 1.5),
  pValue: p,
  began: began,
);

void main() {
  final Replacement vape = rise('vape');
  final Replacement tea = rise(
    'tea',
    before: 0,
    since: 0.4,
    p: 0.01,
    began: true,
  );

  test('a rise reads as what the journal holds, around the same time, and '
      'never as one habit taking the place of another', () {
    for (final String text in <String>[
      replacementSentence(vape, 'Vape', 'en'),
      replacementLine(vape, 'Vape', 'en'),
      replacementSentence(tea, 'Tea', 'en'),
      replacementLine(tea, 'Tea', 'en'),
    ]) {
      expect(text, isNot(contains('replace')));
      expect(text, isNot(contains('instead')));
    }
  });

  test('a habit with no entry before reads as first entries, and a rate '
      'under one a day by the week', () {
    expect(
      replacementSentence(tea, 'Tea', 'en', unit: Unit.drink),
      'Around the same time, your first entries for Tea appear: about 2.8 '
      'drinks a week since.',
    );
    expect(
      replacementLine(tea, 'Tea', 'en', unit: Unit.drink),
      'Also around then: first entries for Tea, about 2.8 drinks a week '
      'since',
    );
    expect(
      replacementRange(tea, 'en'),
      'Range: 1.4 to 4.2 more a week, allowing for the trend it was already '
      'on',
    );
    expect(
      replacementSentence(
        rise('tea', before: 0.2, since: 0.5),
        'Tea',
        'en',
        unit: Unit.drink,
      ),
      'Around the same time, your logged amount of Tea rose from about 1.4 '
      'drinks a week to 3.5.',
    );
    final Replacement again = rise('tea', before: 0, since: 2);
    expect(
      replacementSentence(again, 'Tea', 'en', unit: Unit.drink),
      'Around the same time, your entries for Tea start again after none in '
      'the 13 weeks before: about 2 drinks a day since.',
    );
    expect(
      replacementLine(again, 'Tea', 'en', unit: Unit.drink),
      'Also around then: entries for Tea again, about 2 drinks a day since',
    );
  });
}
