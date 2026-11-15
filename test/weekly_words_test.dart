import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/what_follows.dart';
import 'package:tracker/providers/weekly_review_provider.dart';
import 'package:tracker/insights/weekly_review.dart';
import 'package:tracker/insights/weekly_words.dart';
import 'package:tracker/insights/weekly_words_setting.dart';
import 'package:tracker/weekly_review_page.dart';

import 'fakes.dart';
import 'weekly_review_fixture.dart';

WeeklyReview _review() => buildWeeklyReview(
  week: reviewWeek(reviewToday),
  vices: reviewVices,
  activities: reviewJournal(),
);

// The same week as functions/weekly_words.test.js's, labels as the server
// sets them.
final Map<String, Object?> _sent = <String, Object?>{
  'entries': '20',
  'habits': <Map<String, Object?>>[
    <String, Object?>{
      'habit': 'Habit A',
      'unitOne': 'glass',
      'unitOther': 'glasses',
      'total': '9',
      'entries': '6',
      'days': '5',
      'usual': '7',
      'change': '2',
      'direction': 'more',
    },
    <String, Object?>{
      'habit': 'Habit B',
      'unitOne': 'cup',
      'unitOther': 'cups',
      'total': '14',
      'entries': '14',
      'days': '7',
      'usual': '10.5',
      'change': '3.5',
      'direction': 'more',
    },
    <String, Object?>{
      'habit': 'Habit C',
      'unitOne': 'l',
      'unitOther': 'l',
      'total': '0',
      'entries': '0',
      'days': '0',
      'usual': null,
    },
  ],
  'hours': <Map<String, Object?>>[
    <String, Object?>{'from': '20:00', 'to': '21:00', 'entries': '6'},
  ],
  'tags': <Map<String, Object?>>[
    <String, Object?>{
      'path': 'social/offered',
      'label': 'Who was there › Offered one',
      'entries': '4',
    },
    <String, Object?>{
      'path': 'social',
      'label': 'Who was there',
      'entries': '2',
    },
  ],
  'ownWords': '3',
  'newFindings': <String>[
    'On days with 12 glasses or more logged for Habit A, your mood that night '
        'averages slightly less pleasant than on days with fewer.',
  ],
  'stoppedFindings': <String>['Habit B · heart'],
  'otherFindings': '1',
};

// The cases functions/weekly_words.test.js checks too.
const List<(String, String)> _cases = <(String, String)>[
  (
    'Habit A came to 9 glasses over 5 days. Habit B was 14 cups, usually '
        '10.5. Most were from 20:00 to 21:00.',
    'ok',
  ),
  (
    'You tagged "Who was there › Offered one" 4 times, and 3 tags were in '
        'your own words.',
    'ok',
  ),
  ('Habit A came to 9 glasses, 8 more than usual.', 'number'),
  ('Habit A came to nine glasses.', 'number_word'),
  ('Habit A came to 9 glasses, twice your usual.', 'number_word'),
  ('Habit D came to 9 glasses.', 'placeholder'),
  ('Habit A came to 9 glasses after 8pm.', 'number'),
  ('Habit A came to 9½ glasses.', 'number'),
  ('Habit A came to 9 glasses, 2 more than your usual week.', 'ok'),
  (
    'On days with 12 glasses or more, your mood after Habit A was slightly '
        'less pleasant.',
    'ok',
  ),
  (
    'Habit B no longer stands out for heart, and 1 other finding changed.',
    'ok',
  ),
  ('Habit C came to twelve l.', 'number_word'),
  ('Habits A and B came to 9 and 14.', 'placeholder'),
  ('  ', 'empty'),
];

class _FakeWords implements WeeklyWords {
  _FakeWords(this.answer);

  final Future<String?> Function() answer;
  final List<WeeklyFigures> asked = <WeeklyFigures>[];

  @override
  Future<String?> write(WeeklyFigures figures) {
    asked.add(figures);
    return answer();
  }
}

Future<void> _pumpPage(WidgetTester tester, WeeklyWords? words) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(600, 3200);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: reviewOverrides(words: words),
      child: MaterialApp(
        theme: appTheme(Brightness.light),
        home: const WeeklyReviewPage(),
      ),
    ),
  );
}

void main() {
  group('WeeklyFigures', () {
    test('sends figures under placeholders, with no names or own words', () {
      final WeeklyFigures figures = WeeklyFigures.of(_review())!;
      final String sent = jsonEncode(figures.data);
      for (final String kept in <String>[
        'Coffee',
        'Alcohol',
        'Doomscrolling',
        'with friends',
        'coffee',
        ownerID,
      ]) {
        expect(sent, isNot(contains(kept)));
      }
      expect(figures.names, <String, String>{
        'Habit A': 'Coffee',
        'Habit B': 'Alcohol',
        'Habit C': 'Doomscrolling',
      });
      final List<Object?> habits = figures.data['habits']! as List<Object?>;
      expect(habits.first, <String, Object?>{
        'habit': 'Habit A',
        'unitOne': 'drink',
        'unitOther': 'drinks',
        'total': '11',
        'entries': '11',
        'days': '7',
        'usual': '10.5',
        'change': '0.5',
        'direction': 'more',
      });
      expect((habits[1]! as Map<String, Object?>)['days'], '5');
      expect((habits[2]! as Map<String, Object?>)['total'], '230');
      expect(figures.data['hours'], <Object?>[
        <String, Object?>{'from': '08:00', 'to': '09:00', 'entries': '7'},
        <String, Object?>{'from': '22:00', 'to': '23:00', 'entries': '7'},
        <String, Object?>{'from': '20:00', 'to': '21:00', 'entries': '5'},
      ]);
      expect(figures.data['tags'], <Object?>[
        <String, Object?>{
          'path': 'work/meeting',
          'label': 'Work or study › Meeting',
          'entries': '4',
        },
      ]);
      expect(figures.data['ownWords'], '5');
      expect(figures.data['entries'], '23');
    });

    test('nothing typed leaves: names, own words and places stay home', () {
      final List<Vice> vices = <Vice>[
        Vice(
          id: 'coffee',
          name: 'sleep',
          unit: Unit.drink,
          ownerID: ownerID,
          createdAt: Timestamp.fromDate(DateTime(2026, 1, 1)),
          archived: false,
        ),
        Vice(
          id: 'alcohol',
          name: 'Heart',
          unit: Unit.drink,
          ownerID: ownerID,
          createdAt: Timestamp.fromDate(DateTime(2026, 1, 2)),
          archived: false,
        ),
        Vice(
          id: 'scroll',
          name: 'Grandma Flat',
          unit: Unit.minute,
          ownerID: ownerID,
          createdAt: Timestamp.fromDate(DateTime(2026, 1, 3)),
          archived: false,
        ),
      ];
      final WeeklyReview review = buildWeeklyReview(
        week: reviewWeek(reviewToday),
        vices: vices,
        activities: <ViceActivity>[
          ...reviewJournal(),
          fakeActivity(
            'coffee',
            1,
            DateTime(2026, 11, 4, 12),
            triggers: const <String>['Zanzibar party', 'Grandma Flat'],
          ),
        ],
      );
      final HabitFinding mood = reviewFinding('alcohol', 'moodValence', -0.3);
      // A comparison at a place names it only by id; one on an outcome with
      // no fixed copy, started or stopped, goes as a count.
      final HabitFinding place = reviewFinding('scroll', 'place:1', 0.4);
      final WeeklyFigures figures = WeeklyFigures.of(
        review,
        insights: WeeklyInsightsComputed(
          changes: (
            started: <InsightCard>[
              InsightCard(family: MetricFamily.mood, headline: mood),
              InsightCard(family: MetricFamily.activity, headline: place),
            ],
            stopped: <InsightCard>[
              InsightCard(family: MetricFamily.activity, headline: place),
              InsightCard(
                family: MetricFamily.heart,
                headline: reviewFinding('coffee', 'restingHeartRate', 2),
              ),
            ],
            holding: const <InsightCard>[],
          ),
          collecting: const <HabitRefusal>[],
          floors: const <String, double>{},
        ),
      )!;
      final String sent = jsonEncode(figures.data);
      for (final String typed in <String>[
        'Zanzibar',
        'Grandma',
        'Flat',
        'place',
        'Heart',
        'with friends',
      ]) {
        expect(sent, isNot(contains(typed)));
      }
      expect(figures.data['ownWords'], '7');
      expect(figures.data['newFindings'], <String>[
        findingSentence(mood, 'Habit B', formatLocale, unit: Unit.drink),
      ]);
      expect(figures.data['stoppedFindings'], <String>['Habit A · heart']);
      expect(figures.data['otherFindings'], '2');
      expect(figures.names, <String, String>{
        'Habit A': 'sleep',
        'Habit B': 'Heart',
        'Habit C': 'Grandma Flat',
      });
    });

    test('each habit carries its change from the usual week', () {
      final List<Object?> habits =
          WeeklyFigures.of(_review())!.data['habits']! as List<Object?>;
      final Map<String, Object?> coffee = habits[0]! as Map<String, Object?>;
      final Map<String, Object?> alcohol = habits[1]! as Map<String, Object?>;
      expect((coffee['change'], coffee['direction']), ('0.5', 'more'));
      expect((alcohol['change'], alcohol['direction']), ('5', 'more'));
    });

    test('findings go as the page words them, Health amounts as a count', () {
      final WeeklyFigures figures = WeeklyFigures.of(
        _review(),
        insights: reviewInsights,
      )!;
      // The new sleep finding carries minutes from Health; the stopped one is
      // its heading.
      expect(figures.data['newFindings'], isEmpty);
      expect(figures.data['stoppedFindings'], <String>['Habit A · heart']);
      expect(figures.data['otherFindings'], '1');

      final HabitFinding mood = reviewFinding('alcohol', 'moodValence', -0.3);
      final WeeklyFigures worded = WeeklyFigures.of(
        _review(),
        insights: WeeklyInsightsComputed(
          changes: (
            started: <InsightCard>[
              InsightCard(family: MetricFamily.mood, headline: mood),
            ],
            stopped: const <InsightCard>[],
            holding: const <InsightCard>[],
          ),
          collecting: const <HabitRefusal>[],
          floors: const <String, double>{},
        ),
      )!;
      final String line = findingSentence(
        mood,
        'Habit B',
        formatLocale,
        unit: Unit.drink,
      );
      expect(worded.data['newFindings'], <String>[line]);
      expect(line, isNot(contains('Alcohol')));
      expect(worded.data['otherFindings'], '0');
    });

    test('a week with nothing logged sends nothing', () {
      expect(
        WeeklyFigures.of(
          buildWeeklyReview(
            week: reviewWeek(reviewToday),
            vices: reviewVices,
            activities: const [],
          ),
        ),
        isNull,
      );
    });

    test('numerals are ASCII with a point and no trailing zeros', () {
      expect(numeral(9), '9');
      expect(numeral(9.0), '9');
      expect(numeral(10.5), '10.5');
      expect(numeral(0.1 + 0.2), '0.3');
      expect(numeral(12345), '12345');
    });

    test('names go back by placeholder, in one pass', () {
      expect(
        restoreNames('Habit A then Habit B, not Habit Z.', <String, String>{
          'Habit A': 'Habit B',
          'Habit B': 'Wine',
        }),
        'Habit B then Wine, not Habit Z.',
      );
    });
  });

  test('checkParagraph lets through only sent numbers and placeholders', () {
    for (final (String text, String reason) in _cases) {
      expect(checkParagraph(text, _sent), reason, reason: text);
    }
  });

  group('CallableWeeklyWords', () {
    test('sends the figures, checks the reply and puts names back', () async {
      final List<Map<String, Object?>> calls = <Map<String, Object?>>[];
      final CallableWeeklyWords words = CallableWeeklyWords((data) async {
        calls.add(data);
        return <String, Object?>{
          'reason': 'ok',
          'text': 'Habit B came to 10 drinks over 5 days.',
        };
      });
      final WeeklyFigures figures = WeeklyFigures.of(_review())!;
      expect(
        await words.write(figures),
        'Alcohol came to 10 drinks over 5 days.',
      );
      expect(calls, <Object?>[figures.data]);
      expect(
        await words.write(WeeklyFigures.of(_review())!),
        'Alcohol came to 10 drinks over 5 days.',
      );
      expect(calls, hasLength(1), reason: 'the week is kept in memory');
      expect(
        await words.write(
          WeeklyFigures(figures.data, <String, String>{'Habit B': 'Wine'}),
        ),
        'Wine came to 10 drinks over 5 days.',
      );
      expect(calls, hasLength(1));
    });

    test('a call that throws is tried again on the next open', () async {
      int calls = 0;
      final CallableWeeklyWords words = CallableWeeklyWords((_) async {
        if (++calls == 1) throw Exception('offline');
        return <String, Object?>{'reason': 'ok', 'text': 'Habit A: 11.'};
      });
      final WeeklyFigures figures = WeeklyFigures.of(_review())!;
      expect(await words.write(figures), isNull);
      expect(await words.write(figures), 'Coffee: 11.');
      expect(calls, 2);
    });

    test('drops a reply that fails the check, a refusal or an error', () async {
      final WeeklyFigures figures = WeeklyFigures.of(_review())!;
      for (final FutureOr<Object?> Function() answer
          in <FutureOr<Object?> Function()>[
            () => <String, Object?>{
              'reason': 'ok',
              'text': 'Habit B: 99 drinks.',
            },
            () => <String, Object?>{
              'reason': 'ok',
              'text': 'Habit Q: 10 drinks.',
            },
            () => <String, Object?>{'reason': 'ok', 'text': 'Habit B: ten.'},
            () => <String, Object?>{'reason': 'number', 'text': null},
            () => 'text',
            () => throw Exception('offline'),
          ]) {
        final CallableWeeklyWords words = CallableWeeklyWords(
          (_) async => answer(),
        );
        expect(await words.write(figures), isNull);
      }
    });
  });

  group('the review page', () {
    testWidgets('shows the paragraph at the top, labelled, over the lists', (
      WidgetTester tester,
    ) async {
      final Completer<String?> reply = Completer<String?>();
      final _FakeWords words = _FakeWords(() => reply.future);
      await _pumpPage(tester, words);
      await tester.pump();
      expect(find.text(WeeklyReviewPage.writing), findsOneWidget);
      reply.complete('Coffee came to 11 drinks.');
      await tester.pumpAndSettle();
      expect(find.text(WeeklyReviewPage.writing), findsNothing);
      expect(find.text('Coffee came to 11 drinks.'), findsOneWidget);
      expect(find.text(WeeklyReviewPage.writtenBy), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Coffee came to 11 drinks.')).dy,
        lessThan(
          tester.getTopLeft(find.text(WeeklyReviewPage.totalsHeading)).dy,
        ),
      );
      expect(find.text('11 drinks'), findsOneWidget);
      expect(words.asked, hasLength(1));
    });

    testWidgets('a failure shows the lists alone', (WidgetTester tester) async {
      await _pumpPage(tester, _FakeWords(() async => null));
      await tester.pumpAndSettle();
      expect(find.text(WeeklyReviewPage.writing), findsNothing);
      expect(find.text(WeeklyReviewPage.writtenBy), findsNothing);
      expect(find.text('11 drinks'), findsOneWidget);
    });

    testWidgets('switched off, nothing is asked or shown', (
      WidgetTester tester,
    ) async {
      await _pumpPage(tester, null);
      await tester.pumpAndSettle();
      expect(find.text(WeeklyReviewPage.writing), findsNothing);
      expect(find.text(WeeklyReviewPage.writtenBy), findsNothing);
    });
  });

  group('WeeklyWordsSetting', () {
    Widget app() => ProviderScope(
      child: MaterialApp(
        theme: appTheme(Brightness.light),
        home: const Scaffold(body: WeeklyWordsSetting()),
      ),
    );

    Future<bool?> saved() async =>
        (await SharedPreferences.getInstance()).getBool(WeeklyWordsEnabled.key);

    testWidgets('turning on says what is sent first; Not now leaves it off', (
      WidgetTester tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text(WeeklyWordsSetting.disclosure), findsOneWidget);
      for (final String said in <String>[
        'Habit A',
        'names',
        'own words',
        'Health',
        'Anthropic does not use it for training',
      ]) {
        expect(WeeklyWordsSetting.disclosure, contains(said));
      }
      await tester.tap(find.text(WeeklyWordsSetting.notNow));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(await saved(), isNull);

      await tester.tap(find.text(WeeklyWordsSetting.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(WeeklyWordsSetting.turnOn));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(await saved(), isTrue);
    });

    testWidgets('turning off needs no asking', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        WeeklyWordsEnabled.key: true,
      });
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text(WeeklyWordsSetting.disclosure), findsNothing);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(await saved(), isFalse);
    });
  });
}
