import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/crypto/journal_key.dart';
import 'package:tracker/crypto/key_service.dart';
import 'package:tracker/crypto/sealer.dart';

// The layout is written down in docs/backup-format.md; a change to it raises
// [BackupFile.version] and that page.

enum BackupFailure {
  /// Not a Penchant backup at all, or its fixed header is unreadable.
  notABackup,

  /// Written by a newer build, in a format this one cannot read.
  newerFormat,

  /// Shorter than its header says: cut short while copying or saving.
  incomplete,

  /// Its checksum does not match: damaged in storage or transit.
  damaged,

  /// The recovery key does not open the key it carries. A changed byte in the
  /// wrapped key or the account id looks exactly the same to AES-GCM.
  wrongRecoveryKey,

  /// The key it carries opens but is not the key its header names.
  keyMismatch,

  /// The key opened, but the sealed journal does not open with it: changed on
  /// purpose, with the checksum made again.
  modified,
}

class BackupException implements Exception {
  const BackupException(this.failure, [this.detail]);

  final BackupFailure failure;
  final String? detail;

  @override
  String toString() =>
      'BackupException(${failure.name})${detail == null ? '' : ': $detail'}';
}

/// A value this format has no tag for (a GeoPoint, a reference). Nothing in
/// the journal holds one; the backup refuses rather than drop it.
class UnsupportedBackupValue implements Exception {
  const UnsupportedBackupValue(this.where, this.type);

  final String where;
  final String type;

  @override
  String toString() => 'UnsupportedBackupValue: a $type at $where';
}

/// What can be read before the recovery key is typed.
class BackupHeader {
  const BackupHeader({
    required this.createdAt,
    required this.uid,
    required this.keyID,
    required this.wrapped,
    required this.bodyLength,
  });

  final DateTime createdAt;

  /// The account the backup was saved from. The wrapped key's associated data
  /// binds it, so it cannot be opened without it.
  final String uid;
  final String keyID;
  final Uint8List wrapped;
  final int bodyLength;
}

class OpenedBackup {
  const OpenedBackup({
    required this.header,
    required this.journalKey,
    required this.collections,
  });

  final BackupHeader header;

  /// Held in memory only, to open the documents' envelopes at their original
  /// paths. Never stored and never made this account's key.
  final JournalKey journalKey;
  final Map<String, List<StoredDocument>> collections;
}

class BackupFile {
  BackupFile._();

  static final Uint8List magic = Uint8List.fromList(ascii.encode('PNCHNTBK'));
  static const int version = 1;
  static const int _fixed = 8 + 1 + 4;
  static const int checksumLength = 32;

  // A header far past this is not one this format writes.
  static const int _maxHeader = 4096;

  /// Seals [collections] with [journalKey] under [aes256]. [record] is the
  /// server's `keys/{uid}` record for that key: its `wrapped` copy travels in
  /// the file, so the recovery key alone opens it.
  static Future<Uint8List> write({
    required String uid,
    required JournalKey journalKey,
    required KeyRecord record,
    required Map<String, List<StoredDocument>> collections,
    required AesGcm aes256,
    required DateTime createdAt,
  }) async {
    if (keyIDOf(journalKey) != record.keyID) {
      throw ArgumentError('The key record names another journal key');
    }
    final Uint8List payload = utf8.encode(
      jsonEncode(<String, Object?>{
        'collections': <String, Object?>{
          for (final MapEntry<String, List<StoredDocument>>(:key, :value)
              in collections.entries)
            key: <Object?>[
              for (final StoredDocument doc in value)
                <String, Object?>{
                  'id': doc.id,
                  'data': encodeFields(doc.data, '$key/${doc.id}'),
                },
            ],
        },
      }),
    );
    final int bodyLength = Sealer.overhead + _paddedLength(payload.length);
    final Uint8List header = utf8.encode(
      jsonEncode(<String, Object?>{
        'createdAt': createdAt.toUtc().millisecondsSinceEpoch,
        'uid': uid,
        'keyID': record.keyID,
        'wrapped': base64.encode(record.wrapped),
        'bodyLength': bodyLength,
      }),
    );
    final Uint8List prefix = _prefix(header);
    final Uint8List body = await journalKey
        .sealer(aes256)
        .sealFile(payload, aad: prefix);
    if (body.length != bodyLength) {
      throw StateError('The sealed body is ${body.length}, not $bodyLength');
    }
    final Uint8List unchecked = (BytesBuilder(copy: false)
          ..add(prefix)
          ..add(body))
        .toBytes();
    return (BytesBuilder(copy: false)
          ..add(unchecked)
          ..add(_checksum(unchecked)))
        .toBytes();
  }

  static int _paddedLength(int payloadLength) {
    int bucket = Sealer.smallestFileBucket;
    while (bucket < payloadLength + 4) {
      bucket *= 2;
    }
    return bucket;
  }

  static Uint8List _prefix(Uint8List header) {
    final ByteData length = ByteData(4)..setUint32(0, header.length);
    return (BytesBuilder(copy: false)
          ..add(magic)
          ..addByte(version)
          ..add(length.buffer.asUint8List())
          ..add(header))
        .toBytes();
  }

  static Uint8List _checksum(List<int> bytes) =>
      Uint8List.fromList(const DartSha256().hashSync(bytes).bytes);

  /// Checks everything that needs no key: the magic, the version, the length
  /// and the checksum. Throws [BackupException].
  static BackupHeader readHeader(Uint8List file) {
    for (int i = 0; i < magic.length; i++) {
      if (i >= file.length || file[i] != magic[i]) {
        throw const BackupException(BackupFailure.notABackup);
      }
    }
    if (file.length < _fixed) {
      throw const BackupException(BackupFailure.incomplete);
    }
    final int fileVersion = file[magic.length];
    if (fileVersion > version) {
      throw BackupException(BackupFailure.newerFormat, 'version $fileVersion');
    }
    if (fileVersion != version) {
      throw BackupException(BackupFailure.notABackup, 'version $fileVersion');
    }
    final int headerLength = ByteData.sublistView(
      file,
      magic.length + 1,
      _fixed,
    ).getUint32(0);
    if (headerLength > _maxHeader) {
      throw const BackupException(BackupFailure.notABackup, 'header length');
    }
    if (file.length < _fixed + headerLength) {
      throw const BackupException(BackupFailure.incomplete);
    }
    final BackupHeader header = _parseHeader(
      file.sublist(_fixed, _fixed + headerLength),
    );
    final int expected =
        _fixed + headerLength + header.bodyLength + checksumLength;
    if (file.length < expected) {
      throw const BackupException(BackupFailure.incomplete);
    }
    if (file.length > expected) {
      throw const BackupException(BackupFailure.damaged, 'trailing bytes');
    }
    final Uint8List stated = file.sublist(expected - checksumLength);
    final Uint8List actual = _checksum(
      Uint8List.sublistView(file, 0, expected - checksumLength),
    );
    int diff = 0;
    for (int i = 0; i < checksumLength; i++) {
      diff |= stated[i] ^ actual[i];
    }
    if (diff != 0) {
      throw const BackupException(BackupFailure.damaged);
    }
    return header;
  }

  static BackupHeader _parseHeader(Uint8List bytes) {
    try {
      final Object? json = jsonDecode(utf8.decode(bytes));
      if (json is Map<String, dynamic>) {
        final Object? createdAt = json['createdAt'];
        final Object? uid = json['uid'];
        final Object? keyID = json['keyID'];
        final Object? wrapped = json['wrapped'];
        final Object? bodyLength = json['bodyLength'];
        if (createdAt is int &&
            uid is String &&
            uid.isNotEmpty &&
            keyID is String &&
            wrapped is String &&
            bodyLength is int &&
            bodyLength > Sealer.overhead) {
          return BackupHeader(
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              createdAt,
              isUtc: true,
            ),
            uid: uid,
            keyID: keyID,
            wrapped: base64.decode(wrapped),
            bodyLength: bodyLength,
          );
        }
      }
    } on FormatException {
      // Reported below with the other shapes.
    }
    throw const BackupException(BackupFailure.notABackup, 'header');
  }

  /// Opens [file] with [recoveryKey]. Throws [BackupException]; returns only
  /// what authenticated.
  static Future<OpenedBackup> open(
    Uint8List file, {
    required Uint8List recoveryKey,
    required AesGcm aes128,
    required AesGcm aes256,
  }) async {
    final BackupHeader header = readHeader(file);
    final JournalKey key;
    try {
      key = await JournalKey.unwrap(
        header.wrapped,
        aes128: aes128,
        recoveryKey: recoveryKey,
        uid: header.uid,
      );
    } on SealException catch (e) {
      throw BackupException(BackupFailure.wrongRecoveryKey, e.failure.name);
    }
    if (keyIDOf(key) != header.keyID) {
      throw const BackupException(BackupFailure.keyMismatch);
    }
    final int headerLength = ByteData.sublistView(
      file,
      magic.length + 1,
      _fixed,
    ).getUint32(0);
    final int bodyStart = _fixed + headerLength;
    final Uint8List payload;
    try {
      payload = await key
          .sealer(aes256)
          .openFile(
            Uint8List.sublistView(
              file,
              bodyStart,
              bodyStart + header.bodyLength,
            ),
            aad: Uint8List.sublistView(file, 0, bodyStart),
          );
    } on SealException catch (e) {
      throw BackupException(BackupFailure.modified, e.failure.name);
    }
    return OpenedBackup(
      header: header,
      journalKey: key,
      collections: _parsePayload(payload),
    );
  }

  // Authenticated by now, so a bad shape is a bug in the writer, reported
  // as a modified file rather than half read.
  static Map<String, List<StoredDocument>> _parsePayload(Uint8List payload) {
    try {
      final Object? json = jsonDecode(utf8.decode(payload));
      if (json is Map<String, dynamic> &&
          json['collections'] is Map<String, dynamic>) {
        return <String, List<StoredDocument>>{
          for (final MapEntry<String, dynamic>(:key, :value)
              in (json['collections'] as Map<String, dynamic>).entries)
            key: <StoredDocument>[
              for (final Map<String, dynamic> doc
                  in (value as List<Object?>).cast<Map<String, dynamic>>())
                (
                  id: doc['id'] as String,
                  data: decodeFields(doc['data'] as Map<String, dynamic>),
                ),
            ],
        };
      }
    } on Object catch (e) {
      throw BackupException(BackupFailure.modified, 'payload: $e');
    }
    throw const BackupException(BackupFailure.modified, 'payload');
  }

  /// Firestore values as JSON. Strings, bools, null, ints and doubles are
  /// themselves (Dart writes every double with a point or an exponent, so an
  /// int stays an int); maps, timestamps and bytes are one-key objects.
  static Map<String, Object?> encodeFields(
    Map<String, dynamic> fields,
    String where,
  ) => <String, Object?>{
    for (final MapEntry<String, dynamic>(:key, :value) in fields.entries)
      key: _encode(value, '$where.$key'),
  };

  static Object? _encode(Object? value, String where) => switch (value) {
    null || bool() || int() || String() => value,
    final double d when d.isFinite => d,
    final Timestamp t => <String, Object?>{
      r'$timestamp': <int>[t.seconds, t.nanoseconds],
    },
    final Blob b => <String, Object?>{r'$bytes': base64.encode(b.bytes)},
    final List<Object?> list => <Object?>[
      for (int i = 0; i < list.length; i++) _encode(list[i], '$where[$i]'),
    ],
    final Map<String, dynamic> map => <String, Object?>{
      r'$map': encodeFields(map, where),
    },
    _ => throw UnsupportedBackupValue(where, value.runtimeType.toString()),
  };

  static Map<String, dynamic> decodeFields(Map<String, dynamic> fields) =>
      <String, dynamic>{
        for (final MapEntry<String, dynamic>(:key, :value) in fields.entries)
          key: _decode(value),
      };

  static Object? _decode(Object? value) => switch (value) {
    null || bool() || num() || String() => value,
    final List<Object?> list => <Object?>[for (final v in list) _decode(v)],
    {r'$timestamp': [final int seconds, final int nanoseconds]} => Timestamp(
      seconds,
      nanoseconds,
    ),
    {r'$bytes': final String b} => Blob(base64.decode(b)),
    {r'$map': final Map<String, dynamic> m} => decodeFields(m),
    _ => throw const FormatException('An unknown tagged value'),
  };
}
