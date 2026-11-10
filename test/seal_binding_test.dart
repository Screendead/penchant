// The Firestore types are @sealed, and a mock is the only way to build one
// without a Firestore instance.
// ignore_for_file: subtype_of_sealed_class

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tracker/crypto/sealer.dart';
import 'package:tracker/data/activity_triggers.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/writes/tracker_writes.dart';

import 'fake_sealer.dart';

class _Firestore extends Mock implements FirebaseFirestore {}

class _Collection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _DocRef extends Mock implements DocumentReference<Map<String, dynamic>> {}

const String _id = 'a';
final DateTime _at = DateTime.utc(2026, 11, 10, 8, 30, 15, 123, 456);

// One activity document as the server would hold it: a create sets it, an
// update merges into it.
class _Server {
  _Server() {
    final _Collection activities = _Collection();
    final _DocRef doc = _DocRef();
    when(() => activities.id).thenReturn('activities');
    when(() => activities.doc(_id)).thenReturn(doc);
    when(() => doc.id).thenReturn(_id);
    when(() => doc.parent).thenReturn(activities);
    when(() => doc.set(any())).thenAnswer((Invocation call) async {
      stored = _asStored(
        call.positionalArguments.first as Map<Object, Object?>,
      );
    });
    when(() => doc.update(any())).thenAnswer((Invocation call) async {
      final Map<String, dynamic> next = <String, dynamic>{...stored};
      for (final MapEntry<String, dynamic>(:key, :value) in _asStored(
        call.positionalArguments.first as Map<Object, Object?>,
        keepDeletes: true,
      ).entries) {
        if (value == FieldValue.delete()) {
          next.remove(key);
        } else {
          next[key] = value;
        }
      }
      stored = next;
    });
    when(() => firestore.collection('activities')).thenReturn(activities);
  }

  final _Firestore firestore = _Firestore();
  Map<String, dynamic> stored = <String, dynamic>{};

  static Map<String, dynamic> _asStored(
    Map<Object, Object?> written, {
    bool keepDeletes = false,
  }) => <String, dynamic>{
    for (final MapEntry<Object, Object?>(:key, :value) in written.entries)
      if (keepDeletes || value != FieldValue.delete())
        key as String: value is DateTime ? Timestamp.fromDate(value) : value,
  };
}

void main() {
  late _Server server;
  late FakeSealer sealer;
  late TrackerWrites writes;

  setUp(() {
    server = _Server();
    sealer = FakeSealer();
    writes = TrackerWrites(
      server.firestore,
      sealer: sealer,
      bindActivities: true,
    );
  });

  Future<ViceActivity> read([Map<String, dynamic>? doc]) async {
    final Map<String, dynamic> json = doc ?? server.stored;
    return ViceActivity.fromJson(
      id: _id,
      json: json,
      opened: await SealedOpener(sealer).open('activities', _id, json),
    );
  }

  Future<void> record({
    double? amount,
    List<String> triggers = const <String>[],
  }) => writes
      .recordActivity(
        _id,
        ownerID: 'owner',
        viceID: 'coffee',
        quantity: 2,
        amount: amount,
        createdAt: _at,
        triggers: triggers,
      )
      .done;

  test('a recorded entry reads back intact, triggers and all', () async {
    await record(amount: 1.5, triggers: const <String>['work/meeting']);
    final ViceActivity activity = await read();
    expect(activity.binding, SealBinding.intact);
    expect(activity.locked, isFalse);
    expect(activity.triggers, <String>['work/meeting']);
  });

  test('an entry with no triggers stays in the smallest bucket', () async {
    await record(amount: 1.5);
    expect(
      (server.stored[sealedField]! as Blob).bytes.length,
      Sealer.overhead + Sealer.buckets.first,
    );
  });

  group('a change made beside the envelope is altered:', () {
    final Map<String, Object?> changes = <String, Object?>{
      'createdAt': Timestamp.fromDate(_at.add(const Duration(days: -3))),
      'quantity': 9,
      'amount': 2.0,
      'viceID': 'wine',
    };
    for (final MapEntry<String, Object?>(:key, :value) in changes.entries) {
      test(key, () async {
        await record(amount: 1.5, triggers: const <String>['social']);
        final ViceActivity activity = await read(<String, dynamic>{
          ...server.stored,
          key: value,
        });
        expect(activity.binding, SealBinding.altered);
        expect(activity.locked, isFalse);
        expect(activity.triggers, <String>['social']);
      });
    }

    test('a removed amount', () async {
      await record(amount: 1.5);
      expect(
        (await read(<String, dynamic>{...server.stored}..remove('amount')))
            .binding,
        SealBinding.altered,
      );
    });
  });

  test(
    'an edit that passes the entry it read reseals, and stays intact',
    () async {
      await record(triggers: const <String>['social']);
      final DateTime moved = _at.add(const Duration(hours: 2));
      await writes
          .updateActivity(
            _id,
            createdAt: moved,
            quantity: 3,
            current: await read(),
          )
          .done;
      final ViceActivity edited = await read();
      expect(edited.binding, SealBinding.intact);
      expect(edited.createdAt, Timestamp.fromDate(moved));
      expect(edited.quantity, 3);
      expect(edited.triggers, <String>['social']);
    },
  );

  test('new triggers on a bound entry keep it bound', () async {
    await record();
    await writes
        .updateActivity(
          _id,
          triggers: const <String>['Long day'],
          current: await read(),
        )
        .done;
    final ViceActivity edited = await read();
    expect(edited.binding, SealBinding.intact);
    expect(edited.triggers, <String>['Long day']);
  });

  test('an export carries the triggers and not the binding', () async {
    await record(triggers: const <String>['social']);
    final Map<String, dynamic> exported = unsealed(
      server.stored,
      await SealedOpener(sealer).open('activities', _id, server.stored),
    );
    expect(exported[triggersField], <Object?>['social']);
    expect(exported.keys, isNot(contains(boundField)));
    expect(exported.keys, isNot(contains(sealedField)));
  });

  // The limits of the scheme, pinned so that a change to them is noticed.
  group('not detected, or falsely detected:', () {
    test('an envelope sealed before binding is unbound, whatever sits '
        'beside it', () async {
      final TrackerWrites before = TrackerWrites(
        server.firestore,
        sealer: sealer,
      );
      await before
          .recordActivity(
            _id,
            ownerID: 'owner',
            viceID: 'coffee',
            quantity: 2,
            createdAt: _at,
          )
          .done;
      expect((await read()).binding, SealBinding.unbound);
      expect(
        (await read(<String, dynamic>{...server.stored, 'quantity': 9}))
            .binding,
        SealBinding.unbound,
      );
    });

    test('an older build still opens a bound envelope', () async {
      await record(triggers: const <String>['social']);
      final Map<String, Object?> opened = await sealer.open(
        (server.stored[sealedField]! as Blob).bytes,
        context: 'activities/$_id',
      );
      expect(opened[triggersField], <Object?>['social']);
      expect(opened.keys, contains(boundField));
    });

    test('a time edit by an older build, which never reseals, reads as '
        'altered', () async {
      await record();
      final TrackerWrites older = TrackerWrites(
        server.firestore,
        sealer: sealer,
      );
      await older.updateActivity(_id, quantity: 4).done;
      expect((await read()).binding, SealBinding.altered);
    });

    test('new triggers from an older build strip the binding', () async {
      await record();
      final TrackerWrites older = TrackerWrites(
        server.firestore,
        sealer: sealer,
      );
      await older.updateActivity(_id, triggers: const <String>['x']).done;
      expect((await read()).binding, SealBinding.unbound);
    });

    test('two devices editing different fields of one entry read as '
        'altered', () async {
      await record();
      final ViceActivity stale = await read();
      await writes
          .updateActivity(
            _id,
            createdAt: _at.add(const Duration(hours: 2)),
            current: stale,
          )
          .done;
      await writes.updateActivity(_id, quantity: 3, current: stale).done;
      expect((await read()).binding, SealBinding.altered);
    });

    test('rolling the whole document back to an earlier state reads as '
        'intact', () async {
      await record(triggers: const <String>['social']);
      final Map<String, dynamic> earlier = <String, dynamic>{...server.stored};
      await writes
          .updateActivity(
            _id,
            createdAt: _at.add(const Duration(hours: 2)),
            triggers: const <String>[],
            current: await read(),
          )
          .done;
      expect(server.stored[sealedField], isNot(earlier[sealedField]));
      final ViceActivity rolledBack = await read(earlier);
      expect(rolledBack.binding, SealBinding.intact);
      expect(rolledBack.triggers, <String>['social']);
    });

    test('putting back the envelope from before binding, with any fields '
        'beside it, reads as unbound', () async {
      final TrackerWrites before = TrackerWrites(
        server.firestore,
        sealer: sealer,
      );
      await before
          .recordActivity(
            _id,
            ownerID: 'owner',
            viceID: 'coffee',
            quantity: 2,
            createdAt: _at,
          )
          .done;
      final Object? unboundEnvelope = server.stored[sealedField];
      await writes.updateActivity(_id, quantity: 2, current: await read()).done;
      expect((await read()).binding, SealBinding.intact);
      expect(
        (await read(<String, dynamic>{
          ...server.stored,
          sealedField: unboundEnvelope,
          'quantity': 9,
        })).binding,
        SealBinding.unbound,
      );
    });

    test('an entry forged with an envelope that will not open is locked, '
        'not altered', () async {
      final ViceActivity forged = await read(<String, dynamic>{
        'ownerID': 'owner',
        'viceID': 'coffee',
        'quantity': 40,
        'createdAt': Timestamp.fromDate(_at),
        sealedField: Blob(Uint8List.fromList(List<int>.filled(93, 9))),
      });
      expect(forged.locked, isTrue);
      expect(forged.binding, SealBinding.unbound);
      expect(forged.quantity, 40);
    });
  });
}
