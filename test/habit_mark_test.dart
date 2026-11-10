import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';

import 'fakes.dart';

Vice _vice(String id, int day, {bool archived = false}) => Vice(
  id: id,
  name: id,
  unit: Unit.item,
  ownerID: ownerID,
  createdAt: Timestamp.fromDate(DateTime.utc(2026, 1, day)),
  archived: archived,
);

void main() {
  test('the oldest habit is first, whatever order the list is in', () {
    final Map<String, HabitMark> marks = habitMarks([
      _vice('walk', 3),
      _vice('coffee', 1),
      _vice('tea', 2),
    ]);

    expect(marks['coffee'], const HabitMark(0));
    expect(marks['tea'], const HabitMark(1));
    expect(marks['walk'], const HabitMark(2));
  });

  test('archived habits keep their place, so later colours do not move', () {
    final List<Vice> vices = [
      _vice('coffee', 1),
      _vice('tea', 2, archived: true),
      _vice('walk', 3),
    ];

    expect(habitMarks(vices)['walk']!.slot, 2);
  });

  test('the sixth habit takes the first colour again, as a ring', () {
    final Map<String, HabitMark> marks = habitMarks([
      for (int i = 1; i <= 5; i++) _vice('h$i', i),
      _vice('sixth', 6, archived: true),
    ]);

    expect(marks['sixth']!.slot, 0);
    expect(marks['sixth']!.style, HabitMarkStyle.ring);
    expect(marks['h1']!.style, HabitMarkStyle.filled);
  });

  test('slots cycle through five colours and styles through three', () {
    expect(
      <int>[for (int i = 0; i < 12; i++) HabitMark(i).slot],
      <int>[
        0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, //
      ],
    );
    expect(
      <HabitMarkStyle>[
        for (final int i in <int>[0, 4, 5, 9, 10, 14, 15, 20])
          HabitMark(i).style,
      ],
      <HabitMarkStyle>[
        HabitMarkStyle.filled,
        HabitMarkStyle.filled,
        HabitMarkStyle.ring,
        HabitMarkStyle.ring,
        HabitMarkStyle.dotted,
        HabitMarkStyle.dotted,
        HabitMarkStyle.filled,
        HabitMarkStyle.ring,
      ],
    );
  });

  test('equal creation times are ordered by id, the same every time', () {
    final List<Vice> legacy = [fakeVice('b'), fakeVice('c'), fakeVice('a')];

    final Map<String, HabitMark> marks = habitMarks(legacy);
    expect(marks, habitMarks(legacy.reversed));
    expect(marks['a'], const HabitMark(0));
    expect(marks['b'], const HabitMark(1));
    expect(marks['c'], const HabitMark(2));
  });

  test('no vices, no marks', () {
    expect(habitMarks(<Vice>[]), isEmpty);
  });

  test('a mark resolves to the palette colour and ink of its slot', () {
    const HabitMark seventh = HabitMark(6);
    for (final (DialColors colors, DialPalette palette) in [
      (DialColors.light, DialPalette.light),
      (DialColors.dark, DialPalette.dark),
    ]) {
      expect(colors.habit(seventh), palette.data[1]);
      expect(colors.habitInk(seventh), palette.dataInk[1]);
    }
  });
}
