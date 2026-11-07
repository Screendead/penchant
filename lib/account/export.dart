import 'dart:convert';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/account/account_copy.dart';
import 'package:tracker/data/activity_triggers.dart';

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
  ];
}

const List<String> csvHeader = <String>[
  'time',
  'vice',
  'quantity',
  'unit',
  'vice_id',
  'entry_id',
  'triggers',
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
    csv.write(
      _csvRow(<Object?>[
        _plain(activity.data['createdAt']),
        vice?['name'],
        activity.data['quantity'],
        vice?['unit'],
        viceID,
        activity.id,
        readTriggers(activity.data[triggersField]).join('; '),
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
