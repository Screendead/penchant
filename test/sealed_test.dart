// The Firestore types are @sealed, and a mock is the only way to build one
// without a Firestore instance.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tracker/account/export.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/writes/tracker_writes.dart';

import 'fake_sealer.dart';

class _Firestore extends Mock implements FirebaseFirestore {}

class _Collection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _DocRef extends Mock implements DocumentReference<Map<String, dynamic>> {}

class _Metadata extends Mock implements SnapshotMetadata {}

class _Doc extends Mock
    implements QueryDocumentSnapshot<Map<String, dynamic>> {}

class _Query extends Mock implements QuerySnapshot<Map<String, dynamic>> {}

final Timestamp _at = Timestamp.fromMillisecondsSinceEpoch(1700000000000);

QuerySnapshot<Map<String, dynamic>> _snapshot(
  Map<String, Map<String, dynamic>> docs,
) {
  final _Query query = _Query();
  final List<_Doc> mocks = <_Doc>[];
  for (final MapEntry<String, Map<String, dynamic>>(:key, :value)
      in docs.entries) {
    final _Metadata metadata = _Metadata();
    when(() => metadata.hasPendingWrites).thenReturn(false);
    final _Doc doc = _Doc();
    when(() => doc.id).thenReturn(key);
    when(() => doc.data()).thenReturn(value);
    when(() => doc.metadata).thenReturn(metadata);
    mocks.add(doc);
  }
  when(() => query.docs).thenReturn(mocks);
  return query;
}

// Records each set and update the writes make, per document path.
class _Store {
  _Store() {
    for (final String name in <String>['vices', 'activities']) {
      final _Collection collection = _Collection();
      when(() => collection.id).thenReturn(name);
      for (final String id in <String>['coffee', 'a', 'b']) {
        final _DocRef doc = _doc(collection, id);
        when(() => collection.doc(id)).thenReturn(doc);
      }
      final _DocRef created = _doc(collection, '$name-new');
      when(() => collection.doc()).thenReturn(created);
      when(() => firestore.collection(name)).thenReturn(collection);
    }
  }

  final _Firestore firestore = _Firestore();
  final Map<String, Map<String, Object?>> sets =
      <String, Map<String, Object?>>{};
  final Map<String, Map<Object, Object?>> updates =
      <String, Map<Object, Object?>>{};

  _DocRef _doc(_Collection collection, String id) {
    final _DocRef doc = _DocRef();
    final String path = '${collection.id}/$id';
    when(() => doc.id).thenReturn(id);
    when(() => doc.parent).thenReturn(collection);
    when(() => doc.set(any())).thenAnswer((Invocation call) async {
      sets[path] = call.positionalArguments.first as Map<String, Object?>;
    });
    when(() => doc.update(any())).thenAnswer((Invocation call) async {
      updates[path] = call.positionalArguments.first as Map<Object, Object?>;
    });
    return doc;
  }
}

Vice _vice({bool locked = false}) => Vice(
  id: 'coffee',
  name: 'Coffee',
  unit: Unit.drink,
  ownerID: 'owner',
  createdAt: _at,
  archived: false,
  locked: locked,
);

void main() {
  late FakeSealer sealer;
  late List<String> printed;
  DebugPrintCallback? originalPrint;

  setUp(() {
    sealer = FakeSealer();
    printed = <String>[];
    originalPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => printed.add('$message');
  });

  tearDown(() => debugPrint = originalPrint!);

  Future<Map<String, dynamic>> sealedVice(String id) async => <String, dynamic>{
    sealedField: await sealer.seal(<String, Object?>{
      'name': 'Coffee',
      'unit': 'drink',
    }, context: 'vices/$id'),
    'ownerID': 'owner',
    'createdAt': _at,
    'archived': false,
  };

  group('parsers', () {
    test('a sealed vice opens to its name and unit', () async {
      final List<Vice> vices = await Vice.openQuerySnapshot(
        _snapshot(<String, Map<String, dynamic>>{
          'coffee': await sealedVice('coffee'),
        }),
        SealedOpener(sealer),
      );
      expect(vices.single.name, 'Coffee');
      expect(vices.single.unit, Unit.drink);
      expect(vices.single.locked, isFalse);
      expect(vices.single.ownerID, 'owner');
    });

    test(
      'a plaintext vice reads as before, without opening anything',
      () async {
        final List<Vice> vices = await Vice.openQuerySnapshot(
          _snapshot(<String, Map<String, dynamic>>{
            'tea': <String, dynamic>{
              'name': 'Tea',
              'unit': 'drink',
              'ownerID': 'owner',
              'createdAt': _at,
            },
          }),
          SealedOpener(sealer),
        );
        expect(vices.single.name, 'Tea');
        expect(vices.single.locked, isFalse);
        expect(sealer.opened, isEmpty);
      },
    );

    test(
      'a vice that will not open is a locked placeholder, reported once',
      () async {
        final SealedOpener opener = SealedOpener(sealer);
        // Sealed for another document, so the context check refuses it.
        final QuerySnapshot<Map<String, dynamic>> snapshot = _snapshot(
          <String, Map<String, dynamic>>{'coffee': await sealedVice('other')},
        );
        final Vice first = (await Vice.openQuerySnapshot(
          snapshot,
          opener,
        )).single;
        await Vice.openQuerySnapshot(snapshot, opener);

        expect(first.locked, isTrue);
        expect(first.name, lockedViceName);
        expect(first.unit, Unit.item);
        expect(first.archived, isFalse);
        expect(
          printed.where((String line) => line.contains('vices/coffee')),
          hasLength(1),
        );
      },
    );

    test(
      'without a key every sealed document is locked, and none throws',
      () async {
        final List<Vice> vices = await Vice.openQuerySnapshot(
          _snapshot(<String, Map<String, dynamic>>{
            'coffee': await sealedVice('coffee'),
            'bad': <String, dynamic>{sealedField: 42, 'ownerID': 'owner'},
          }),
          SealedOpener(null),
        );
        expect(vices.map((Vice vice) => vice.locked), <bool>[true, true]);
      },
    );

    test('a sealed activity opens to its quantity', () async {
      final List<ViceActivity> activities =
          await ViceActivity.openQuerySnapshot(
            _snapshot(<String, Map<String, dynamic>>{
              'a': <String, dynamic>{
                sealedField: await sealer.seal(<String, Object?>{
                  'quantity': 3,
                }, context: 'activities/a'),
                'viceID': 'coffee',
                'ownerID': 'owner',
                'createdAt': _at,
              },
              'b': <String, dynamic>{
                sealedField: 'garbage',
                'viceID': 'coffee',
                'ownerID': 'owner',
                'createdAt': _at,
              },
            }),
            SealedOpener(sealer),
          );
      expect(activities.first.quantity, 3);
      expect(activities.first.locked, isFalse);
      expect(activities.first.viceID, 'coffee');
      expect(activities.last.locked, isTrue);
      expect(activities.last.quantity, 0);
      expect(activities.last.createdAt, _at);
    });
  });

  group('TrackerWrites with a sealer', () {
    late _Store store;
    late TrackerWrites writes;

    setUp(() {
      store = _Store();
      writes = TrackerWrites(store.firestore, sealer: sealer);
    });

    test(
      'addVice stores only the envelope and the structural fields',
      () async {
        final SentWrite write = writes.addVice(
          ownerID: 'owner',
          name: 'Coffee',
          unit: Unit.drink,
        );
        await write.done;
        final Map<String, Object?> stored = store.sets['vices/${write.id}']!;

        expect(stored.keys.toSet(), <String>{
          sealedField,
          'ownerID',
          'createdAt',
          'archived',
        });
        expect(stored[sealedField].toString(), isNot(contains('Coffee')));
        expect(
          await sealer.open(
            stored[sealedField]! as String,
            context: 'vices/${write.id}',
          ),
          <String, Object?>{'name': 'Coffee', 'unit': 'drink'},
        );
      },
    );

    test('updateVice reseals the whole content and drops plaintext', () async {
      await writes.updateVice(_vice(), name: 'Espresso').done;
      final Map<Object, Object?> update = store.updates['vices/coffee']!;

      expect(update['name'], FieldValue.delete());
      expect(update['unit'], FieldValue.delete());
      expect(
        await sealer.open(
          update[sealedField]! as String,
          context: 'vices/coffee',
        ),
        <String, Object?>{'name': 'Espresso', 'unit': 'drink'},
      );
    });

    test('updateVice refuses to write back a locked vice', () {
      expect(
        () => writes.updateVice(_vice(locked: true), name: 'x'),
        throwsStateError,
      );
      expect(store.updates, isEmpty);
    });

    test('recordActivity seals the quantity', () async {
      await writes
          .recordActivity(
            'a',
            ownerID: 'owner',
            viceID: 'coffee',
            quantity: 2,
            createdAt: _at.toDate(),
          )
          .done;
      final Map<String, Object?> stored = store.sets['activities/a']!;

      expect(stored.keys.toSet(), <String>{
        sealedField,
        'ownerID',
        'viceID',
        'createdAt',
      });
      expect(
        await sealer.open(
          stored[sealedField]! as String,
          context: 'activities/a',
        ),
        <String, Object?>{'quantity': 2},
      );
    });

    test(
      'updateActivity reseals a quantity, and leaves a date plaintext',
      () async {
        final DateTime moved = DateTime(2026, 1, 3);
        final SentWrite write = writes.updateActivity(
          'a',
          quantity: 4,
          createdAt: moved,
        );
        await write.done;
        final Map<Object, Object?> update = store.updates['activities/a']!;

        expect(update['quantity'], FieldValue.delete());
        expect(update['createdAt'], moved);
        expect(
          await sealer.open(
            update[sealedField]! as String,
            context: 'activities/a',
          ),
          <String, Object?>{'quantity': 4},
        );
        expect(write.fields, <String, Object>{
          'createdAt': moved.microsecondsSinceEpoch,
        });

        await writes.updateActivity('b', createdAt: moved).done;
        expect(store.updates['activities/b'], <Object, Object?>{
          'createdAt': moved,
        });
      },
    );
  });

  test('without a sealer the writes stay plaintext', () async {
    final _Store store = _Store();
    final TrackerWrites writes = TrackerWrites(store.firestore);
    final SentWrite write = writes.addVice(
      ownerID: 'owner',
      name: 'Coffee',
      unit: Unit.drink,
    );
    await write.done;
    await writes.updateVice(_vice(), name: 'Espresso').done;

    expect(store.sets['vices/${write.id}']!['name'], 'Coffee');
    expect(store.sets['vices/${write.id}']!.containsKey(sealedField), isFalse);
    expect(store.updates['vices/coffee'], <Object, Object?>{
      'name': 'Espresso',
    });
  });

  test('the export carries opened fields in place of the envelope', () async {
    final Map<String, dynamic> stored = await sealedVice('coffee');
    final Map<String, dynamic> exported = unsealed(
      stored,
      await SealedOpener(sealer).open('vices', 'coffee', stored),
    );
    expect(exported.containsKey(sealedField), isFalse);
    expect(exported['name'], 'Coffee');

    final String csv = exportCsv(
      AccountData(
        vices: <StoredDocument>[(id: 'coffee', data: exported)],
        activities: <StoredDocument>[
          (
            id: 'a',
            data: <String, dynamic>{
              'viceID': 'coffee',
              'quantity': 2,
              'createdAt': _at,
            },
          ),
        ],
      ),
    );
    expect(csv, contains('Coffee'));

    final Map<String, dynamic> locked = <String, dynamic>{
      ...stored,
      sealedField: 'garbage',
    };
    expect(
      unsealed(locked, await SealedOpener(sealer).open('vices', 'x', locked)),
      locked,
    );
  });
}
