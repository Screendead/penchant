import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/report/report_output.dart';

// "Today" in the report tests: a Monday, so three months run from 1 September.
final DateTime reportNow = DateTime(2026, 11, 16, 9, 30);

StoredDocument storedVice(
  String id,
  String name,
  String unit, {
  int order = 0,
  Map<String, Object?> extra = const <String, Object?>{},
}) => (
  id: id,
  data: <String, dynamic>{
    'name': name,
    'unit': unit,
    'ownerID': 'owner',
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1 + order)),
    'archived': false,
    'category': 'other',
    ...extra,
  },
);

StoredDocument storedEntry(
  String id,
  String viceID,
  DateTime at,
  num quantity, {
  List<String> triggers = const <String>[],
  String? note,
}) => (
  id: id,
  data: <String, dynamic>{
    'viceID': viceID,
    'quantity': quantity is int ? quantity : quantity.ceil(),
    if (quantity is double) 'amount': quantity,
    'ownerID': 'owner',
    'createdAt': Timestamp.fromDate(at),
    'triggers': triggers,
    'note': ?note,
  },
);

// A sealed document this device could not open: fetchData leaves its
// envelope in place.
StoredDocument lockedEntry(String id, String viceID, DateTime at) => (
  id: id,
  data: <String, dynamic>{
    'viceID': viceID,
    'quantity': 4,
    'ownerID': 'owner',
    'createdAt': Timestamp.fromDate(at),
    'sealed': Blob(Uint8List(40)),
  },
);

// A plausible three months and more of wine and coffee, the same every run.
AccountData sampleJournal({int days = 380}) {
  final Random random = Random(7);
  final List<StoredDocument> entries = <StoredDocument>[];
  final DateTime today = startOfDay(reportNow);
  int n = 0;
  for (int d = 0; d < days; d++) {
    final DateTime day = addDays(today, -d);
    final bool weekend = day.weekday >= DateTime.friday;
    if (random.nextDouble() < (weekend ? 0.8 : 0.35)) {
      final int glasses = 1 + random.nextInt(weekend ? 4 : 2);
      for (int g = 0; g < glasses; g++) {
        entries.add(
          storedEntry(
            'w${n++}',
            'wine',
            day.add(Duration(hours: 18 + g, minutes: random.nextInt(50))),
            1,
            triggers: <String>[
              if (random.nextDouble() < 0.5) 'social/friends',
              if (random.nextDouble() < 0.3) 'feeling/stressed',
              if (random.nextDouble() < 0.1) 'cheese night',
            ],
            note: g == 0 && random.nextDouble() < 0.06
                ? 'Dinner with the neighbours'
                : null,
          ),
        );
      }
    }
    for (int c = 0; c < 1 + random.nextInt(3); c++) {
      entries.add(
        storedEntry(
          'c${n++}',
          'coffee',
          day.add(Duration(hours: 7 + c * 3, minutes: random.nextInt(40))),
          1,
          triggers: <String>[if (random.nextDouble() < 0.4) 'work/meeting'],
        ),
      );
    }
  }
  entries.add(lockedEntry('locked', 'wine', addDays(today, -3)));
  return AccountData(
    vices: <StoredDocument>[
      storedVice(
        'wine',
        'Wine',
        'drink',
        extra: <String, Object?>{
          'unitLabel': 'glasses',
          'unitSingular': 'glass',
          'strengthUnit': 'ukUnit',
          'servingMl': 175,
          'abv': 13,
        },
      ),
      storedVice(
        'coffee',
        'Coffee',
        'drink',
        order: 1,
        extra: <String, Object?>{'unitLabel': 'cups', 'unitSingular': 'cup'},
      ),
    ],
    activities: entries,
    dayNotes: <StoredDocument>[
      (
        id: 'owner_2026-11-01',
        data: <String, dynamic>{
          'ownerID': 'owner',
          'day': '2026-11-01',
          'text': 'Long week, slept badly.',
          'triggers': <String>[],
        },
      ),
    ],
  );
}

// Records what would be drawn, written and shared.
class FakeReportOutput implements ReportOutput {
  FakeReportOutput([this.images = const <ui.Image>[]]);

  final List<ui.Image> images;
  Uint8List? rastered;
  String? shared;
  int discarded = 0;

  @override
  Future<List<ui.Image>> pages(Uint8List pdf) async {
    rastered = pdf;
    return images;
  }

  @override
  Future<File> write(Uint8List pdf, String name) async => File(name);

  @override
  Future<void> share(File file, {ui.Rect? origin}) async {
    shared = file.path;
  }

  @override
  Future<void> discard() async => discarded++;
}
