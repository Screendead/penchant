import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/backup/backup_file.dart';
import 'package:tracker/crypto/journal_key.dart';
import 'package:tracker/crypto/key_service.dart';
import 'package:tracker/crypto/recovery_key.dart';

final AesGcm _aes128 = AesGcm.with128bits();
final AesGcm _aes256 = AesGcm.with256bits();
const String _uid = 'source-uid';
final JournalKey _key = JournalKey(List<int>.filled(32, 7));
final Uint8List _recovery = RecoveryKey.generate(Random(3));

Future<KeyRecord> _record({JournalKey? key, String uid = _uid}) async =>
    KeyRecord(
      keyID: keyIDOf(key ?? _key),
      wrapped: await (key ?? _key).wrap(
        aes128: _aes128,
        recoveryKey: _recovery,
        uid: uid,
      ),
      createdAt: DateTime.utc(2026, 1, 1),
    );

final Map<String, List<StoredDocument>> _journal =
    <String, List<StoredDocument>>{
      'vices': <StoredDocument>[
        (
          id: 'v1',
          data: <String, dynamic>{
            'ownerID': _uid,
            'createdAt': Timestamp(1700000000, 123456789),
            'archived': false,
            'sealed': Blob(Uint8List.fromList(<int>[1, 2, 3, 255])),
          },
        ),
        (
          id: 'legacy',
          data: <String, dynamic>{
            'ownerID': _uid,
            'name': 'Coffee',
            'unit': 'drink',
            'createdAt': Timestamp(1600000000, 0),
          },
        ),
      ],
      'activities': <StoredDocument>[
        (
          id: 'a1',
          data: <String, dynamic>{
            'ownerID': _uid,
            'viceID': 'v1',
            'quantity': 2,
            'amount': 1.5,
            'whole': 3.0,
            'triggers': <Object?>['work/meeting', 'own words'],
            'nested': <String, dynamic>{
              r'$timestamp': 'not a tag',
              'inner': <Object?>[null, true, Timestamp(1, 2)],
            },
          },
        ),
      ],
      'dayNotes': const <StoredDocument>[],
    };

Future<Uint8List> _file({Map<String, List<StoredDocument>>? journal}) async =>
    BackupFile.write(
      uid: _uid,
      journalKey: _key,
      record: await _record(),
      collections: journal ?? _journal,
      aes256: _aes256,
      createdAt: DateTime.utc(2026, 11, 16, 9),
    );

Future<OpenedBackup> _open(Uint8List file, {Uint8List? recovery}) =>
    BackupFile.open(
      file,
      recoveryKey: recovery ?? _recovery,
      aes128: _aes128,
      aes256: _aes256,
    );

Future<void> _fails(Uint8List file, BackupFailure failure) async {
  await expectLater(
    _open(file),
    throwsA(
      isA<BackupException>().having(
        (BackupException e) => e.failure,
        'failure',
        failure,
      ),
    ),
  );
}

int _headerLength(Uint8List file) =>
    ByteData.sublistView(file, 9, 13).getUint32(0);

// The file with its trailing checksum made again, as someone changing it on
// purpose would.
Uint8List _rechecked(Uint8List file) {
  final Uint8List out = Uint8List.fromList(file);
  final int end = out.length - BackupFile.checksumLength;
  out.setRange(
    end,
    out.length,
    const DartSha256().hashSync(out.sublist(0, end)).bytes,
  );
  return out;
}

Uint8List _flip(Uint8List file, int at) =>
    Uint8List.fromList(file)..[at] ^= 0x01;

// The header rewritten with [change], lengths kept consistent.
Uint8List _withHeader(
  Uint8List file,
  void Function(Map<String, dynamic>) change,
) {
  final int length = _headerLength(file);
  final Map<String, dynamic> header =
      jsonDecode(utf8.decode(file.sublist(13, 13 + length)))
          as Map<String, dynamic>;
  change(header);
  final Uint8List encoded = utf8.encode(jsonEncode(header));
  final ByteData size = ByteData(4)..setUint32(0, encoded.length);
  return _rechecked(
    (BytesBuilder()
          ..add(file.sublist(0, 9))
          ..add(size.buffer.asUint8List())
          ..add(encoded)
          ..add(file.sublist(13 + length)))
        .toBytes(),
  );
}

void main() {
  test('a backup opens to every document as it was saved', () async {
    final Uint8List file = await _file();
    final OpenedBackup opened = await _open(file);

    expect(opened.header.uid, _uid);
    expect(opened.header.createdAt, DateTime.utc(2026, 11, 16, 9));
    expect(opened.header.keyID, keyIDOf(_key));
    expect(opened.journalKey.sameAs(_key), isTrue);
    expect(opened.collections.keys, _journal.keys);
    final Map<String, dynamic> vice = opened.collections['vices']!.first.data;
    expect(vice['createdAt'], Timestamp(1700000000, 123456789));
    expect((vice['sealed'] as Blob).bytes, <int>[1, 2, 3, 255]);
    final Map<String, dynamic> activity =
        opened.collections['activities']!.single.data;
    expect(activity['quantity'], isA<int>());
    expect(activity['whole'], isA<double>());
    expect(activity['whole'], 3.0);
    expect(activity['amount'], 1.5);
    expect(activity['triggers'], <Object?>['work/meeting', 'own words']);
    expect(activity['nested'], <String, dynamic>{
      r'$timestamp': 'not a tag',
      'inner': <Object?>[null, true, Timestamp(1, 2)],
    });
    expect(opened.collections['dayNotes'], isEmpty);
  });

  test('the header holds only what opening needs', () async {
    final Uint8List file = await _file();
    final Map<String, dynamic> header =
        jsonDecode(utf8.decode(file.sublist(13, 13 + _headerLength(file))))
            as Map<String, dynamic>;
    expect(header.keys, <String>{
      'createdAt',
      'uid',
      'keyID',
      'wrapped',
      'bodyLength',
    });
    expect(base64.decode(header['wrapped'] as String), hasLength(61));
    expect(utf8.decode(file, allowMalformed: true), isNot(contains('Coffee')));
  });

  test('its length reveals only a power of two of journal', () async {
    final int small = (await _file()).length;
    final int larger = (await _file(
      journal: <String, List<StoredDocument>>{
        ..._journal,
        'dayNotes': <StoredDocument>[
          (id: 'n', data: <String, dynamic>{'pad': 'x' * 100}),
        ],
      },
    )).length;
    expect(larger, small);
  });

  test('a journal of several megabytes fits one envelope', () async {
    final Uint8List file = await _file(
      journal: <String, List<StoredDocument>>{
        'activities': <StoredDocument>[
          for (int i = 0; i < 12000; i++)
            (
              id: 'activity$i',
              data: <String, dynamic>{
                'ownerID': _uid,
                'viceID': 'v1',
                'quantity': 1,
                'createdAt': Timestamp(1700000000 + i, 0),
                'sealed': Blob(Uint8List(93)),
              },
            ),
        ],
      },
    );
    expect(file.length, greaterThan(2 * 1024 * 1024));
    expect((await _open(file)).collections['activities'], hasLength(12000));
  });

  test('a value with no tag is refused, not dropped', () async {
    await expectLater(
      _file(
        journal: <String, List<StoredDocument>>{
          'vices': <StoredDocument>[
            (id: 'v', data: <String, dynamic>{'where': const GeoPoint(1, 2)}),
          ],
        },
      ),
      throwsA(isA<UnsupportedBackupValue>()),
    );
  });

  test('a record for another key is refused when writing', () async {
    await expectLater(
      BackupFile.write(
        uid: _uid,
        journalKey: _key,
        record: await _record(key: JournalKey(List<int>.filled(32, 8))),
        collections: _journal,
        aes256: _aes256,
        createdAt: DateTime.utc(2026),
      ),
      throwsArgumentError,
    );
  });

  group('fails closed', () {
    test('with a valid recovery key for another journal', () async {
      final Uint8List file = await _file();
      await expectLater(
        _open(file, recovery: RecoveryKey.generate(Random(4))),
        throwsA(
          isA<BackupException>().having(
            (BackupException e) => e.failure,
            'failure',
            BackupFailure.wrongRecoveryKey,
          ),
        ),
      );
    });

    test('when cut short anywhere', () async {
      final Uint8List file = await _file();
      for (final int keep in <int>[
        file.length - 1,
        file.length - BackupFile.checksumLength,
        file.length ~/ 2,
        13 + _headerLength(file),
        20,
        10,
      ]) {
        await _fails(file.sublist(0, keep), BackupFailure.incomplete);
      }
      await _fails(file.sublist(0, 5), BackupFailure.notABackup);
    });

    test('with bytes added at the end', () async {
      await _fails(
        Uint8List.fromList(<int>[...await _file(), 0]),
        BackupFailure.damaged,
      );
    });

    test('for a newer format', () async {
      final Uint8List file = await _file();
      file[8] = BackupFile.version + 1;
      await _fails(file, BackupFailure.newerFormat);
    });

    test('for something else entirely', () async {
      await _fails(
        Uint8List.fromList(utf8.encode('{"vices": []}' * 10)),
        BackupFailure.notABackup,
      );
    });

    test('when the key id is not the wrapped key\'s', () async {
      final Uint8List file = _withHeader(
        await _file(),
        (Map<String, dynamic> h) => h['keyID'] = keyIDOf(JournalKey.generate()),
      );
      await _fails(file, BackupFailure.keyMismatch);
    });

    test('for a changed byte in each region', () async {
      final Uint8List file = await _file();
      final int headerEnd = 13 + _headerLength(file);
      final int bodyEnd = file.length - BackupFile.checksumLength;
      final String header = utf8.decode(file.sublist(13, headerEnd));
      int inHeader(String text) => 13 + header.indexOf(text);
      final Map<String, (int, BackupFailure, BackupFailure)> regions =
          <String, (int, BackupFailure, BackupFailure)>{
            // Changed byte, then the failure with the checksum left alone and
            // with it made again.
            'magic': (0, BackupFailure.notABackup, BackupFailure.notABackup),
            'header length': (
              12,
              BackupFailure.notABackup,
              BackupFailure.notABackup,
            ),
            'creation time': (
              inHeader('"createdAt":') + 13,
              BackupFailure.damaged,
              BackupFailure.modified,
            ),
            'account id': (
              inHeader(_uid) + 2,
              BackupFailure.damaged,
              BackupFailure.wrongRecoveryKey,
            ),
            'wrapped key': (
              inHeader('"wrapped":"') + 20,
              BackupFailure.damaged,
              BackupFailure.wrongRecoveryKey,
            ),
            'body version': (
              headerEnd,
              BackupFailure.damaged,
              BackupFailure.modified,
            ),
            'body nonce': (
              headerEnd + 5,
              BackupFailure.damaged,
              BackupFailure.modified,
            ),
            'ciphertext': (
              headerEnd + 400,
              BackupFailure.damaged,
              BackupFailure.modified,
            ),
            'tag': (bodyEnd - 1, BackupFailure.damaged, BackupFailure.modified),
            'checksum': (
              file.length - 1,
              BackupFailure.damaged,
              BackupFailure.damaged,
            ),
          };
      for (final MapEntry<String, (int, BackupFailure, BackupFailure)>(
            key: String region,
            value: (int at, BackupFailure plain, BackupFailure rechecked),
          )
          in regions.entries) {
        Uint8List changed = _flip(file, at);
        // A flipped base64 or digit character must stay one, or the header
        // stops parsing before the check this case is about.
        if (region == 'wrapped key' || region == 'creation time') {
          changed = Uint8List.fromList(file)
            ..[at] = file[at] == 0x41 ? 0x42 : 0x41;
          if (region == 'creation time') {
            changed[at] = file[at] == 0x31 ? 0x32 : 0x31;
          }
        }
        if (region == 'checksum') {
          await _fails(changed, plain);
          continue;
        }
        await expectLater(
          _open(changed),
          throwsA(
            isA<BackupException>().having(
              (BackupException e) => e.failure,
              '$region, checksum unchanged',
              plain,
            ),
          ),
        );
        await expectLater(
          _open(_rechecked(changed)),
          throwsA(
            isA<BackupException>().having(
              (BackupException e) => e.failure,
              '$region, checksum made again',
              rechecked,
            ),
          ),
        );
      }
    });
  });
}
