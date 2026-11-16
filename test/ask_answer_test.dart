import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/ask/ask_answer.dart';
import 'package:tracker/ask/ask_journal.dart';
import 'package:tracker/ask/journal_db.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';

import 'fakes.dart';

Map<String, Object?> chart({
  String type = 'number',
  Object? y = const <Object?>['n'],
}) => <String, Object?>{
  'type': type,
  'x': '',
  'y': y,
  'series': '',
  'x_kind': 'none',
};

Map<String, Object?> card({
  String title = 'T',
  String sql = 'SELECT 1 AS n',
  Object? y = const <Object?>['n'],
}) => <String, Object?>{
  'title': title,
  'explain': 'E',
  'sql': sql,
  'chart': chart(y: y),
};

Map<String, Object?> answer({
  String kind = 'answer',
  String reason = 'none',
  List<Object?>? cards,
}) => <String, Object?>{
  'kind': kind,
  'reason': reason,
  'cards': cards ?? <Object?>[card()],
};

Map<String, Object?> without(Map<String, Object?> m, String key) =>
    Map<String, Object?>.of(m)..remove(key);

Map<String, Object?> schema() =>
    jsonDecode(File('functions/ask_query_schema.json').readAsStringSync())
        as Map<String, Object?>;

List<Object?> enumOf(Map<String, Object?> prop) =>
    (prop['enum']! as List<Object?>);

void main() {
  group('parseAskAnswer', () {
    test('accepts each kind', () {
      expect(parseAskAnswer(answer())!.kind, AskKind.answer);
      expect(
        parseAskAnswer(answer(cards: <Object?>[card(), card(), card()]))!.cards,
        hasLength(3),
      );
      expect(
        parseAskAnswer(
          answer(kind: 'needs_insights', cards: <Object?>[]),
        )!.kind,
        AskKind.needsInsights,
      );
      final AskAnswer cannot = parseAskAnswer(
        answer(
          kind: 'cannot_answer',
          reason: 'unknown_habit',
          cards: <Object?>[],
        ),
      )!;
      expect(cannot.kind, AskKind.cannotAnswer);
      expect(cannot.reason, AskReason.unknownHabit);
    });

    test('refuses what does not fit', () {
      final Map<String, Map<String, Object?>> bad =
          <String, Map<String, Object?>>{
            'extra key': <String, Object?>{...answer(), 'more': 1},
            'missing key': without(answer(), 'reason'),
            'unknown kind': answer(kind: 'maybe'),
            'unknown reason': answer(
              kind: 'cannot_answer',
              reason: 'bored',
              cards: <Object?>[],
            ),
            '0 cards for answer': answer(cards: <Object?>[]),
            '4 cards for answer': answer(
              cards: <Object?>[card(), card(), card(), card()],
            ),
            'cards on needs_insights': answer(kind: 'needs_insights'),
            'cards on cannot_answer': answer(
              kind: 'cannot_answer',
              reason: 'unclear',
            ),
            'cannot_answer with none': answer(
              kind: 'cannot_answer',
              cards: <Object?>[],
            ),
            'title over 80': answer(cards: <Object?>[card(title: 'x' * 81)]),
            'sql over 4000': answer(cards: <Object?>[card(sql: 'x' * 4001)]),
            'y over 4': answer(
              cards: <Object?>[
                card(y: <Object?>['a', 'b', 'c', 'd', 'e']),
              ],
            ),
            'non-string y': answer(
              cards: <Object?>[
                card(y: <Object?>[1]),
              ],
            ),
            'unknown chart type': answer(
              cards: <Object?>[
                <String, Object?>{...card(), 'chart': chart(type: 'pie')},
              ],
            ),
          };
      for (final MapEntry<String, Map<String, Object?>> e in bad.entries) {
        expect(parseAskAnswer(e.value), isNull, reason: e.key);
      }
      expect(parseAskAnswer('x'), isNull);
      expect(parseAskAnswer(null), isNull);
    });

    test('toJson round-trips', () {
      final AskAnswer a = parseAskAnswer(
        answer(
          cards: <Object?>[
            card(),
            <String, Object?>{
              ...card(),
              'chart': <String, Object?>{
                'type': 'bar',
                'x': 'hour',
                'y': <Object?>['n'],
                'series': 'habit',
                'x_kind': 'hour',
              },
            },
          ],
        ),
      )!;
      final Map<String, Object?> json = a.toJson();
      final AskAnswer b = parseAskAnswer(json)!;
      expect(b.toJson(), json);
      expect(jsonEncode(json), jsonEncode(parseAskAnswer(json)!.toJson()));
      final AskAnswer c = parseAskAnswer(
        answer(
          kind: 'cannot_answer',
          reason: 'not_supported',
          cards: <Object?>[],
        ),
      )!;
      expect(parseAskAnswer(c.toJson())!.reason, AskReason.notSupported);
    });
  });

  group('schema and server limits', () {
    test('enums and keys match functions/ask_query_schema.json', () {
      final Map<String, Object?> s = schema();
      final Map<String, Object?> props =
          s['properties']! as Map<String, Object?>;
      final Map<String, Object?> defs = s['\$defs']! as Map<String, Object?>;
      final Map<String, Object?> cardDef =
          defs['card']! as Map<String, Object?>;
      final Map<String, Object?> chartDef =
          defs['chart']! as Map<String, Object?>;
      final Map<String, Object?> cardProps =
          cardDef['properties']! as Map<String, Object?>;
      final Map<String, Object?> chartProps =
          chartDef['properties']! as Map<String, Object?>;

      expect(props.keys.toSet(), <String>{'kind', 'reason', 'cards'});
      expect(cardProps.keys.toSet(), <String>{
        'title',
        'explain',
        'sql',
        'chart',
      });
      expect(chartProps.keys.toSet(), <String>{
        'type',
        'x',
        'y',
        'series',
        'x_kind',
      });
      for (final Object? m in <Object?>[s, cardDef, chartDef]) {
        final Map<String, Object?> map = m! as Map<String, Object?>;
        expect(map['additionalProperties'], false);
        expect(
          (map['required']! as List<Object?>).toSet(),
          (map['properties']! as Map<String, Object?>).keys.toSet(),
        );
      }

      expect(enumOf(props['kind']! as Map<String, Object?>).toSet(), <String>{
        'answer',
        'needs_insights',
        'cannot_answer',
      });
      // Every wire name parses to a distinct kind, and there are no others.
      final Set<AskKind> kinds = <AskKind>{};
      for (final Object? k in enumOf(props['kind']! as Map<String, Object?>)) {
        final AskAnswer? a = parseAskAnswer(
          answer(
            kind: k! as String,
            reason: k == 'cannot_answer' ? 'unclear' : 'none',
            cards: k == 'answer' ? <Object?>[card()] : <Object?>[],
          ),
        );
        expect(a, isNotNull, reason: '$k');
        kinds.add(a!.kind);
      }
      expect(kinds, hasLength(AskKind.values.length));

      final List<Object?> reasons = enumOf(
        props['reason']! as Map<String, Object?>,
      );
      final Set<AskReason> seenReasons = <AskReason>{};
      for (final Object? r in reasons) {
        final AskAnswer? a = parseAskAnswer(
          answer(
            kind: r == 'none' ? 'needs_insights' : 'cannot_answer',
            reason: r! as String,
            cards: <Object?>[],
          ),
        );
        expect(a, isNotNull, reason: '$r');
        seenReasons.add(a!.reason);
      }
      expect(seenReasons, hasLength(AskReason.values.length));

      expect(
        enumOf(chartProps['type']! as Map<String, Object?>),
        AskChartType.values.map((AskChartType t) => t.name).toList(),
      );
      expect(
        enumOf(chartProps['x_kind']! as Map<String, Object?>),
        AskXKind.values.map((AskXKind t) => t.name).toList(),
      );
    });

    test('AskLimits equal the server constants', () {
      final String js = File('functions/ask_journal.js').readAsStringSync();
      int constant(String name) =>
          int.parse(RegExp('const $name = (\\d+);').firstMatch(js)![1]!);
      expect(AskLimits.cards, constant('MAX_CARDS'));
      expect(AskLimits.title, constant('MAX_TITLE'));
      expect(AskLimits.explain, constant('MAX_EXPLAIN'));
      expect(AskLimits.sql, constant('MAX_SQL'));
      expect(AskLimits.y, constant('MAX_Y'));
      expect(AskLimits.column, constant('MAX_COLUMN'));
    });
  });

  group('what is sent', () {
    Vice habit(String id, String name, int created, {bool locked = false}) =>
        Vice(
          id: id,
          name: name,
          unit: Unit.drink,
          ownerID: ownerID,
          createdAt: Timestamp.fromMillisecondsSinceEpoch(created),
          archived: false,
          locked: locked,
        );

    final List<Vice> vices = <Vice>[
      habit('vice-abc', 'Wine', 1),
      habit('vice-locked', 'Locked', 2, locked: true),
      habit('vice-def', 'Beer', 3),
    ];
    final List<({int id, Vice vice})> sent = numberedHabits(
      vices,
    ).take(askHabits(vices).length).toList();
    final DateTime today = DateTime(2026, 11, 15, 14);

    AskTurn turn(int i) => AskTurn('question $i', parseAskAnswer(answer())!);

    test('request has exactly the allowed keys and the last 5 turns', () {
      expect(sent, hasLength(2));
      final Map<String, Object?> r = CallableAskJournal.request(
        'How much wine?',
        habits: sent,
        today: today,
        history: <AskTurn>[for (int i = 0; i < 7; i++) turn(i)],
      );
      expect(r.keys.toSet(), <String>{
        'question',
        'today',
        'weekday',
        'habits',
        'history',
      });
      expect(r['today'], '2026-11-15');
      expect(r['weekday'], 'Sunday');
      final List<Object?> habits = r['habits']! as List<Object?>;
      expect(habits, hasLength(2));
      for (final Object? h in habits) {
        expect((h! as Map<String, Object?>).keys.toSet(), <String>{
          'id',
          'name',
          'unit',
          'unit_one',
          'archived',
        });
      }
      final List<Object?> history = r['history']! as List<Object?>;
      expect(history.map((Object? t) => (t! as Map)['question']), <String>[
        'question 2',
        'question 3',
        'question 4',
        'question 5',
        'question 6',
      ]);
      for (final Object? t in history) {
        final Map<String, Object?> m = t! as Map<String, Object?>;
        expect(m.keys.toSet(), <String>{'question', 'answer'});
        expect((m['answer']! as Map).keys.toSet(), <String>{
          'kind',
          'reason',
          'cards',
        });
      }
    });

    test('nothing from entries, notes, ids or the uid is in it', () {
      // The request signature has no parameter for entries or notes: the
      // distinctive values below exist only to be absent.
      final List<Object?> journalOnly = <Object?>[
        fakeActivity(
          'vice-abc',
          9,
          DateTime(2026, 11, 14, 3, 33),
          amount: 7.25,
        ),
        'zebra-note-42',
      ];
      final String encoded = jsonEncode(
        CallableAskJournal.request(
          'How much wine?',
          habits: sent,
          today: today,
          history: <AskTurn>[turn(1)],
        ),
      );
      expect(journalOnly, isNotEmpty);
      for (final String secret in <String>[
        'zebra-note-42',
        '7.25',
        '03:33',
        'vice-abc',
        'vice-def',
        'vice-locked',
        'Locked',
        ownerID,
      ]) {
        expect(encoded, isNot(contains(secret)), reason: secret);
      }
    });

    test('ask sends exactly request() and fails on a bad reply', () async {
      final List<Map<String, Object?>> calls = <Map<String, Object?>>[];
      Object? reply = <String, Object?>{'reason': 'ok', 'answer': answer()};
      final CallableAskJournal service = CallableAskJournal((data) async {
        calls.add(data);
        return reply;
      });
      final List<AskTurn> history = <AskTurn>[turn(1)];
      final AskAnswer got = await service.ask(
        ' How much wine? ',
        habits: sent,
        today: today,
        history: history,
      );
      expect(got.kind, AskKind.answer);
      expect(
        calls.single,
        CallableAskJournal.request(
          'How much wine?',
          habits: sent,
          today: today,
          history: history,
        ),
      );

      Future<void> fails(Object? r, String reason) async {
        reply = r;
        await expectLater(
          service.ask('q', habits: sent, today: today),
          throwsA(
            isA<AskFailed>().having(
              (AskFailed e) => e.reason,
              'reason',
              reason,
            ),
          ),
        );
      }

      await fails(<String, Object?>{
        'reason': 'refusal',
        'answer': null,
      }, 'refusal');
      await fails(<String, Object?>{
        'reason': 'ok',
        'answer': answer(cards: <Object?>[]),
      }, 'invalid');
    });
  });

  test('every function the prompt offers is on the device allow-list', () {
    final String js = File('functions/ask_journal.js').readAsStringSync();
    final String list = RegExp(
      r'const SQL_FUNCTIONS = \[([^\]]*)\]',
    ).firstMatch(js)!.group(1)!;
    final List<String> offered = <String>[
      for (final RegExpMatch m in RegExp(r"'([a-z_0-9]+)'").allMatches(list))
        m.group(1)!,
    ];
    expect(offered, isNotEmpty);
    expect(askFunctions.containsAll(offered), isTrue);
  });
}
