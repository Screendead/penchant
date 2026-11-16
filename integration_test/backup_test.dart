import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/backup/backup_file.dart';
import 'package:tracker/backup/backup_service.dart';
import 'package:tracker/backup/restore.dart';
import 'package:tracker/crypto/journal_field_sealer.dart';
import 'package:tracker/crypto/journal_key.dart';
import 'package:tracker/crypto/key_service.dart';
import 'package:tracker/crypto/recovery_key.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/data/updated_at.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/writes/queued_write_journal.dart';

import '../test/fake_sealer.dart';
import 'support.dart';

// A backup that has never been restored is not a backup: this saves one from
// a journal on the emulators, restores it into a new account through the
// rules as that account's client, and compares every document.
//
// Dart's AES-GCM, not CryptoKit: the same envelope, without the keychain.
final BackupCiphers _ciphers = BackupCiphers(
  aes128: AesGcm.with128bits(),
  aes256: AesGcm.with256bits(),
);

// The source journal's key, the bytes e2eSealer uses; the new account seals
// with another, so a key mix-up cannot pass.
final JournalKey _sourceKey = JournalKey(List<int>.filled(32, 7));
final JournalFieldSealer _source = JournalFieldSealer(
  _sourceKey.sealer(_ciphers.aes256),
);
final FakeSealer _destination = FakeSealer(keyByte: 9);
final Uint8List _recovery = RecoveryKey.generate(Random(24));

Account _account() => Account(
  FirebaseAuth.instance,
  FirebaseFirestore.instance,
  QueuedWriteJournal(MemoryJournalStore()),
);

// Every owned document of the signed-in user, content opened with [sealer]
// at its own path, with its plaintext fields beside it.
Future<Map<String, List<Map<String, Object?>>>> _opened(
  FieldSealer sealer,
) async {
  final String uid = FirebaseAuth.instance.currentUser!.uid;
  final Map<String, List<Map<String, Object?>>> out =
      <String, List<Map<String, Object?>>>{};
  for (final String collection in Account.ownedCollections) {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await FirebaseFirestore
        .instance
        .collection(collection)
        .where('ownerID', isEqualTo: uid)
        .get(const GetOptions(source: Source.server));
    out[collection] = <Map<String, Object?>>[
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs)
        <String, Object?>{
          for (final MapEntry<String, dynamic>(:key, :value)
              in doc.data().entries)
            if (key != sealedField && key != updatedAtField) key: value,
          if (doc.data()[sealedField] case final Blob envelope)
            ...await sealer.open(
              envelope.bytes,
              context: sealContext(collection, doc.id),
            ),
          'id': doc.id,
        },
    ];
  }
  return out;
}

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('a saved backup restores into a new account', (
    WidgetTester tester,
  ) async {
    final FirebaseFirestore db = FirebaseFirestore.instance;
    final String from =
        (await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: 'e2e-backup-from@example.com',
          password: 'e2e-password',
        )).user!.uid;
    final Timestamp at = Timestamp(1763290000, 123000);

    // Sealed documents written through the rules, as the app writes them.
    final DocumentReference<Map<String, dynamic>> wine = db
        .collection('vices')
        .doc();
    await wine.set(<String, Object>{
      'ownerID': from,
      'createdAt': at,
      'archived': false,
      sealedField: Blob(
        await _source.seal(<String, Object?>{
          'name': 'Wine',
          'unit': 'drink',
          'category': 'alcohol',
          'lineAmount': 2,
          'linePeriod': 'day',
        }, context: sealContext('vices', wine.id)),
      ),
    });
    final DocumentReference<Map<String, dynamic>> glass = db
        .collection('activities')
        .doc();
    await glass.set(<String, Object>{
      'ownerID': from,
      'viceID': wine.id,
      'quantity': 2,
      'amount': 1.5,
      'createdAt': at,
      ...updatedNow,
      sealedField: Blob(
        await _source.seal(<String, Object?>{
          'triggers': <String>['social/party', 'own words'],
          'urge': 3,
          'note': 'a birthday',
        }, context: sealContext('activities', glass.id)),
      ),
    });
    final String noteID = '${from}_2026-11-01';
    await db.collection('dayNotes').doc(noteID).set(<String, Object>{
      'ownerID': from,
      'day': '2026-11-01',
      'createdAt': at,
      ...updatedNow,
      sealedField: Blob(
        await _source.seal(<String, Object?>{
          'text': 'A long day',
          'triggers': <String>['work'],
        }, context: sealContext('dayNotes', noteID)),
      ),
    });
    final DocumentReference<Map<String, dynamic>> urge = db
        .collection('urges')
        .doc();
    await urge.set(<String, Object>{
      'ownerID': from,
      'viceID': wine.id,
      'createdAt': at,
      sealedField: Blob(
        await _source.seal(<String, Object?>{
          'strength': 4,
          'zone': 'Europe/London',
        }, context: sealContext('urges', urge.id)),
      ),
    });

    // Legacy plaintext, which the rules no longer take from a client.
    Map<String, Object> text(String value) => <String, Object>{
      'stringValue': value,
    };
    final Map<String, Object> when = <String, Object>{
      'timestampValue': at.toDate().toUtc().toIso8601String(),
    };
    final String coffee = db.collection('vices').doc().id;
    await createBypassingRules('vices', coffee, <String, Object>{
      'name': text('Coffee'),
      'unit': text('drink'),
      'ownerID': text(from),
      'createdAt': when,
    });
    final String cup = db.collection('activities').doc().id;
    await createBypassingRules('activities', cup, <String, Object>{
      'viceID': text(coffee),
      'quantity': <String, Object>{'integerValue': '1'},
      'ownerID': text(from),
      'createdAt': when,
      'triggers': <String, Object>{
        'arrayValue': <String, Object>{
          'values': <Object>[text('tired')],
        },
      },
    });

    // The source key's server record, as the key service would publish it.
    final KeyRecord record = KeyRecord(
      keyID: keyIDOf(_sourceKey),
      wrapped: await _sourceKey.wrap(
        aes128: _ciphers.aes128,
        recoveryKey: _recovery,
        uid: from,
      ),
      createdAt: DateTime.utc(2026, 11, 1),
    );
    final Map<String, List<Map<String, Object?>>> before = await _opened(
      _source,
    );
    final Uint8List file = await makeBackup(
      account: _account(),
      key: BackupKey(
        uid: from,
        journalKey: _sourceKey,
        record: record,
        recoveryKey: _recovery,
      ),
      ciphers: _ciphers,
      now: DateTime.now(),
    );

    await FirebaseAuth.instance.signOut();
    final String to =
        (await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: 'e2e-backup-to@example.com',
          password: 'e2e-password',
        )).user!.uid;

    final OpenedBackup backup = await BackupFile.open(
      file,
      recoveryKey: _recovery,
      aes128: _ciphers.aes128,
      aes256: _ciphers.aes256,
    );
    final RestorePlan plan = await planRestore(
      backup,
      destinationUid: to,
      destination: _destination,
      aes256: _ciphers.aes256,
    );
    expect(plan.skipped, isEmpty);
    final FirestoreRestoreTarget target = FirestoreRestoreTarget(db);
    final RestoreResult result = await runRestore(plan, target);
    expect(result.stoppedBy, isNull);
    expect(result.written, <String, int>{
      'vices': 2,
      'activities': 2,
      'dayNotes': 1,
      'urges': 1,
    });

    // A second run finds everything there and writes nothing.
    final RestoreResult again = await runRestore(plan, target);
    expect(again.writtenTotal, 0);
    expect(again.alreadyThere, 6);

    final Map<String, List<Map<String, Object?>>> after = await _opened(
      _destination,
    );
    // Each restored document matched to its original by its new id.
    String newID(String collection, Map<String, Object?> doc) => restoredID(
      collection,
      (id: doc['id']! as String, data: <String, dynamic>{'day': doc['day']}),
      sourceUid: from,
      destinationUid: to,
    );
    final Map<String, String> viceIDs = <String, String>{
      for (final Map<String, Object?> v in before['vices']!)
        v['id']! as String: newID('vices', v),
    };
    for (final String collection in Account.ownedCollections) {
      expect(
        after[collection],
        hasLength(before[collection]!.length),
        reason: collection,
      );
      for (final Map<String, Object?> original in before[collection]!) {
        final String id = newID(collection, original);
        final Map<String, Object?> restored = after[collection]!.singleWhere(
          (Map<String, Object?> d) => d['id'] == id,
        );
        final Map<String, Object?> expected = <String, Object?>{
          ...original,
          'id': id,
          'ownerID': to,
          if (original['viceID'] case final String viceID)
            'viceID': viceIDs[viceID],
          if (collection == 'vices') 'archived': original['archived'] ?? false,
          if (collection == 'vices' && !original.containsKey('category'))
            'category': 'caffeine',
        };
        expect(restored, expected, reason: '$collection ${original['id']}');
      }
    }

    // Restoring into an account that already holds a journal is refused,
    // with nothing written.
    await expectLater(
      runRestore(
        await planRestore(
          backup,
          destinationUid: to,
          destination: _destination,
          aes256: _ciphers.aes256,
        ).then(
          (RestorePlan p) => RestorePlan(
            sourceUid: 'another-backup',
            destinationUid: to,
            writes: <String, List<RestoreWrite>>{
              'vices': <RestoreWrite>[
                RestoreWrite('vices', 'x' * 20, p.writes['vices']!.first.data),
              ],
            },
            skipped: const <SkipReason, int>{},
            trimmed: 0,
          ),
        ),
        target,
      ),
      throwsA(isA<AccountNotEmpty>()),
    );
    expect(await existsBypassingRules('vices', 'x' * 20), isFalse);
  });
}
