import 'dart:convert';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tracker/data/habit_strength.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/account/account_copy.dart';
import 'package:tracker/data/activity_content.dart';
import 'package:tracker/data/activity_triggers.dart';
import 'package:tracker/data/check_in.dart';
import 'package:tracker/data/urge.dart';
import 'package:tracker/notes/follow_up.dart';

@immutable
class ExportFile {
  const ExportFile({
    required this.name,
    required this.mimeType,
    required this.contents,
  });

  final String name;
  final String mimeType;
  final String contents;
}

List<ExportFile> exportFiles(AccountData data, DateTime exportedAt) {
  final String stamp = exportedAt.toUtc().toIso8601String().substring(0, 10);
  return <ExportFile>[
    ExportFile(
      name: 'penchant-entries-$stamp.csv',
      mimeType: 'text/csv',
      contents: exportCsv(data),
    ),
    ExportFile(
      name: 'penchant-export-$stamp.json',
      mimeType: 'application/json',
      contents: exportJson(data, exportedAt),
    ),
    // Only for someone who has written one, so nobody else gets an empty file.
    if (data.dayNotes.isNotEmpty)
      ExportFile(
        name: 'penchant-day-notes-$stamp.csv',
        mimeType: 'text/csv',
        contents: exportDayNotesCsv(data),
      ),
    if (data.urges.isNotEmpty)
      ExportFile(
        name: 'penchant-urges-$stamp.csv',
        mimeType: 'text/csv',
        contents: exportUrgesCsv(data),
      ),
    if (data.checkIns.isNotEmpty)
      ExportFile(
        name: 'penchant-check-ins-$stamp.csv',
        mimeType: 'text/csv',
        contents: exportCheckInsCsv(data),
      ),
  ];
}

const List<String> csvHeader = <String>[
  'time',
  'vice',
  'quantity',
  'amount',
  'unit',
  'vice_id',
  'entry_id',
  'triggers',
  // Added later, so they come last and older columns keep their places.
  'urge',
  'note',
  'time_zone',
  'written_at',
  'logged_via',
  'follow_up_question',
  'follow_up_quote',
  'follow_up_answer',
  'own_abv',
  'own_caffeine_mg',
  'strength_total',
  'strength_unit',
];

// One row per activity, oldest first. An activity whose vice is gone keeps
// its vice id and leaves the name and unit blank. Triggers are joined with
// "; ", as stored: tree paths or free text.
String exportCsv(AccountData data) {
  final Map<String, Map<String, dynamic>> vices =
      <String, Map<String, dynamic>>{
        for (final StoredDocument vice in data.vices) vice.id: vice.data,
      };
  final List<StoredDocument> activities = List<StoredDocument>.of(
    data.activities,
  )..sort((a, b) => _sortKey(a).compareTo(_sortKey(b)));

  final StringBuffer csv = StringBuffer()..write(_csvRow(csvHeader));
  for (final StoredDocument activity in activities) {
    final Object? viceID = activity.data['viceID'];
    final Map<String, dynamic>? vice = vices[viceID];
    final ActivityContent content = ActivityContent.read(activity.data);
    final HabitStrength? strength = vice == null
        ? null
        : HabitStrength.read(vice);
    // What the entry comes to in its habit's chosen unit, as Trends counts it.
    final double? total = strength?.of(
      ViceActivity.fromJson(
        id: activity.id,
        json: activity.data,
        opened: activity.data,
      ),
    );
    csv.write(
      _csvRow(<Object?>[
        _plain(activity.data['createdAt']),
        vice?['name'],
        activity.data['quantity'],
        activity.data['amount'],
        vice?['unit'],
        viceID,
        activity.id,
        content.triggers.join('; '),
        content.urge,
        content.note,
        content.zone,
        _plain(content.writtenAt),
        content.loggedVia?.name,
        content.followUp?.question,
        content.followUp?.quote,
        content.followUp?.answer,
        content.abv,
        content.caffeineMg,
        total,
        total == null ? null : strength?.unit.name,
      ]),
    );
  }
  return csv.toString();
}

const List<String> dayNotesCsvHeader = <String>[
  'day',
  'text',
  'triggers',
  // Added later, so they come last and older columns keep their places.
  'follow_up_question',
  'follow_up_quote',
  'follow_up_answer',
];

// One row per day note, by day. A note that would not open keeps its day and
// leaves the rest blank; the JSON keeps its envelope.
String exportDayNotesCsv(AccountData data) {
  final List<StoredDocument> notes = List<StoredDocument>.of(data.dayNotes)
    ..sort((a, b) => '${a.data['day']}'.compareTo('${b.data['day']}'));
  final StringBuffer csv = StringBuffer()..write(_csvRow(dayNotesCsvHeader));
  for (final StoredDocument note in notes) {
    final Object? text = note.data['text'];
    final FollowUp? followUp = FollowUp.read(note.data);
    csv.write(
      _csvRow(<Object?>[
        note.data['day'],
        text is String ? text : null,
        readTriggers(note.data[triggersField]).join('; '),
        followUp?.question,
        followUp?.quote,
        followUp?.answer,
      ]),
    );
  }
  return csv.toString();
}

const List<String> urgesCsvHeader = <String>[
  'time',
  'vice',
  'vice_id',
  'urge_id',
  'strength',
  'outcome',
  'outcome_at',
  'time_zone',
];

// One row per urge, oldest first. An urge that would not open keeps its time
// and habit and leaves the rest blank; the JSON keeps its envelope.
String exportUrgesCsv(AccountData data) {
  final Map<String, Map<String, dynamic>> vices =
      <String, Map<String, dynamic>>{
        for (final StoredDocument vice in data.vices) vice.id: vice.data,
      };
  final List<StoredDocument> urges = List<StoredDocument>.of(data.urges)
    ..sort((a, b) => _sortKey(a).compareTo(_sortKey(b)));
  final StringBuffer csv = StringBuffer()..write(_csvRow(urgesCsvHeader));
  for (final StoredDocument urge in urges) {
    final Object? viceID = urge.data['viceID'];
    final UrgeContent content = UrgeContent.read(urge.data);
    csv.write(
      _csvRow(<Object?>[
        _plain(urge.data['createdAt']),
        vices[viceID]?['name'],
        viceID,
        urge.id,
        content.strength,
        content.outcome?.name,
        _plain(content.outcomeAt),
        content.zone,
      ]),
    );
  }
  return csv.toString();
}

const List<String> checkInsCsvHeader = <String>[
  'time',
  'check_in_id',
  'strength',
  'prompted_at',
  'answered_via',
  'time_zone',
];

// One row per answered check-in, oldest first. One that would not open keeps
// its time and leaves the rest blank; the JSON keeps its envelope.
String exportCheckInsCsv(AccountData data) {
  final List<StoredDocument> checkIns = List<StoredDocument>.of(data.checkIns)
    ..sort((a, b) => _sortKey(a).compareTo(_sortKey(b)));
  final StringBuffer csv = StringBuffer()..write(_csvRow(checkInsCsvHeader));
  for (final StoredDocument checkIn in checkIns) {
    final CheckInContent content = CheckInContent.read(checkIn.data);
    csv.write(
      _csvRow(<Object?>[
        _plain(checkIn.data['createdAt']),
        checkIn.id,
        content.strength,
        _plain(content.promptedAt),
        content.via?.name,
        content.zone,
      ]),
    );
  }
  return csv.toString();
}

// Every stored field, unknown ones included, so nothing logged is lost.
String exportJson(AccountData data, DateTime exportedAt) {
  List<Map<String, Object?>> documents(List<StoredDocument> docs) =>
      <Map<String, Object?>>[
        for (final StoredDocument doc in docs)
          <String, Object?>{
            'id': doc.id,
            for (final MapEntry<String, dynamic> field in doc.data.entries)
              field.key: _plain(field.value),
          },
      ];

  return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'vices': documents(data.vices),
    'activities': documents(data.activities),
    'dayNotes': documents(data.dayNotes),
    'urges': documents(data.urges),
    'checkIns': documents(data.checkIns),
  });
}

String _sortKey(StoredDocument doc) => '${_plain(doc.data['createdAt'])}';

Object? _plain(Object? value) {
  return switch (value) {
    Timestamp() => value.toDate().toUtc().toIso8601String(),
    DateTime() => value.toUtc().toIso8601String(),
    GeoPoint() => <String, double>{
      'latitude': value.latitude,
      'longitude': value.longitude,
    },
    DocumentReference() => value.path,
    Blob() => base64Encode(value.bytes),
    List<Object?>() => value.map(_plain).toList(),
    Map<Object?, Object?>() => <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        '${entry.key}': _plain(entry.value),
    },
    _ => value,
  };
}

// RFC 4180: quote a field holding a comma, quote or line break, and double
// any quote inside it. Lines end in CRLF.
String _csvRow(List<Object?> fields) =>
    '${fields.map(_csvField).join(',')}\r\n';

String _csvField(Object? value) {
  final String text = value == null ? '' : '$value';
  if (text.contains(RegExp(r'[",\r\n]'))) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

// The share sheet sits behind this so tests can capture what would be shared.
class ExportShare {
  const ExportShare();

  Future<void> share(List<ExportFile> files, {Rect? origin}) async {
    await SharePlus.instance.share(
      ShareParams(
        subject: AccountCopy.exportSubject,
        files: <XFile>[
          for (final ExportFile file in files)
            XFile.fromData(
              utf8.encode(file.contents),
              mimeType: file.mimeType,
              name: file.name,
            ),
        ],
        fileNameOverrides: <String>[
          for (final ExportFile file in files) file.name,
        ],
        sharePositionOrigin: origin,
      ),
    );
  }
}
