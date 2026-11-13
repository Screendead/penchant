import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/account/export.dart';

final DateTime _monday = DateTime.utc(2026, 11, 2, 9, 30);

AccountData _data() => AccountData(
  vices: <StoredDocument>[
    (
      id: 'v1',
      data: <String, dynamic>{
        'name': 'Coffee, "flat white"\nlarge',
        'unit': 'drink',
        'ownerID': 'owner',
        'createdAt': Timestamp.fromDate(_monday),
        'archived': false,
      },
    ),
  ],
  activities: <StoredDocument>[
    (
      id: 'a2',
      data: <String, dynamic>{
        'viceID': 'gone',
        'quantity': 1,
        'amount': 0.5,
        'ownerID': 'owner',
        'createdAt': Timestamp.fromDate(_monday.add(const Duration(hours: 2))),
      },
    ),
    (
      id: 'a1',
      data: <String, dynamic>{
        'viceID': 'v1',
        'quantity': 3,
        'ownerID': 'owner',
        'createdAt': Timestamp.fromDate(_monday),
        'note': 'kept although no field list names it',
        'triggers': <String>['work/meeting', 'Late, "very"'],
      },
    ),
  ],
);

void main() {
  test('the CSV has one row per activity, oldest first, quoted per RFC 4180, '
      'keeps an activity whose vice is gone, leaves a missing amount blank, '
      'and joins triggers, with the later columns at the end', () {
    expect(
      exportCsv(_data()),
      'time,vice,quantity,amount,unit,vice_id,entry_id,triggers,'
      'urge,note,time_zone,written_at,logged_via\r\n'
      '2026-11-02T09:30:00.000Z,"Coffee, ""flat white""\nlarge",3,,drink,v1,a1,'
      '"work/meeting; Late, ""very""",,kept although no field list names it,'
      ',,\r\n'
      '2026-11-02T11:30:00.000Z,,1,0.5,,gone,a2,,,,,,\r\n',
    );
  });

  test('the CSV writes urge, zone, write time and source as stored', () {
    final String csv = exportCsv(
      AccountData(
        vices: const <StoredDocument>[],
        activities: <StoredDocument>[
          (
            id: 'a',
            data: <String, dynamic>{
              'viceID': 'v',
              'quantity': 1,
              'createdAt': Timestamp.fromDate(_monday),
              'urge': 4,
              'zone': 'Europe/London',
              'writtenAt': DateTime.utc(2026, 11, 2, 21).millisecondsSinceEpoch,
              'loggedVia': 'sheet',
            },
          ),
        ],
      ),
    );
    expect(
      csv.split('\r\n')[1],
      endsWith(',4,,Europe/London,2026-11-02T21:00:00.000Z,sheet'),
    );
  });

  test('the JSON holds every stored field, ids, and UTC ISO-8601 times', () {
    final Map<String, dynamic> json =
        jsonDecode(exportJson(_data(), _monday)) as Map<String, dynamic>;
    expect(json['exportedAt'], '2026-11-02T09:30:00.000Z');
    expect(json['vices'], <Object>[
      <String, Object>{
        'id': 'v1',
        'name': 'Coffee, "flat white"\nlarge',
        'unit': 'drink',
        'ownerID': 'owner',
        'createdAt': '2026-11-02T09:30:00.000Z',
        'archived': false,
      },
    ]);
    final List<dynamic> activities = json['activities'] as List<dynamic>;
    expect(activities, hasLength(2));
    expect(
      activities.firstWhere((dynamic a) => a['id'] == 'a1')['note'],
      'kept although no field list names it',
    );
  });

  test('an export is a dated CSV and a dated JSON file', () {
    final List<ExportFile> files = exportFiles(_data(), _monday);
    expect(
      <String>[for (final ExportFile f in files) f.name],
      <String>[
        'penchant-entries-2026-11-02.csv',
        'penchant-export-2026-11-02.json',
      ],
    );
    expect(
      <String>[for (final ExportFile f in files) f.mimeType],
      <String>['text/csv', 'application/json'],
    );
  });
}
