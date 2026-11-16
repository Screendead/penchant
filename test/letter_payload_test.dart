import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/letter/letter_payload.dart';
import 'package:tracker/notes/follow_up.dart';

import 'fakes.dart';

final DateTime today = DateTime(2026, 11, 16);

ViceActivity entry(
  String viceID,
  DateTime at, {
  int quantity = 1,
  double? amount,
  String? note,
  int? urge,
  List<String> triggers = const <String>[],
  FollowUp? followUp,
  bool locked = false,
}) => ViceActivity(
  id: 'doc-${at.millisecondsSinceEpoch}',
  viceID: viceID,
  quantity: quantity,
  amount: amount,
  ownerID: ownerID,
  createdAt: Timestamp.fromDate(at),
  triggers: triggers,
  urge: urge,
  note: note,
  zone: 'Europe/London',
  followUp: followUp,
  locked: locked,
);

DayNote dayNote(DateTime day, String text, {bool locked = false}) => DayNote(
  id: dayNoteID(ownerID, dayKey(day)),
  ownerID: ownerID,
  day: dayKey(day),
  createdAt: Timestamp.fromDate(day),
  text: text,
  triggers: const <String>['work'],
  locked: locked,
);

final List<Vice> vices = <Vice>[
  fakeVice('v1', name: 'Wine', unit: Unit.drink),
  fakeVice('v2', name: 'Cigarettes'),
  Vice(
    id: 'v3',
    name: 'Locked habit',
    unit: Unit.item,
    ownerID: ownerID,
    createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
    archived: false,
    locked: true,
  ),
];

LetterPayload build(
  List<ViceActivity> activities, {
  List<DayNote> notes = const <DayNote>[],
  int months = 3,
  int budget = letterBudget,
}) => buildLetterPayload(
  vices: vices,
  activities: activities,
  dayNotes: notes,
  today: today,
  months: months,
  budget: budget,
)!;

Set<String> keys(Object? map) => (map! as Map<String, Object?>).keys.toSet();

void main() {
  test('sends exactly the agreed keys', () {
    final LetterPayload p = build(
      <ViceActivity>[
        entry(
          'v1',
          DateTime(2026, 10, 2, 21, 30),
          amount: 2.5,
          quantity: 3,
          note: 'after the meeting',
          urge: 4,
          triggers: const <String>['work/meeting'],
          followUp: const FollowUp(
            question: 'What made it hard?',
            quote: 'meeting',
            answer: 'it ran late',
          ),
        ),
        entry('v2', DateTime(2026, 11, 1, 8, 5)),
      ],
      notes: <DayNote>[dayNote(DateTime(2026, 9, 14), 'A quiet Sunday.')],
    );
    final Map<String, Object?> json = p.json;
    expect(keys(json), <String>{'period', 'entries', 'dayNotes', 'figures'});
    expect(keys(json['period']), <String>{'from', 'to', 'months', 'shortened'});
    final List<Object?> entries = json['entries']! as List<Object?>;
    expect(keys(entries.first), <String>{
      'date',
      'time',
      'habit',
      'amount',
      'unit',
      'tags',
      'urge',
      'note',
      'followUp',
    });
    expect(keys((entries.first! as Map<String, Object?>)['followUp']), <String>{
      'question',
      'answer',
    });
    expect(keys(entries.last), <String>{
      'date',
      'time',
      'habit',
      'amount',
      'unit',
      'tags',
    });
    expect(entries.first, containsPair('habit', 'Wine'));
    expect(entries.first, containsPair('amount', '2.5'));
    expect(entries.first, containsPair('unit', 'drinks'));
    expect(entries.first, containsPair('time', '21:30'));
    expect(entries.first, containsPair('date', '2026-10-02'));
    expect(entries.first, containsPair('urge', 'a lot'));
    expect(
      entries.first,
      containsPair('tags', <String>['Work or study › Meeting']),
    );
    final List<Object?> dayNotes = json['dayNotes']! as List<Object?>;
    expect(keys(dayNotes.single), <String>{'date', 'text', 'tags'});
    final Map<String, Object?> figures =
        json['figures']! as Map<String, Object?>;
    expect(keys(figures), <String>{'habits', 'months', 'notes', 'tags'});
    expect((figures['habits']! as List<Object?>).first, <String, Object?>{
      'habit': 'Wine',
      'unit': 'drinks',
      'total': '2.5',
      'entries': '1',
      'days': '1',
    });
    expect((figures['months']! as List<Object?>).first, <String, Object?>{
      'month': 'October 2026',
      'habits': <Object?>[
        <String, Object?>{
          'habit': 'Wine',
          'total': '2.5',
          'entries': '1',
          'days': '1',
        },
      ],
    });
    expect(figures['notes'], <String, Object?>{
      'entryNotes': '1',
      'dayNotes': '1',
      'followUps': '1',
    });
    expect(keys((figures['tags']! as List<Object?>).first), <String>{
      'tag',
      'count',
    });
  });

  test('never sends ids, the uid, the zone or Health and places', () {
    final String sent = jsonEncode(
      build(
        <ViceActivity>[entry('v1', DateTime(2026, 10, 2, 21), note: 'n')],
        notes: <DayNote>[dayNote(DateTime(2026, 10, 3), 'x')],
      ).json,
    );
    for (final String never in <String>[
      ownerID,
      'doc-',
      'v1',
      'Europe/London',
      'health',
      'place',
      'calendar',
      'sleep',
      'viceID',
      'ownerID',
      'createdAt',
    ]) {
      expect(sent.toLowerCase(), isNot(contains(never.toLowerCase())));
    }
  });

  test('leaves out everything outside the period', () {
    final LetterPayload p = build(
      <ViceActivity>[
        entry('v1', DateTime(2026, 8, 16, 23, 59), note: 'too early'),
        entry('v1', DateTime(2026, 8, 17), note: 'first day'),
        entry('v1', DateTime(2026, 11, 17, 0, 1), note: 'tomorrow'),
      ],
      notes: <DayNote>[
        dayNote(DateTime(2026, 8, 16), 'before'),
        dayNote(DateTime(2026, 11, 16), 'today'),
      ],
    );
    expect(p.json['period'], containsPair('from', '2026-08-17'));
    expect(p.json['period'], containsPair('to', '2026-11-16'));
    final String sent = jsonEncode(p.json);
    expect(sent, contains('first day'));
    expect(sent, contains('today'));
    expect(sent, isNot(contains('too early')));
    expect(sent, isNot(contains('tomorrow')));
    expect(sent, isNot(contains('before')));
    expect(p.notes.map((LetterNote n) => n.text), <String>[
      'first day',
      'today',
    ]);
  });

  test('counts and leaves out locked entries, notes and habits', () {
    final LetterPayload p = build(
      <ViceActivity>[
        entry('v1', DateTime(2026, 10, 1), note: 'sent'),
        entry('v1', DateTime(2026, 10, 2), note: 'sealed', locked: true),
        entry('v3', DateTime(2026, 10, 3), note: 'locked habit'),
        entry('gone', DateTime(2026, 10, 4), note: 'deleted habit'),
      ],
      notes: <DayNote>[
        dayNote(DateTime(2026, 10, 5), 'locked note', locked: true),
      ],
    );
    expect(p.counts.entries, 1);
    expect(p.counts.dayNotes, 0);
    expect(p.counts.leftOut, 4);
    final String sent = jsonEncode(p.json);
    expect(sent, isNot(contains('Locked habit')));
    expect(sent, isNot(contains('sealed')));
    expect(sent, isNot(contains('deleted habit')));
  });

  test('works out the figures on the device', () {
    final LetterPayload p = build(<ViceActivity>[
      entry('v1', DateTime(2026, 10, 1, 20), quantity: 2),
      entry('v1', DateTime(2026, 10, 1, 22), quantity: 1),
      entry('v1', DateTime(2026, 11, 2, 21), amount: 0.25, quantity: 1),
    ]);
    final List<Object?> habits =
        (p.json['figures']! as Map<String, Object?>)['habits']!
            as List<Object?>;
    expect(habits.single, containsPair('total', '3.25'));
    expect(habits.single, containsPair('entries', '3'));
    expect(habits.single, containsPair('days', '2'));
  });

  test('shortens a period over the budget and says so', () {
    final List<ViceActivity> many = <ViceActivity>[
      for (int d = 0; d < 80; d++)
        entry(
          'v1',
          DateTime(2026, 8, 20).add(Duration(days: d, hours: 12)),
          note: 'x' * 400,
        ),
    ];
    final LetterPayload whole = build(many);
    expect(whole.shortened, isFalse);
    final LetterPayload p = build(many, budget: whole.chars ~/ 2);
    expect(p.shortened, isTrue);
    expect(p.json['period'], containsPair('shortened', true));
    expect(p.chars, lessThanOrEqualTo(whole.chars ~/ 2));
    expect(p.from.isAfter(DateTime(2026, 8, 17)), isTrue);
    expect(p.counts.entries, lessThan(80));
  });

  test('formats figures as plain ASCII', () {
    expect(letterFigure(3), '3');
    expect(letterFigure(2.5), '2.5');
    expect(letterFigure(1234.567), '1234.57');
    expect(letterFigure(0.1 + 0.2), '0.3');
  });
}
