// The Firestore types are @sealed, and a mock is the only way to build one
// without a Firestore instance.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tracker/account/export.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/data/habit_line.dart';
import 'package:tracker/data/limits.dart';
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

class _FailingSealer implements FieldSealer {
  @override
  Future<Uint8List> seal(
    Map<String, Object?> fields, {
    required String context,
  }) => Future<Uint8List>.error(StateError('no key'));

  @override
  Future<Map<String, Object?>> open(
    Uint8List envelope, {
    required String context,
  }) => Future<Map<String, Object?>>.error(StateError('no key'));
}

Vice _vice({
  bool locked = false,
  String? unitLabel,
  String? unitSingular,
  double? costPerUnit,
  String? currency,
}) => Vice(
  id: 'coffee',
  name: 'Coffee',
  unit: Unit.drink,
  ownerID: 'owner',
  createdAt: _at,
  archived: false,
  locked: locked,
  unitLabel: unitLabel,
  unitSingular: unitSingular,
  costPerUnit: costPerUnit,
  currency: currency,
);

final Blob _garbage = Blob(Uint8List.fromList(List<int>.filled(40, 9)));

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
    sealedField: Blob(
      await sealer.seal(<String, Object?>{
        'name': 'Coffee',
        'unit': 'drink',
      }, context: 'vices/$id'),
    ),
    'ownerID': 'owner',
    'createdAt': _at,
    'archived': false,
  };

  group('parsers', () {
    test('a sealed vice opens to its unit label and price', () async {
      Future<Vice> open(Map<String, Object?> content) async =>
          (await Vice.openQuerySnapshot(
            _snapshot(<String, Map<String, dynamic>>{
              'coffee': <String, dynamic>{
                sealedField: Blob(
                  await sealer.seal(content, context: 'vices/coffee'),
                ),
                'ownerID': 'owner',
                'createdAt': _at,
                'archived': false,
              },
            }),
            SealedOpener(sealer),
          )).single;

      final Vice priced = await open(<String, Object?>{
        'name': 'Coffee',
        'unit': 'drink',
        'unitLabel': ' cups ',
        'unitSingular': ' cup ',
        'costPerUnit': 3,
        'currency': 'GBP',
      });
      expect(priced.unitLabel, 'cups');
      expect(priced.unitSingular, 'cup');
      expect(priced.units.label(2), '2 cups');
      expect(priced.units.label(1), '1 cup');
      expect(priced.costPerUnit, 3.0);
      expect(priced.currency, 'GBP');
      expect(priced.spendOf(2.5), 7.5);

      // What an older build's reseal leaves: the preset's words, no spend.
      final Vice resealed = await open(<String, Object?>{
        'name': 'Coffee',
        'unit': 'drink',
      });
      expect(resealed.unitLabel, isNull);
      expect(resealed.units.label(1), '1 drink');
      expect(resealed.spendOf(2), isNull);

      final Vice mistyped = await open(<String, Object?>{
        'name': 'Coffee',
        'unitLabel': 'x' * (maxUnitLabelLength + 1),
        'unitSingular': 3,
        'costPerUnit': -1,
        'currency': 'gbp',
      });
      expect(mistyped.unitLabel, isNull);
      expect(mistyped.unitSingular, isNull);
      expect(mistyped.costPerUnit, isNull);
      expect(mistyped.currency, isNull);

      final Vice lined = await open(<String, Object?>{
        'name': 'Wine',
        'unit': 'drink',
        'lineAmount': 2.5,
        'linePeriod': 'day',
      });
      expect(lined.line, const HabitLine(2.5, LinePeriod.day));
      expect(lined.line!.words(lined.units), '2.5 drinks a day');
      expect(resealed.line, isNull);
      // Half a line, or one out of bounds, is no line.
      for (final Map<String, Object?> bad in <Map<String, Object?>>[
        <String, Object?>{'lineAmount': 3},
        <String, Object?>{'linePeriod': 'week'},
        <String, Object?>{'lineAmount': 0, 'linePeriod': 'week'},
        <String, Object?>{'lineAmount': '3', 'linePeriod': 'week'},
        <String, Object?>{'lineAmount': 3, 'linePeriod': 'month'},
        <String, Object?>{'lineAmount': maxLineAmount + 1, 'linePeriod': 'day'},
      ]) {
        expect((await open(bad)).line, isNull, reason: '$bad');
      }
    });

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

    test('a sealed activity keeps its plaintext quantity', () async {
      final List<ViceActivity> activities =
          await ViceActivity.openQuerySnapshot(
            _snapshot(<String, Map<String, dynamic>>{
              'a': <String, dynamic>{
                sealedField: Blob(
                  await sealer.seal(
                    <String, Object?>{},
                    context: 'activities/a',
                  ),
                ),
                'quantity': 3,
                'viceID': 'coffee',
                'ownerID': 'owner',
                'createdAt': _at,
              },
              'b': <String, dynamic>{
                sealedField: _garbage,
                'quantity': 2,
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
      expect(activities.last.quantity, 2);
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
            (stored[sealedField]! as Blob).bytes,
            context: 'vices/${write.id}',
          ),
          <String, Object?>{
            'name': 'Coffee',
            'unit': 'drink',
            'category': 'other',
          },
        );
      },
    );

    test('updateVice reseals the whole content and drops plaintext', () async {
      await writes.updateVice(_vice(), name: 'Espresso').done;
      final Map<Object, Object?> update = store.updates['vices/coffee']!;

      expect(update['name'], FieldValue.delete());
      expect(update['unit'], FieldValue.delete());
      expect(update['category'], FieldValue.delete());
      expect(
        await sealer.open(
          (update[sealedField]! as Blob).bytes,
          context: 'vices/coffee',
        ),
        <String, Object?>{
          'name': 'Espresso',
          'unit': 'drink',
          'category': 'other',
        },
      );
    });

    test('addVice seals a unit label and price', () async {
      final SentWrite write = writes.addVice(
        ownerID: 'owner',
        name: 'Coffee',
        unit: Unit.drink,
        unitAndPrice: (
          unitLabel: 'cups',
          unitSingular: 'cup',
          costPerUnit: 2.5,
          currency: 'GBP',
        ),
      );
      await write.done;
      final Map<String, Object?> stored = store.sets['vices/${write.id}']!;
      expect(
        await sealer.open(
          (stored[sealedField]! as Blob).bytes,
          context: 'vices/${write.id}',
        ),
        <String, Object?>{
          'name': 'Coffee',
          'unit': 'drink',
          'category': 'other',
          'unitLabel': 'cups',
          'unitSingular': 'cup',
          'costPerUnit': 2.5,
          'currency': 'GBP',
        },
      );
    });

    test('updateVice keeps a unit label and price through a rename', () async {
      final Vice priced = _vice(
        unitLabel: 'cups',
        unitSingular: 'cup',
        costPerUnit: 2.5,
        currency: 'GBP',
      );
      await writes.updateVice(priced, name: 'Espresso').done;
      final Map<Object, Object?> update = store.updates['vices/coffee']!;

      for (final String field in viceContentFields) {
        expect(update[field], FieldValue.delete());
      }
      expect(
        await sealer.open(
          (update[sealedField]! as Blob).bytes,
          context: 'vices/coffee',
        ),
        <String, Object?>{
          'name': 'Espresso',
          'unit': 'drink',
          'category': 'other',
          'unitLabel': 'cups',
          'unitSingular': 'cup',
          'costPerUnit': 2.5,
          'currency': 'GBP',
        },
      );

      await writes
          .updateVice(
            priced,
            unitAndPrice: (
              unitLabel: 'cups',
              unitSingular: null,
              costPerUnit: null,
              currency: null,
            ),
          )
          .done;
      expect(
        await sealer.open(
          (store.updates['vices/coffee']![sealedField]! as Blob).bytes,
          context: 'vices/coffee',
        ),
        <String, Object?>{
          'name': 'Coffee',
          'unit': 'drink',
          'category': 'other',
          'unitLabel': 'cups',
        },
      );
    });

    test('updateVice seals a line, keeps it through a rename and clears it '
        'on request', () async {
      Future<Map<String, Object?>> sealed() => sealer.open(
        (store.updates['vices/coffee']![sealedField]! as Blob).bytes,
        context: 'vices/coffee',
      );
      await writes
          .updateVice(
            _vice(),
            line: (line: const HabitLine(30, LinePeriod.week)),
          )
          .done;
      expect(await sealed(), <String, Object?>{
        'name': 'Coffee',
        'unit': 'drink',
        'category': 'other',
        'lineAmount': 30.0,
        'linePeriod': 'week',
      });

      final Vice lined = Vice(
        id: 'coffee',
        name: 'Coffee',
        unit: Unit.drink,
        ownerID: 'owner',
        createdAt: _at,
        archived: false,
        line: const HabitLine(3, LinePeriod.day),
      );
      await writes.updateVice(lined, name: 'Espresso').done;
      expect((await sealed())['lineAmount'], 3.0);
      expect((await sealed())['linePeriod'], 'day');

      await writes.updateVice(lined, line: (line: null)).done;
      expect(await sealed(), isNot(contains('lineAmount')));
      expect(await sealed(), isNot(contains('linePeriod')));
    });

    test('updateVice refuses to write back a locked vice', () {
      expect(
        () => writes.updateVice(_vice(locked: true), name: 'x'),
        throwsStateError,
      );
      expect(store.updates, isEmpty);
    });

    test(
      'a seal that fails is a FirebaseException, and writes nothing',
      () async {
        final TrackerWrites failing = TrackerWrites(
          store.firestore,
          sealer: _FailingSealer(),
        );
        await expectLater(
          failing
              .addVice(ownerID: 'owner', name: 'Coffee', unit: Unit.drink)
              .done,
          throwsA(isA<FirebaseException>()),
        );
        expect(store.sets, isEmpty);
      },
    );

    test('an activity seals its triggers alone', () async {
      await writes
          .recordActivity(
            'a',
            ownerID: 'owner',
            viceID: 'coffee',
            quantity: 2,
            amount: 1.5,
            createdAt: _at.toDate(),
            triggers: const <String>['social'],
          )
          .done;
      final Map<String, Object?> stored = store.sets['activities/a']!;
      expect(stored.keys.toSet(), <String>{
        sealedField,
        'amount',
        'createdAt',
        'ownerID',
        'quantity',
        'viceID',
      });
      expect(stored['quantity'], 2);
      expect(stored['amount'], 1.5);
      expect(
        await sealer.open(
          (stored[sealedField]! as Blob).bytes,
          context: 'activities/a',
        ),
        <String, Object?>{
          'triggers': <Object?>['social'],
        },
      );
    });

    test('an activity without triggers is sealed too', () async {
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
      expect(stored.containsKey('triggers'), isFalse);
      expect(
        await sealer.open(
          (stored[sealedField]! as Blob).bytes,
          context: 'activities/a',
        ),
        <String, Object?>{'triggers': <Object?>[]},
      );
    });

    test('updateActivity reseals only for new triggers', () async {
      final DateTime moved = DateTime(2026, 1, 3);
      await writes.updateActivity('a', quantity: 4, createdAt: moved).done;
      expect(store.updates['activities/a'], <Object, Object?>{
        'createdAt': moved,
        'quantity': 4,
      });

      final SentWrite write = writes.updateActivity(
        'b',
        quantity: 3,
        triggers: const <String>['Long day'],
      );
      await write.done;
      final Map<Object, Object?> update = store.updates['activities/b']!;
      expect(update['quantity'], 3);
      expect(update['triggers'], FieldValue.delete());
      expect(write.fields, <String, Object>{'quantity': 3});
      expect(
        await sealer.open(
          (update[sealedField]! as Blob).bytes,
          context: 'activities/b',
        ),
        <String, Object?>{
          'triggers': <Object?>['Long day'],
        },
      );
    });

    test(
      'a sealed activity parses its triggers, or none when locked',
      () async {
        final Map<String, dynamic> json = <String, dynamic>{
          'viceID': 'coffee',
          'quantity': 2,
          'ownerID': 'owner',
          'createdAt': _at,
          sealedField: Blob(
            await sealer.seal(<String, Object?>{
              'triggers': <String>['social'],
            }, context: 'activities/a'),
          ),
        };
        final ViceActivity opened = ViceActivity.fromJson(
          id: 'a',
          json: json,
          opened: await SealedOpener(sealer).open('activities', 'a', json),
        );
        expect(opened.triggers, <String>['social']);
        expect(opened.quantity, 2);
        expect(opened.locked, isFalse);

        final ViceActivity locked = ViceActivity.fromJson(
          id: 'x',
          json: json,
          opened: await SealedOpener(sealer).open('activities', 'x', json),
        );
        expect(locked.locked, isTrue);
        expect(locked.triggers, isEmpty);
        expect(locked.quantity, 2);
      },
    );
  });

  test(
    'without a sealer nothing is created and updates stay plaintext',
    () async {
      final _Store store = _Store();
      final TrackerWrites writes = TrackerWrites(store.firestore);
      expect(writes.canCreate, isFalse);
      expect(
        () =>
            writes.addVice(ownerID: 'owner', name: 'Coffee', unit: Unit.drink),
        throwsStateError,
      );
      expect(
        () => writes.recordActivity(
          'a',
          ownerID: 'owner',
          viceID: 'coffee',
          quantity: 1,
          createdAt: _at.toDate(),
          triggers: <String>['social'],
        ),
        throwsStateError,
      );
      expect(
        () => writes.updateVice(
          _vice(),
          unitAndPrice: (
            unitLabel: 'cups',
            unitSingular: null,
            costPerUnit: null,
            currency: null,
          ),
        ),
        throwsStateError,
      );
      await writes
          .updateVice(_vice(), name: 'Espresso', unitAndPrice: noUnitAndPrice)
          .done;

      expect(store.sets, isEmpty);
      expect(store.updates['vices/coffee'], <Object, Object?>{
        'name': 'Espresso',
      });
    },
  );

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
      sealedField: _garbage,
    };
    expect(
      unsealed(locked, await SealedOpener(sealer).open('vices', 'x', locked)),
      locked,
    );
  });
}
