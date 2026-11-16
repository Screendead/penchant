import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/notes/tag_tidy.dart';

import 'fakes.dart';

ViceActivity entry(String id, List<String> triggers, {bool locked = false}) =>
    ViceActivity(
      id: id,
      viceID: 'v1',
      quantity: 1,
      ownerID: ownerID,
      createdAt: Timestamp.fromDate(DateTime(2026, 10, 1)),
      triggers: triggers,
      locked: locked,
    );

DayNote note(String day, List<String> triggers) => DayNote(
  id: dayNoteID(ownerID, day),
  ownerID: ownerID,
  day: day,
  createdAt: Timestamp.fromDate(DateTime(2026, 10, 1)),
  text: 'A day',
  triggers: triggers,
);

void main() {
  test('own words are the labels outside the tree, from entries and day '
      'notes, most used first, locked ones left out', () {
    final List<OwnWords> words = ownWords(
      <ViceActivity>[
        entry('a', <String>['hungover', 'work/meeting']),
        entry('b', <String>['hungover', 'hung over']),
        entry('c', <String>['secret'], locked: true),
      ],
      <DayNote>[
        note('2026-10-02', <String>['hung over', 'bday']),
      ],
    );
    expect(words, <OwnWords>[
      (label: 'hung over', entries: 1, dayNotes: 1),
      (label: 'hungover', entries: 2, dayNotes: 0),
      (label: 'bday', entries: 0, dayNotes: 1),
    ]);
  });

  test('only labels the server accepts are sent', () {
    expect(sendableLabel('hungover'), isTrue);
    expect(sendableLabel(' '), isFalse);
    expect(sendableLabel('a\nb'), isFalse);
    expect(sendableLabel('x' * 61), isFalse);
  });

  group('suggestionsIn', () {
    const List<String> sent = <String>['hungover', 'hung over', 'bday', 'Sam'];

    List<TidySuggestion> check(List<Object?> suggestions) =>
        CallableTagTidier.suggestionsIn(<String, Object?>{
          'suggestions': suggestions,
          'reason': 'ok',
        }, sent);

    test('keeps merges into one of their labels and maps onto a leaf', () {
      expect(
        check(<Object?>[
          <String, Object?>{
            'from': <String>['hungover', 'hung over'],
            'label': 'hungover',
            'path': null,
          },
          <String, Object?>{
            'from': <String>['bday'],
            'path': 'event/birthday',
            'label': null,
          },
        ]),
        const <TidySuggestion>[
          TidySuggestion(
            from: <String>['hungover', 'hung over'],
            label: 'hungover',
          ),
          TidySuggestion(from: <String>['bday'], path: 'event/birthday'),
        ],
      );
    });

    test('drops what the labels and tree do not bear out', () {
      expect(
        check(<Object?>[
          // A label not sent.
          <String, Object?>{
            'from': <String>['hangover'],
            'path': 'event/birthday',
            'label': null,
          },
          // A merge into a new label.
          <String, Object?>{
            'from': <String>['hungover', 'hung over'],
            'label': 'hang',
            'path': null,
          },
          // A merge of one.
          <String, Object?>{
            'from': <String>['Sam'],
            'label': 'Sam',
            'path': null,
          },
          // An area, not a leaf.
          <String, Object?>{
            'from': <String>['bday'],
            'path': 'event',
            'label': null,
          },
          // Both set.
          <String, Object?>{
            'from': <String>['bday'],
            'path': 'event/birthday',
            'label': 'bday',
          },
          'nonsense',
        ]),
        isEmpty,
      );
      expect(
        check(<Object?>[
          <String, Object?>{
            'from': <String>['bday'],
            'path': 'event/birthday',
            'label': null,
          },
          // bday again.
          <String, Object?>{
            'from': <String>['bday', 'Sam'],
            'label': 'Sam',
            'path': null,
          },
        ]),
        hasLength(1),
      );
    });
  });

  test('tidied replaces each mapped label once, keeping order', () {
    final Map<String, String> map = tidyMap(const <TidySuggestion>[
      TidySuggestion(
        from: <String>['hungover', 'hung over'],
        label: 'hungover',
      ),
      TidySuggestion(from: <String>['bday'], path: 'event/birthday'),
    ]);
    expect(map, <String, String>{
      'hung over': 'hungover',
      'bday': 'event/birthday',
    });
    expect(
      tidied(<String>['hung over', 'work/meeting', 'hungover', 'bday'], map),
      <String>['hungover', 'work/meeting', 'event/birthday'],
    );
    expect(touches(<String>['work/meeting'], map), isFalse);
  });
}
