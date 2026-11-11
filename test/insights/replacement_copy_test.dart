import 'package:flutter/material.dart' hide Interval;
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/insights/payoff.dart';
import 'package:tracker/insights/payoff_copy.dart';
import 'package:tracker/insights/replacement.dart';
import 'package:tracker/insights/replacement_copy.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights_page.dart';
import 'package:tracker/widgets/replacement_card.dart';

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
);

String name(String id) => switch (id) {
  'cigarettes' => 'Cigarettes',
  'vape' => 'Vape',
  _ => 'Tea',
};

Unit unit(String id) => switch (id) {
  'vape' => Unit.puff,
  'tea' => Unit.drink,
  _ => Unit.item,
};

void main() {
  final Replacement vape = rise('vape');
  final Replacement tea = rise('tea', before: 0, since: 0.4, p: 0.01);

  test('a rise reads as what the journal holds, around the same time, and '
      'never as one habit taking the place of another', () {
    expect(
      replacementSentence(vape, 'Vape', 'en', unit: Unit.puff),
      'Around the same time, your logged amount of Vape rose from about 2 '
      'puffs a day to 5, allowing for the trend it was already on.',
    );
    expect(replacementRange(vape, 'en'), 'Range: 1.5 to 4.5 more a day');
    expect(replacementBasis(vape), 'From 91 days before and 60 since');
    expect(
      replacementLine(vape, 'Vape', 'en', unit: Unit.puff),
      'Also around then: logged amount of Vape up from about 2 puffs a day '
      'to 5',
    );
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
    expect(replacementRange(tea, 'en'), 'Range: 1.4 to 4.2 more a week');
    expect(
      replacementSentence(
        rise('tea', before: 0.2, since: 0.5),
        'Tea',
        'en',
        unit: Unit.drink,
      ),
      'Around the same time, your logged amount of Tea rose from about 1.4 '
      'drinks a week to 3.5, allowing for the trend it was already on.',
    );
  });

  test('Copy as text carries the card under How cutting down is going', () {
    final List<ReplacementCard> cards = replacementCards(<Replacement>[
      tea,
      vape,
    ]);
    final String text = insightsText(
      cards: const [],
      refused: const [],
      firstDay: null,
      nameOf: name,
      locale: 'en',
      cuttingDown: <List<String>>[
        for (final ReplacementCard card in cards)
          replacementText(card, name, unit, 'en'),
      ],
    );
    expect(
      text,
      contains(
        '\n${InsightsPage.cuttingDownHeading}\n\nCigarettes\n'
        'Your logged amount of Cigarettes fell from about 12 items a day to '
        '1.5 around March 3, 2026.\n'
        'Around the same time, your logged amount of Vape rose from about 2 '
        'puffs a day to 5, allowing for the trend it was already on.\n'
        'Range: 1.5 to 4.5 more a day\n'
        'From 91 days before and 60 since\n'
        'Also around then: first entries for Tea, about 2.8 drinks a week '
        'since\n'
        '$replacementCaveat\n',
      ),
    );
  });

  testWidgets('the card shows the fall, the clearest rise with its range '
      'and basis, the rest as lines, then what it cannot say', (
    WidgetTester tester,
  ) async {
    final Replacement stoppedVape = rise('vape', fallSince: 0);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReplacementCardView(
              card: replacementCards(<Replacement>[
                rise('tea', before: 0, since: 0.4, p: 0.01, fallSince: 0),
                stoppedVape,
              ]).single,
              nameOf: name,
              unitOf: unit,
              mark: const HabitMark(0),
              locale: 'en',
              top: 0,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Cigarettes'), findsOneWidget);
    expect(
      find.text(
        'No entries for Cigarettes since March 3, 2026, from about 12 items '
        'a day before.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        fallSentence(stoppedVape.fall, 'Cigarettes', 'en', unit: Unit.item),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Around the same time, your logged amount of Vape rose from about 2 '
        'puffs a day to 5, allowing for the trend it was already on.',
      ),
      findsOneWidget,
    );
    expect(find.text('Range: 1.5 to 4.5 more a day'), findsOneWidget);
    expect(find.text('From 91 days before and 60 since'), findsOneWidget);
    expect(
      find.text(
        'Also around then: first entries for Tea, about 2.8 drinks a week '
        'since',
      ),
      findsOneWidget,
    );
    expect(find.text(replacementCaveat), findsOneWidget);
  });
}
