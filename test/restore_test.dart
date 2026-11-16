import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/backup/backup_file.dart';
import 'package:tracker/backup/restore.dart';
import 'package:tracker/crypto/journal_field_sealer.dart';
import 'package:tracker/crypto/journal_key.dart';
import 'package:tracker/crypto/key_service.dart';
import 'package:tracker/crypto/recovery_key.dart';
import 'package:tracker/data/sealed.dart';

import 'fake_sealer.dart';

final AesGcm _aes128 = AesGcm.with128bits();
final AesGcm _aes256 = AesGcm.with256bits();
const String _from = 'old-uid';
const String _to = 'new-uid';
final JournalKey _key = JournalKey(List<int>.filled(32, 7));
final JournalFieldSealer _source = JournalFieldSealer(_key.sealer(_aes256));
final JournalFieldSealer _earlier = JournalFieldSealer(
  JournalKey(List<int>.filled(32, 5)).sealer(_aes256),
);
final FakeSealer _destination = FakeSealer(keyByte: 9);
final Uint8List _recovery = RecoveryKey.generate(Random(5));

Future<Blob> _sealed(
  String collection,
  String id,
  Map<String, Object?> content, {
  JournalFieldSealer? with_,
}) async => Blob(
  await (with_ ?? _source).seal(content, context: sealContext(collection, id)),
);

final Timestamp _at = Timestamp(1700000000, 5000);

Future<Map<String, List<StoredDocument>>> _journal() async =>
    <String, List<StoredDocument>>{
      'activities': <StoredDocument>[
        (
          id: 'a-sealed',
          data: <String, dynamic>{
            'ownerID': _from,
            'viceID': 'v-sealed',
            'quantity': 2,
            'amount': 1.5,
            'createdAt': _at,
            'updatedAt': _at,
            'sealed': await _sealed('activities', 'a-sealed', <String, Object?>{
              'triggers': <String>['work/meeting'],
              'note': 'after the call',
              'futureField': 42,
            }),
          },
        ),
        (
          id: 'a-legacy',
          data: <String, dynamic>{
            'ownerID': _from,
            'viceID': 'v-legacy',
            'quantity': 1,
            'createdAt': _at,
            'triggers': <String>['tired'],
          },
        ),
        (
          id: 'a-orphan',
          data: <String, dynamic>{
            'ownerID': _from,
            'viceID': 'gone',
            'quantity': 1,
            'createdAt': _at,
          },
        ),
        (
          id: 'a-zero',
          data: <String, dynamic>{
            'ownerID': _from,
            'viceID': 'v-legacy',
            'quantity': 0,
            'createdAt': _at,
          },
        ),
        (
          id: 'a-earlier',
          data: <String, dynamic>{
            'ownerID': _from,
            'viceID': 'v-legacy',
            'quantity': 1,
            'createdAt': _at,
            'sealed': await _sealed(
              'activities',
              'a-earlier',
              <String, Object?>{
                'triggers': <String>['x'],
              },
              with_: _earlier,
            ),
          },
        ),
      ],
      'vices': <StoredDocument>[
        (
          id: 'v-sealed',
          data: <String, dynamic>{
            'ownerID': _from,
            'createdAt': _at,
            'archived': true,
            'sealed': await _sealed('vices', 'v-sealed', <String, Object?>{
              'name': 'Wine',
              'unit': 'drink',
              'category': 'alcohol',
              'lineAmount': 2,
            }),
          },
        ),
        (
          id: 'v-legacy',
          data: <String, dynamic>{
            'ownerID': _from,
            'createdAt': _at,
            'name': 'Coffee',
            'unit': 'drink',
            'oldField': 'kept nowhere',
          },
        ),
      ],
      'dayNotes': <StoredDocument>[
        (
          id: '${_from}_2026-11-01',
          data: <String, dynamic>{
            'ownerID': _from,
            'day': '2026-11-01',
            'createdAt': _at,
            'sealed': await _sealed(
              'dayNotes',
              '${_from}_2026-11-01',
              <String, Object?>{'text': 'A long day'},
            ),
          },
        ),
      ],
      'urges': <StoredDocument>[
        (
          id: 'u1',
          data: <String, dynamic>{
            'ownerID': _from,
            'viceID': 'v-sealed',
            'createdAt': _at,
            'sealed': await _sealed('urges', 'u1', <String, Object?>{
              'strength': 4,
            }),
          },
        ),
      ],
      'checkIns': <StoredDocument>[
        (
          id: 'c1',
          data: <String, dynamic>{
            'ownerID': _from,
            'createdAt': _at,
            'sealed': await _sealed('checkIns', 'c1', <String, Object?>{
              'strength': 2,
            }),
          },
        ),
      ],
    };

Future<OpenedBackup> _backup([Map<String, List<StoredDocument>>? j]) async =>
    BackupFile.open(
      await BackupFile.write(
        uid: _from,
        journalKey: _key,
        record: KeyRecord(
          keyID: keyIDOf(_key),
          wrapped: await _key.wrap(
            aes128: _aes128,
            recoveryKey: _recovery,
            uid: _from,
          ),
          createdAt: DateTime.utc(2026),
        ),
        collections: j ?? await _journal(),
        aes256: _aes256,
        createdAt: DateTime.utc(2026, 11, 16),
      ),
      recoveryKey: _recovery,
      aes128: _aes128,
      aes256: _aes256,
    );

Future<RestorePlan> _plan([OpenedBackup? backup]) async => planRestore(
  backup ?? await _backup(),
  destinationUid: _to,
  destination: _destination,
  aes256: _aes256,
);

RestoreWrite _write(RestorePlan plan, String collection, String oldID) {
  final String id = restoredID(
    collection,
    (id: oldID, data: <String, dynamic>{'day': '2026-11-01'}),
    sourceUid: _from,
    destinationUid: _to,
  );
  return plan.writes[collection]!.singleWhere((RestoreWrite w) => w.id == id);
}

Future<Map<String, Object?>> _opened(RestoreWrite w) => _destination.open(
  (w.data['sealed']! as Blob).bytes,
  context: sealContext(w.collection, w.id),
);

class _Target implements RestoreTarget {
  final Map<String, Map<String, Map<String, Object>>> stored =
      <String, Map<String, Map<String, Object>>>{};
  final List<List<RestoreWrite>> batches = <List<RestoreWrite>>[];
  int failOnBatch = -1;

  @override
  Future<Set<String>> ownedIDs(String collection, String uid) async => <String>{
    for (final MapEntry<String, Map<String, Object>>(:key, :value)
        in (stored[collection] ?? const <String, Map<String, Object>>{})
            .entries)
      if (value['ownerID'] == uid) key,
  };

  @override
  Future<void> commit(List<RestoreWrite> writes) async {
    if (batches.length == failOnBatch) {
      failOnBatch = -1;
      throw StateError('connection lost');
    }
    batches.add(writes);
    for (final RestoreWrite w in writes) {
      final Map<String, Map<String, Object>> c = stored.putIfAbsent(
        w.collection,
        () => <String, Map<String, Object>>{},
      );
      expect(c.containsKey(w.id), isFalse, reason: 'written twice: ${w.id}');
      c[w.id] = w.data;
    }
  }
}

void main() {
  test('every collection an account owns can be restored', () {
    expect(restorableCollections, containsAll(Account.ownedCollections));
  });

  test('each document is sealed again for its new path and key', () async {
    final RestorePlan plan = await _plan();

    final RestoreWrite wine = _write(plan, 'vices', 'v-sealed');
    expect(wine.data.keys, <String>{
      'createdAt',
      'archived',
      'ownerID',
      'sealed',
    });
    expect(wine.data['ownerID'], _to);
    expect(wine.data['createdAt'], _at);
    expect(wine.data['archived'], isTrue);
    expect(await _opened(wine), <String, Object?>{
      'name': 'Wine',
      'unit': 'drink',
      'category': 'alcohol',
      'lineAmount': 2,
    });
    // The backup's key never opens the new envelope, nor the old path.
    await expectLater(
      _source.open(
        (wine.data['sealed']! as Blob).bytes,
        context: sealContext('vices', wine.id),
      ),
      throwsA(anything),
    );

    final RestoreWrite coffee = _write(plan, 'vices', 'v-legacy');
    expect(coffee.data['archived'], isFalse);
    expect(await _opened(coffee), <String, Object?>{
      'name': 'Coffee',
      'unit': 'drink',
      'category': 'caffeine',
    });

    final RestoreWrite entry = _write(plan, 'activities', 'a-sealed');
    expect(entry.data.keys, <String>{
      'viceID',
      'quantity',
      'createdAt',
      'amount',
      'ownerID',
      'sealed',
    });
    expect(entry.data['viceID'], wine.id);
    expect(entry.data['quantity'], 2);
    expect(entry.data['amount'], 1.5);
    expect(await _opened(entry), <String, Object?>{
      'triggers': <Object?>['work/meeting'],
      'note': 'after the call',
      'futureField': 42,
    });

    final RestoreWrite legacy = _write(plan, 'activities', 'a-legacy');
    expect(legacy.data['viceID'], coffee.id);
    expect(legacy.data.containsKey('triggers'), isFalse);
    expect(await _opened(legacy), <String, Object?>{
      'triggers': <Object?>['tired'],
    });

    final RestoreWrite note = plan.writes['dayNotes']!.single;
    expect(note.id, '${_to}_2026-11-01');
    expect(note.data.keys, <String>{'day', 'createdAt', 'ownerID', 'sealed'});
    expect(await _opened(note), <String, Object?>{'text': 'A long day'});

    final RestoreWrite urge = plan.writes['urges']!.single;
    expect(urge.data.keys, <String>{
      'viceID',
      'createdAt',
      'ownerID',
      'sealed',
    });
    expect(urge.data['viceID'], wine.id);
    expect(await _opened(urge), <String, Object?>{'strength': 4});

    final RestoreWrite checkIn = plan.writes['checkIns']!.single;
    expect(checkIn.data.keys, <String>{'createdAt', 'ownerID', 'sealed'});
    expect(await _opened(checkIn), <String, Object?>{'strength': 2});

    expect(plan.skipped, <SkipReason, int>{
      SkipReason.habitMissing: 1,
      SkipReason.badAmount: 1,
      SkipReason.earlierKey: 1,
    });
    expect(plan.trimmed, 1);
    expect(plan.total, 7);
  });

  test('ids are new, and the same on every run', () async {
    final RestorePlan first = await _plan();
    final RestorePlan second = await _plan();
    for (final String collection in restorableCollections) {
      expect(first.ids(collection), second.ids(collection));
    }
    expect(first.ids('vices'), isNot(contains('v-sealed')));
    expect(
      first.ids('vices').every(RegExp(r'^[A-Za-z0-9]{20}$').hasMatch),
      isTrue,
    );
    expect(
      restoredID(
        'vices',
        (id: 'v-sealed', data: const <String, dynamic>{}),
        sourceUid: _from,
        destinationUid: 'another',
      ),
      isNot(anyOf(first.ids('vices').toList())),
    );
  });

  test('a habit that cannot be restored takes its entries with it', () async {
    final Map<String, List<StoredDocument>> journal = await _journal();
    journal['vices'] = <StoredDocument>[
      for (final StoredDocument v in journal['vices']!)
        if (v.id == 'v-sealed')
          (
            id: v.id,
            data: <String, dynamic>{
              ...v.data,
              'sealed': await _sealed('vices', v.id, <String, Object?>{
                'name': 'Wine',
              }, with_: _earlier),
            },
          )
        else
          v,
    ];
    final RestorePlan plan = await _plan(await _backup(journal));
    expect(plan.count('vices'), 1);
    expect(plan.count('urges'), 0);
    expect(plan.skipped[SkipReason.earlierKey], 2);
    expect(plan.skipped[SkipReason.habitMissing], 3);
  });

  test('a collection this build does not know refuses the restore', () async {
    final OpenedBackup backup = await _backup(<String, List<StoredDocument>>{
      ...await _journal(),
      'letters': const <StoredDocument>[],
    });
    await expectLater(_plan(backup), throwsA(isA<UnknownCollection>()));
  });

  group('into the account', () {
    test('refuses one that holds other documents', () async {
      final _Target target = _Target()
        ..stored['activities'] = <String, Map<String, Object>>{
          'mine': <String, Object>{'ownerID': _to},
        };
      await expectLater(
        runRestore(await _plan(), target),
        throwsA(
          isA<AccountNotEmpty>().having(
            (AccountNotEmpty e) => e.counts,
            'counts',
            <String, int>{'activities': 1},
          ),
        ),
      );
      expect(target.batches, isEmpty);
    });

    test('writes habits first, entries and urges 20 a batch', () async {
      final Map<String, List<StoredDocument>> journal = await _journal();
      journal['activities'] = <StoredDocument>[
        for (int i = 0; i < 45; i++)
          (
            id: 'bulk$i',
            data: <String, dynamic>{
              'ownerID': _from,
              'viceID': i.isEven ? 'v-sealed' : 'v-legacy',
              'quantity': 1,
              'createdAt': Timestamp(1700000000 + i, 0),
            },
          ),
      ];
      final _Target target = _Target();
      final RestoreResult result = await runRestore(
        await _plan(await _backup(journal)),
        target,
      );
      expect(result.stoppedBy, isNull);
      expect(result.written, <String, int>{
        'vices': 2,
        'activities': 45,
        'dayNotes': 1,
        'urges': 1,
        'checkIns': 1,
      });
      expect(
        target.batches.first.map((RestoreWrite w) => w.collection),
        <String>['vices', 'vices'],
      );
      for (final List<RestoreWrite> batch in target.batches) {
        expect(
          batch.map((RestoreWrite w) => w.collection).toSet(),
          hasLength(1),
        );
        if (batch.first.collection case 'activities' || 'urges') {
          expect(batch.length, lessThanOrEqualTo(20));
        }
      }
    });

    test('a run cut short finishes on the next without duplicates', () async {
      final Map<String, List<StoredDocument>> journal = await _journal();
      journal['activities'] = <StoredDocument>[
        for (int i = 0; i < 50; i++)
          (
            id: 'bulk$i',
            data: <String, dynamic>{
              'ownerID': _from,
              'viceID': 'v-sealed',
              'quantity': 1,
              'createdAt': Timestamp(1700000000 + i, 0),
            },
          ),
      ];
      final RestorePlan plan = await _plan(await _backup(journal));
      final _Target target = _Target()..failOnBatch = 2;

      final RestoreResult first = await runRestore(plan, target);
      expect(first.stoppedBy, isNotNull);
      expect(first.writtenTotal, 22);

      final RestoreResult second = await runRestore(
        await _plan(await _backup(journal)),
        target,
      );
      expect(second.stoppedBy, isNull);
      expect(second.alreadyThere, 22);
      expect(second.writtenTotal, 54 - 22);
      expect(target.stored['activities'], hasLength(50));
      expect(target.stored['vices'], hasLength(2));
    });
  });
}
