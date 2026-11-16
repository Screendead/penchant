// One small journal as a backup file, for the restore page's tests.
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/backup/backup_file.dart';
import 'package:tracker/crypto/journal_field_sealer.dart';
import 'package:tracker/crypto/journal_key.dart';
import 'package:tracker/crypto/key_service.dart';
import 'package:tracker/crypto/recovery_key.dart';
import 'package:tracker/data/sealed.dart';

final AesGcm aes128 = AesGcm.with128bits();
final AesGcm aes256 = AesGcm.with256bits();
const String _from = 'old-uid';
const String sampleToUid = 'new-uid';
final JournalKey _key = JournalKey(List<int>.filled(32, 7));
final Uint8List sampleRecoveryKey = RecoveryKey.generate(Random(5));
final Uint8List otherRecoveryKey = RecoveryKey.generate(Random(6));
final Timestamp _at = Timestamp(1700000000, 0);

Future<Uint8List> sampleBackup({bool unknown = false}) async {
  final JournalFieldSealer sealer = JournalFieldSealer(_key.sealer(aes256));
  Future<Blob> sealed(
    String c,
    String id,
    Map<String, Object?> content,
  ) async => Blob(await sealer.seal(content, context: sealContext(c, id)));
  return BackupFile.write(
    uid: _from,
    journalKey: _key,
    record: KeyRecord(
      keyID: keyIDOf(_key),
      wrapped: await _key.wrap(
        aes128: aes128,
        recoveryKey: sampleRecoveryKey,
        uid: _from,
      ),
      createdAt: DateTime.utc(2026),
    ),
    collections: <String, List<StoredDocument>>{
      'vices': <StoredDocument>[
        (
          id: 'v1',
          data: <String, dynamic>{
            'ownerID': _from,
            'createdAt': _at,
            'archived': false,
            'sealed': await sealed('vices', 'v1', <String, Object?>{
              'name': 'Coffee',
              'unit': 'drink',
              'category': 'caffeine',
            }),
          },
        ),
      ],
      'activities': <StoredDocument>[
        (
          id: 'a1',
          data: <String, dynamic>{
            'ownerID': _from,
            'viceID': 'v1',
            'quantity': 1,
            'createdAt': _at,
            'sealed': await sealed('activities', 'a1', <String, Object?>{
              'triggers': <String>['work/meeting'],
            }),
          },
        ),
      ],
      if (unknown)
        'mystery': <StoredDocument>[
          (id: 'm1', data: <String, dynamic>{'ownerID': _from}),
        ],
    },
    aes256: aes256,
    createdAt: DateTime.utc(2026, 11, 16),
  );
}
