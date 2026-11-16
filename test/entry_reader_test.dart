import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/activity_content.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/say_it/entry_reader.dart';

import 'fakes.dart';

// Runs functions/entry_reader_fixture.json through the device's checks, the
// same file the function's tests run, so the two cannot drift.

DateTime _local(String date, [String time = '00:00']) {
  final List<int> d = date.split('-').map(int.parse).toList();
  final List<int> t = time.split(':').map(int.parse).toList();
  return DateTime(d[0], d[1], d[2], t[0], t[1]);
}

void main() {
  final Map<String, Object?> fixture =
      jsonDecode(File('functions/entry_reader_fixture.json').readAsStringSync())
          as Map<String, Object?>;

  group('the shared fixture', () {
    for (final Object? c in fixture['cases']! as List<Object?>) {
      final Map<String, Object?> kase = c! as Map<String, Object?>;
      test(kase['name']! as String, () {
        final Map<String, Object?> input =
            kase['input']! as Map<String, Object?>;
        final List<({int id, Vice vice})> habits = <({int id, Vice vice})>[
          for (final Object? h in input['habits']! as List<Object?>)
            (
              id: (h! as Map<String, Object?>)['id']! as int,
              vice: fakeVice(
                'v${(h as Map<String, Object?>)['id']}',
                name: h['name']! as String,
              ),
            ),
        ];
        final String now = input['now']! as String;
        final List<String> nowParts = now.split('T');
        final List<DateTime> days = <DateTime>[
          for (final Object? d in input['dates']! as List<Object?>)
            _local((d! as Map<String, Object?>)['date']! as String),
        ];
        final Map<String, Object?> reply =
            kase['reply']! as Map<String, Object?>;
        final ReadEntries got = checkEntries(
          reply,
          mode: input['mode'] == 'now' ? EntryMode.now : EntryMode.days,
          text: input['text']! as String,
          now: _local(nowParts[0], nowParts[1]),
          days: days,
          habits: habits,
        );
        final List<Object?> sent = reply['entries']! as List<Object?>;
        final List<Object?> kept = kase['kept']! as List<Object?>;
        final List<Object?> keptTags = kase['keptTags']! as List<Object?>;
        expect(got.entries.length, kept.length);
        expect(got.dropped, kase['dropped']);
        for (int i = 0; i < kept.length; i++) {
          final Map<String, Object?> want =
              sent[kept[i]! as int]! as Map<String, Object?>;
          final DraftEntry entry = got.entries[i];
          expect(entry.vice.id, 'v${want['habit']}');
          expect(entry.amount, want['amount']);
          expect(
            entry.at,
            _local(want['date']! as String, want['time']! as String),
          );
          expect(entry.note ?? '', want['note']);
          expect(entry.triggers, keptTags[i]);
        }
      });
    }
  });

  test('a reply that is not a list keeps nothing and never throws', () {
    for (final Object? answer in <Object?>[
      null,
      'x',
      <String, Object?>{'entries': 'x'},
      <String, Object?>{'entries': null, 'dropped': 2},
    ]) {
      final ReadEntries got = checkEntries(
        answer,
        mode: EntryMode.now,
        text: 'a',
        now: DateTime(2026, 11, 16, 12),
        days: <DateTime>[DateTime(2026, 11, 16)],
        habits: <({int id, Vice vice})>[(id: 1, vice: fakeVice('v1'))],
      );
      expect(got.entries, isEmpty);
    }
  });

  test('the request holds only the words, times, dates and habit words', () {
    final List<({int id, Vice vice})> habits = entryHabits(<Vice>[
      fakeVice('secret-id', name: 'Beer'),
      fakeVice('gone', name: 'Old', archived: true),
    ]);
    expect(habits.map((h) => h.vice.id), <String>['secret-id']);
    final DateTime now = DateTime(2026, 11, 16, 21, 30);
    final Map<String, Object?> sent = entryRequest(
      EntryMode.now,
      'two pints',
      now: now,
      days: entryDays(EntryMode.now, now),
      habits: habits,
    );
    expect(sent.keys, <String>['mode', 'text', 'now', 'dates', 'habits']);
    expect(sent['now'], '2026-11-16T21:30');
    expect(sent['dates'], <Object?>[
      <String, Object?>{'date': '2026-11-15', 'weekday': 'Sunday'},
      <String, Object?>{'date': '2026-11-16', 'weekday': 'Monday'},
    ]);
    expect(jsonEncode(sent), isNot(contains('secret-id')));
  });

  test('catch-up days drop the future and repeats, oldest first', () {
    final DateTime now = DateTime(2026, 11, 16, 9);
    expect(
      entryDays(
        EntryMode.days,
        now,
        days: <DateTime>[
          DateTime(2026, 11, 15, 8),
          DateTime(2026, 11, 13),
          DateTime(2026, 11, 15),
          DateTime(2026, 11, 17),
        ],
      ),
      <DateTime>[DateTime(2026, 11, 13), DateTime(2026, 11, 15)],
    );
  });

  test('the new sources are the longest stored names the bound allows for', () {
    expect(longestLoggedVia, LoggedVia.caughtUp);
    expect(readLoggedVia('spoken'), LoggedVia.spoken);
    expect(readLoggedVia('caughtUp'), LoggedVia.caughtUp);
  });
}
