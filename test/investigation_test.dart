import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/analyst/investigation.dart';
import 'package:tracker/ask/ask_answer.dart';
import 'package:tracker/ask/journal_db.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/letter/letter_checks.dart';

import 'fakes.dart';

// functions/analyst_fixture.json: functions/analyst.test.js runs the same
// cases through the server's checks.
final Map<String, Object?> fixture =
    jsonDecode(File('functions/analyst_fixture.json').readAsStringSync())
        as Map<String, Object?>;

final DateTime today = DateTime(2026, 11, 15);

Vice habit(String id, int created, {String? name}) => Vice(
  id: id,
  name: name ?? id,
  unit: Unit.drink,
  ownerID: ownerID,
  createdAt: Timestamp.fromMillisecondsSinceEpoch(created),
  archived: false,
);

const AskChartSpec table = AskChartSpec(type: AskChartType.table);

AskCard card(String sql, {String title = 'Wine by month'}) => AskCard(
  title: title,
  explain: 'Wine entries in each month.',
  sql: sql,
  chart: table,
);

const String byMonth =
    'SELECT month, count(*) AS entries, sum(amount) AS total FROM entries '
    'WHERE habit_id = 1 GROUP BY month ORDER BY month';

class FakeInvestigator implements Investigator {
  FakeInvestigator(this.replies);

  final List<InvestigationStep Function(Map<String, Object?> request)> replies;
  final List<Map<String, Object?>> requests = <Map<String, Object?>>[];

  @override
  Future<InvestigationStep> step(Map<String, Object?> request) async {
    requests.add(jsonDecode(jsonEncode(request)) as Map<String, Object?>);
    return replies[requests.length - 1](request);
  }
}

/// The fixture's input as this device's rounds, for the shared cases.
(List<InvestigationRound>, List<({int id, Vice vice})>) fixtureRounds() {
  final Map<String, dynamic> input = fixture['input']! as Map<String, dynamic>;
  final List<({int id, Vice vice})> habits = <({int id, Vice vice})>[
    for (final dynamic h in input['habits'] as List<dynamic>)
      (
        id: h['id'] as int,
        vice: Vice(
          id: 'h${h['id']}',
          name: h['name'] as String,
          unit: Unit.drink,
          unitLabel: h['unit'] as String,
          unitSingular: h['unit_one'] as String,
          ownerID: ownerID,
          createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
          archived: false,
        ),
      ),
  ];
  SentResult sent(dynamic s) => (s as Map).containsKey('refused')
      ? SentRefusal(AskRefusal.values.byName(s['refused'] as String))
      : SentRows(
          (s['columns'] as List<dynamic>).cast<String>(),
          <List<String?>>[
            for (final dynamic row in s['rows'] as List<dynamic>)
              (row as List<dynamic>).cast<String?>(),
          ],
          truncated: s['truncated'] as bool,
        );
  final List<InvestigationRound> rounds = <InvestigationRound>[
    for (final dynamic r in input['rounds'] as List<dynamic>)
      InvestigationRound(
        <AskCard>[
          for (final dynamic q in r['queries'] as List<dynamic>)
            parseAskCard(q)!,
        ],
        const <AskRun>[],
        <SentResult>[
          for (final dynamic s in r['results'] as List<dynamic>) sent(s),
        ],
      ),
  ];
  return (rounds, habits);
}

void main() {
  test('the limits and causal terms match the server\'s', () {
    final Map<String, Object?> limits =
        fixture['limits']! as Map<String, Object?>;
    expect(limits, <String, Object?>{
      'steps': AnalystLimits.steps,
      'queries': AnalystLimits.queries,
      'rows': AnalystLimits.rows,
      'resultChars': AnalystLimits.resultChars,
      'columns': AnalystLimits.columns,
      'cell': AnalystLimits.cell,
      'headline': AnalystLimits.headline,
      'body': AnalystLimits.body,
    });
    expect(analystCausalTerms, fixture['causalTerms']);
  });

  test('each shared case gives the server\'s reason', () {
    final (
      List<InvestigationRound> rounds,
      List<({int id, Vice vice})> habits,
    ) = fixtureRounds();
    final LetterContext context = findingContext(rounds, habits);
    for (final Object? c in fixture['cases']! as List<Object?>) {
      final Map<String, Object?> m = c! as Map<String, Object?>;
      expect(
        checkAnalystPassage(m['text']! as String, context),
        m['expect'],
        reason: m['text'] as String?,
      );
    }
  });

  test('counts come from untruncated results, hours from whole cells', () {
    final List<({int id, Vice vice})> habits = fixtureRounds().$2;
    String check(SentRows rows, String text) => checkAnalystPassage(
      text,
      findingContext(<InvestigationRound>[
        InvestigationRound(
          <AskCard>[card(byMonth)],
          const <AskRun>[],
          <SentResult>[rows],
        ),
      ], habits),
    );
    const List<String> columns = <String>['habit', 'hour', 'day'];
    const List<List<String?>> rows = <List<String?>>[
      <String?>['Wine', '20', '2026-10-18'],
      <String?>['Coffee', '8', '2026-10-18'],
      <String?>['Tea', '20', null],
    ];
    const SentRows whole = SentRows(columns, rows, truncated: false);
    expect(check(whole, 'All three habits peaked at 20:00 or 08:00.'), 'ok');
    expect(check(whole, 'Two days.'), 'ok');
    expect(check(whole, 'Four habits.'), 'number_word:four');
    expect(check(whole, 'All 3 habits.'), 'number:3');
    expect(check(whole, 'From 18:00 on.'), 'number:18:00');
    expect(check(whole, 'At 20:30.'), 'number:20:30');
    expect(
      check(
        const SentRows(columns, rows, truncated: true),
        'All three habits.',
      ),
      'number_word:three',
    );
  });

  group('cellText', () {
    test('formats as the check reads it', () {
      expect(cellText(3), '3');
      expect(cellText(2.0), '2');
      expect(cellText(61.538), '61.54');
      expect(cellText(0.5), '0.5');
      expect(cellText(-0.001), '0');
      expect(cellText(double.nan), isNull);
      expect(cellText(null), isNull);
      expect(cellText('x' * 300), hasLength(AnalystLimits.cell));
    });
  });

  group('cutResult', () {
    test('keeps at most 50 rows and says it cut', () {
      final SentResult sent = cutResult(
        AskRan(
          AskRows(
            <String>['n'],
            <List<Object?>>[
              for (int i = 0; i < 80; i++) <Object?>[i],
            ],
          ),
        ),
      );
      expect(sent, isA<SentRows>());
      expect((sent as SentRows).rows, hasLength(AnalystLimits.rows));
      expect(sent.truncated, isTrue);
    });

    test('drops rows until the JSON is within 8000', () {
      final SentRows sent =
          cutResult(
                AskRan(
                  AskRows(
                    <String>['a', 'b'],
                    <List<Object?>>[
                      for (int i = 0; i < 50; i++)
                        <Object?>['y' * 150, 'z' * 150],
                    ],
                  ),
                ),
              )
              as SentRows;
      expect(
        jsonEncode(sent.toJson()).length,
        lessThanOrEqualTo(AnalystLimits.resultChars),
      );
      expect(sent.rows.length, lessThan(50));
      expect(sent.truncated, isTrue);
    });

    test('a refusal sends its code alone', () {
      expect(
        cutResult(const AskRefused(AskRefusal.forbidden)).toJson(),
        <String, Object?>{'refused': 'forbidden'},
      );
    });
  });

  group('parseStep', () {
    Map<String, Object?> query(String sql) => card(sql).toJson();
    const Map<String, Object?> noFinding = <String, Object?>{
      'headline': '',
      'body': '',
      'rests_on': <Object?>[],
    };

    test('reads queries and a finding', () {
      expect(
        parseStep(<String, Object?>{
          'kind': 'queries',
          'queries': <Object?>[query(byMonth)],
          'finding': noFinding,
        }),
        isA<MoreQueries>(),
      );
      final InvestigationStep? f = parseStep(<String, Object?>{
        'kind': 'finding',
        'queries': <Object?>[],
        'finding': <String, Object?>{
          'headline': 'H',
          'body': 'B',
          'rests_on': <Object?>[1],
        },
      });
      expect((f! as Finding).restsOn, <int>[1]);
    });

    test('refuses too many queries, both at once, or an empty finding', () {
      for (final Object? bad in <Object?>[
        <String, Object?>{
          'kind': 'queries',
          'queries': <Object?>[for (int i = 0; i < 4; i++) query(byMonth)],
          'finding': noFinding,
        },
        <String, Object?>{
          'kind': 'queries',
          'queries': <Object?>[],
          'finding': noFinding,
        },
        <String, Object?>{
          'kind': 'finding',
          'queries': <Object?>[query(byMonth)],
          'finding': <String, Object?>{
            'headline': 'H',
            'body': 'B',
            'rests_on': <Object?>[1],
          },
        },
        <String, Object?>{
          'kind': 'finding',
          'queries': <Object?>[],
          'finding': noFinding,
        },
        <String, Object?>{'kind': 'finding'},
      ]) {
        expect(parseStep(bad), isNull, reason: '$bad');
      }
    });
  });

  group('runInvestigation', () {
    late JournalDb db;
    final List<Vice> vices = <Vice>[habit('Wine', 0)];
    final List<({int id, Vice vice})> habits = <({int id, Vice vice})>[
      (id: 1, vice: vices.single),
    ];
    setUp(
      () => db = JournalDb.build(
        vices: vices,
        entries: <ViceActivity>[
          fakeActivity('Wine', 9, DateTime(2026, 10, 1, 20)),
          fakeActivity('Wine', 2, DateTime(2026, 11, 14, 20)),
          fakeActivity('Wine', 3, DateTime(2026, 11, 15, 12)),
        ],
        notes: <DayNote>[],
        today: today,
        figuresOnly: true,
      ),
    );
    tearDown(() => db.close());

    InvestigationStep more(Map<String, Object?> _) =>
        MoreQueries(<AskCard>[card(byMonth), card('SELECT note FROM entries')]);

    test(
      'runs each step\'s queries here and sends their cut results',
      () async {
        final FakeInvestigator fake = FakeInvestigator(
          <InvestigationStep Function(Map<String, Object?>)>[
            more,
            (_) => const Finding(
              'Wine came to 5 drinks in November and 9 in October.',
              'November had 2 entries and October 1.',
              <int>[1],
            ),
          ],
        );
        final InvestigationOutcome outcome = await runInvestigation(
          investigator: fake,
          db: db,
          question: 'What changed in November?',
          habits: habits,
          today: today,
        );
        expect(outcome, isA<InvestigationShown>());
        expect(fake.requests, hasLength(2));
        expect(fake.requests.first.keys.toSet(), <String>{
          'question',
          'today',
          'weekday',
          'habits',
          'rounds',
        });
        expect(fake.requests.first['rounds'], isEmpty);
        final Map<String, Object?> round =
            (fake.requests[1]['rounds']! as List<Object?>).single!
                as Map<String, Object?>;
        expect(round['results'], <Object?>[
          <String, Object?>{
            'columns': <Object?>['month', 'entries', 'total'],
            'rows': <Object?>[
              <Object?>['2026-10', '1', '9'],
              <Object?>['2026-11', '2', '5'],
            ],
            'truncated': false,
          },
          <String, Object?>{'refused': 'forbidden'},
        ]);
      },
    );

    test('withholds a finding with a number it was not shown', () async {
      final InvestigationOutcome outcome = await runInvestigation(
        investigator: FakeInvestigator(
          <InvestigationStep Function(Map<String, Object?>)>[
            more,
            (_) => const Finding('Wine fell by 4.', 'Sums.', <int>[1]),
          ],
        ),
        db: db,
        question: 'q',
        habits: habits,
        today: today,
      );
      expect((outcome as InvestigationWithheld).reason, 'number:4');
    });

    for (final (String why, Finding f) in <(String, Finding)>[
      ('cause:because', const Finding('More because of work.', 'B.', <int>[1])),
      ('rests_on', const Finding('Wine.', 'B.', <int>[2])),
      ('rests_on', const Finding('Wine.', 'B.', <int>[3])),
      ('term:should', const Finding('You should look.', 'B.', <int>[1])),
    ]) {
      test('withholds "${f.headline}" resting on ${f.restsOn}: $why', () async {
        final InvestigationOutcome outcome = await runInvestigation(
          investigator: FakeInvestigator(
            <InvestigationStep Function(Map<String, Object?>)>[more, (_) => f],
          ),
          db: db,
          question: 'q',
          habits: habits,
          today: today,
        );
        expect((outcome as InvestigationWithheld).reason, why);
      });
    }

    test('stops after 6 steps without a finding', () async {
      final FakeInvestigator fake = FakeInvestigator(
        <InvestigationStep Function(Map<String, Object?>)>[
          for (int i = 0; i < 10; i++) more,
        ],
      );
      final InvestigationOutcome outcome = await runInvestigation(
        investigator: fake,
        db: db,
        question: 'q',
        habits: habits,
        today: today,
      );
      expect((outcome as InvestigationFailed).reason, 'no_finding');
      expect(fake.requests, hasLength(AnalystLimits.steps));
      expect(outcome.rounds, hasLength(AnalystLimits.steps - 1));
    });

    test('calls nothing once no longer wanted', () async {
      final FakeInvestigator fake = FakeInvestigator(
        <InvestigationStep Function(Map<String, Object?>)>[more, more],
      );
      int asked = 0;
      final InvestigationOutcome outcome = await runInvestigation(
        investigator: fake,
        db: db,
        question: 'q',
        habits: habits,
        today: today,
        stillWanted: () => asked++ == 0,
      );
      expect((outcome as InvestigationFailed).reason, 'stopped');
      expect(fake.requests, hasLength(1));
    });

    test('refuses a database that is not figures only', () async {
      final JournalDb ask = JournalDb.build(
        vices: vices,
        entries: <ViceActivity>[],
        notes: <DayNote>[],
        today: today,
      );
      addTearDown(ask.close);
      await expectLater(
        runInvestigation(
          investigator: FakeInvestigator(
            <InvestigationStep Function(Map<String, Object?>)>[],
          ),
          db: ask,
          question: 'q',
          habits: habits,
          today: today,
        ),
        throwsArgumentError,
      );
    });
  });
}
