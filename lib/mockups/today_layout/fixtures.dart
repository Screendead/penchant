import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';

// Mock-up only. The icon, the default quantity, triggers and notes are not in
// the data model yet; they rest on r2-data-model.

class MockVice {
  MockVice({
    required String id,
    required String name,
    required Unit unit,
    required this.icon,
    required this.defaultQuantity,
    required this.previousSixDays,
  }) : vice = Vice(
         id: id,
         name: name,
         unit: unit,
         ownerID: mockOwnerID,
         createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
         archived: false,
       );

  final Vice vice;
  final IconData icon;
  final int defaultQuantity;
  final List<int> previousSixDays;

  String get name => vice.name;
  Unit get unit => vice.unit;
}

class MockEntry {
  const MockEntry(
    this.vice,
    this.hour,
    this.minute,
    this.quantity, {
    this.triggers = const [],
    this.note,
  });

  final MockVice vice;
  final int hour;
  final int minute;
  final int quantity;
  final List<String> triggers;
  final String? note;
}

class MockDay {
  const MockDay({
    required this.date,
    required this.vices,
    required this.entries,
  });

  final DateTime date;
  final List<MockVice> vices;
  final List<MockEntry> entries;

  bool get isClean => entries.isEmpty;

  int total(MockVice vice) => entries
      .where((MockEntry e) => e.vice == vice)
      .fold(0, (int sum, MockEntry e) => sum + e.quantity);

  List<int> lastSevenDays(MockVice vice) => [
    ...vice.previousSixDays,
    total(vice),
  ];

  DateTime at(MockEntry entry) =>
      DateTime(date.year, date.month, date.day, entry.hour, entry.minute);

  List<ViceActivity> get activities => [
    for (final MockEntry e in entries)
      ViceActivity(
        id: '${e.vice.vice.id}-${e.hour}-${e.minute}',
        viceID: e.vice.vice.id,
        quantity: e.quantity,
        ownerID: mockOwnerID,
        createdAt: Timestamp.fromDate(at(e)),
      ),
  ];
}

const String mockOwnerID = 'mock-owner';

final DateTime mockDate = DateTime(2026, 11, 3);

final MockVice coffee = MockVice(
  id: 'coffee',
  name: 'Coffee',
  unit: Unit.drink,
  icon: Icons.coffee_outlined,
  defaultQuantity: 1,
  previousSixDays: [2, 3, 2, 4, 3, 1],
);

final MockVice wine = MockVice(
  id: 'wine',
  name: 'Wine',
  unit: Unit.drink,
  icon: Icons.wine_bar_outlined,
  defaultQuantity: 1,
  previousSixDays: [0, 2, 0, 0, 3, 4],
);

final MockVice vape = MockVice(
  id: 'vape',
  name: 'Vape',
  unit: Unit.time,
  icon: Icons.cloud_outlined,
  defaultQuantity: 1,
  previousSixDays: [6, 5, 7, 4, 5, 8],
);

final MockVice socialMedia = MockVice(
  id: 'social',
  name: 'Social media',
  unit: Unit.hour,
  icon: Icons.phone_iphone,
  defaultQuantity: 1,
  previousSixDays: [3, 2, 4, 2, 1, 3],
);

final MockVice sweets = MockVice(
  id: 'sweets',
  name: 'Sweets',
  unit: Unit.item,
  icon: Icons.cookie_outlined,
  defaultQuantity: 1,
  previousSixDays: [1, 0, 2, 3, 1, 2],
);

final MockDay twoVices = MockDay(
  date: mockDate,
  vices: [coffee, wine],
  entries: [
    MockEntry(coffee, 7, 40, 1, triggers: ['Morning routine']),
    MockEntry(coffee, 10, 15, 1, triggers: ['Work', 'Tired']),
    MockEntry(coffee, 14, 5, 1, triggers: ['Afternoon dip']),
    MockEntry(wine, 18, 45, 1, triggers: ['Social'], note: 'Dinner with Sam'),
    MockEntry(wine, 20, 10, 1, triggers: ['Social']),
  ],
);

final MockDay fiveVices = MockDay(
  date: mockDate,
  vices: [coffee, wine, vape, socialMedia, sweets],
  entries: [
    MockEntry(coffee, 7, 40, 1, triggers: ['Morning routine']),
    MockEntry(socialMedia, 8, 5, 1, triggers: ['Commute']),
    MockEntry(coffee, 10, 15, 1, triggers: ['Work', 'Tired']),
    MockEntry(vape, 12, 50, 2, triggers: ['After a meal']),
    MockEntry(
      sweets,
      15,
      20,
      2,
      triggers: ['Afternoon dip'],
      note: 'Biscuits in the planning meeting',
    ),
    MockEntry(coffee, 15, 30, 1, triggers: ['Work']),
    MockEntry(vape, 17, 10, 2, triggers: ['Stress']),
    MockEntry(wine, 18, 45, 1, triggers: ['Social'], note: 'Dinner with Sam'),
    MockEntry(vape, 19, 30, 2, triggers: ['Social']),
    MockEntry(wine, 20, 10, 1, triggers: ['Social']),
    MockEntry(socialMedia, 21, 0, 1, triggers: ['In bed', 'Bored']),
  ],
);

final MockDay cleanDay = MockDay(
  date: mockDate,
  vices: [coffee, wine, vape, socialMedia, sweets],
  entries: const [],
);

ThemeData mockAppTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.pink,
    brightness: Brightness.dark,
  ),
  useMaterial3: true,
);

/// [fiveVices] after a tap on the Wine tile at 21:32.
final MockDay fiveVicesAfterWineTap = MockDay(
  date: mockDate,
  vices: fiveVices.vices,
  entries: [...fiveVices.entries, MockEntry(wine, 21, 32, 1)],
);
