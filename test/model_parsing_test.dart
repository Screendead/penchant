// QuerySnapshot and QueryDocumentSnapshot are @sealed, and a mock is the only
// way to build one without a Firestore instance.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';

class _Metadata extends Mock implements SnapshotMetadata {}

class _Doc extends Mock
    implements QueryDocumentSnapshot<Map<String, dynamic>> {}

class _Query extends Mock implements QuerySnapshot<Map<String, dynamic>> {}

QuerySnapshot<Map<String, dynamic>> _snapshot(
  List<(String, Map<String, dynamic>, bool)> docs,
) {
  final _Query query = _Query();
  final List<_Doc> mocks = <_Doc>[
    for (final (String id, Map<String, dynamic> data, bool pending) in docs)
      () {
        final _Metadata metadata = _Metadata();
        when(() => metadata.hasPendingWrites).thenReturn(pending);
        final _Doc doc = _Doc();
        when(() => doc.id).thenReturn(id);
        when(() => doc.data()).thenReturn(data);
        when(() => doc.metadata).thenReturn(metadata);
        return doc;
      }(),
  ];
  when(() => query.docs).thenReturn(mocks);
  return query;
}

final Timestamp _at = Timestamp.fromMillisecondsSinceEpoch(1700000000000);
final Timestamp _epoch = Timestamp(0, 0);

Map<String, dynamic> _vice() => <String, dynamic>{
  'name': 'Coffee',
  'unit': 'drink',
  'ownerID': 'owner',
  'createdAt': _at,
  'archived': true,
};

Map<String, dynamic> _activity() => <String, dynamic>{
  'viceID': 'vice',
  'quantity': 3,
  'ownerID': 'owner',
  'createdAt': _at,
};

Map<String, dynamic> _with(
  Map<String, dynamic> json,
  String field,
  Object? value,
) => <String, dynamic>{...json, field: value};

Map<String, dynamic> _without(Map<String, dynamic> json, String field) =>
    <String, dynamic>{...json}..remove(field);

void expectRecent(Timestamp value) {
  final Duration age = DateTime.now().difference(value.toDate());
  expect(age.inSeconds.abs(), lessThan(5));
}

void main() {
  group('Vice.fromJson', () {
    Vice parse(Map<String, dynamic> json, {bool pending = false}) =>
        Vice.fromJson(id: 'v', json: json, pending: pending);

    test('reads a complete document unchanged', () {
      final Vice vice = parse(_vice());
      expect(vice.id, 'v');
      expect(vice.name, 'Coffee');
      expect(vice.unit, Unit.drink);
      expect(vice.ownerID, 'owner');
      expect(vice.createdAt, _at);
      expect(vice.archived, isTrue);
    });

    test('parses an empty document', () {
      final Vice vice = parse(<String, dynamic>{});
      expect(vice.name, '');
      expect(vice.unit, Unit.fallback);
      expect(vice.ownerID, '');
      expect(vice.createdAt, _epoch);
      expect(vice.archived, isFalse);
    });

    test('a missing or mistyped name reads as empty', () {
      expect(parse(_without(_vice(), 'name')).name, '');
      expect(parse(_with(_vice(), 'name', 42)).name, '');
      expect(parse(_with(_vice(), 'name', null)).name, '');
    });

    test('keeps a legacy name longer than the 60-unit limit', () {
      final String long = 'x' * 200;
      expect(parse(_with(_vice(), 'name', long)).name, long);
    });

    test('a missing, unknown or mistyped unit reads as the fallback', () {
      expect(parse(_without(_vice(), 'unit')).unit, Unit.fallback);
      expect(parse(_with(_vice(), 'unit', 'litre')).unit, Unit.fallback);
      expect(parse(_with(_vice(), 'unit', 'Drink')).unit, Unit.fallback);
      expect(parse(_with(_vice(), 'unit', 3)).unit, Unit.fallback);
    });

    test('every stored unit name round-trips', () {
      for (final Unit unit in Unit.values) {
        expect(parse(_with(_vice(), 'unit', unit.name)).unit, unit);
      }
    });

    test('a missing or mistyped ownerID reads as empty', () {
      expect(parse(_without(_vice(), 'ownerID')).ownerID, '');
      expect(parse(_with(_vice(), 'ownerID', 7)).ownerID, '');
    });

    test('a vice without archived (pre-2024-08-14) reads as unarchived', () {
      expect(parse(_without(_vice(), 'archived')).archived, isFalse);
      expect(parse(_with(_vice(), 'archived', 'true')).archived, isFalse);
      expect(parse(_with(_vice(), 'archived', 1)).archived, isFalse);
    });

    test('a missing or mistyped createdAt reads as the epoch', () {
      expect(parse(_without(_vice(), 'createdAt')).createdAt, _epoch);
      expect(parse(_with(_vice(), 'createdAt', 'yesterday')).createdAt, _epoch);
      expect(parse(_with(_vice(), 'createdAt', 1700000000)).createdAt, _epoch);
    });

    test('a pending server timestamp reads as now', () {
      expectRecent(
        parse(_with(_vice(), 'createdAt', null), pending: true).createdAt,
      );
    });

    test('a pending write keeps a resolved createdAt', () {
      expect(parse(_vice(), pending: true).createdAt, _at);
    });

    test('a DateTime createdAt converts to a Timestamp', () {
      expect(parse(_with(_vice(), 'createdAt', _at.toDate())).createdAt, _at);
    });

    test('round-trips through toJson', () {
      final Vice vice = parse(_vice());
      expect(parse(vice.toJson()).toJson(), vice.toJson());
    });
  });

  group('ViceActivity.fromJson', () {
    ViceActivity parse(Map<String, dynamic> json, {bool pending = false}) =>
        ViceActivity.fromJson(id: 'a', json: json, pending: pending);

    test('reads a complete document unchanged', () {
      final ViceActivity activity = parse(_activity());
      expect(activity.id, 'a');
      expect(activity.viceID, 'vice');
      expect(activity.quantity, 3);
      expect(activity.ownerID, 'owner');
      expect(activity.createdAt, _at);
    });

    test('parses an empty document', () {
      final ViceActivity activity = parse(<String, dynamic>{});
      expect(activity.viceID, '');
      expect(activity.quantity, 0);
      expect(activity.ownerID, '');
      expect(activity.createdAt, _epoch);
    });

    test('a missing or mistyped viceID reads as empty', () {
      expect(parse(_without(_activity(), 'viceID')).viceID, '');
      expect(parse(_with(_activity(), 'viceID', 1)).viceID, '');
    });

    test('a missing or mistyped ownerID reads as empty', () {
      expect(parse(_without(_activity(), 'ownerID')).ownerID, '');
      expect(parse(_with(_activity(), 'ownerID', true)).ownerID, '');
    });

    test('keeps legacy zero and negative quantities', () {
      expect(parse(_with(_activity(), 'quantity', 0)).quantity, 0);
      expect(parse(_with(_activity(), 'quantity', -2)).quantity, -2);
    });

    test('a quantity stored as a double reads as the nearest int', () {
      expect(parse(_with(_activity(), 'quantity', 2.0)).quantity, 2);
      expect(parse(_with(_activity(), 'quantity', 2.4)).quantity, 2);
      expect(parse(_with(_activity(), 'quantity', 2.5)).quantity, 3);
    });

    test('a quantity stored as a numeric string is parsed', () {
      expect(parse(_with(_activity(), 'quantity', '4')).quantity, 4);
      expect(parse(_with(_activity(), 'quantity', ' 1.6 ')).quantity, 2);
    });

    test('a missing, non-numeric or non-finite quantity reads as 0', () {
      expect(parse(_without(_activity(), 'quantity')).quantity, 0);
      expect(parse(_with(_activity(), 'quantity', 'many')).quantity, 0);
      expect(parse(_with(_activity(), 'quantity', double.nan)).quantity, 0);
      expect(
        parse(_with(_activity(), 'quantity', double.infinity)).quantity,
        0,
      );
      expect(parse(_with(_activity(), 'quantity', 'Infinity')).quantity, 0);
      expect(parse(_with(_activity(), 'quantity', <int>[1])).quantity, 0);
    });

    test('a missing or mistyped createdAt reads as the epoch', () {
      expect(parse(_without(_activity(), 'createdAt')).createdAt, _epoch);
      expect(
        parse(_with(_activity(), 'createdAt', '2024-01-01')).createdAt,
        _epoch,
      );
    });

    test('a pending null createdAt reads as now', () {
      expectRecent(
        parse(_with(_activity(), 'createdAt', null), pending: true).createdAt,
      );
    });

    test('round-trips through toJson', () {
      final ViceActivity activity = parse(_activity());
      expect(parse(activity.toJson()).toJson(), activity.toJson());
    });
  });

  group('fromQuerySnapshot', () {
    test('one malformed vice does not fail the list', () {
      final List<Vice> vices = Vice.fromQuerySnapshot(
        _snapshot(<(String, Map<String, dynamic>, bool)>[
          ('good', _vice(), false),
          ('legacy', _without(_vice(), 'archived'), false),
          ('bad', <String, dynamic>{'unit': 'litre', 'name': 1}, false),
        ]),
      );
      expect(vices.map((Vice v) => v.id), <String>['good', 'legacy', 'bad']);
      expect(vices[1].archived, isFalse);
      expect(vices[2].unit, Unit.fallback);
    });

    test('a just-saved vice reads its pending createdAt as now', () {
      final List<Vice> vices = Vice.fromQuerySnapshot(
        _snapshot(<(String, Map<String, dynamic>, bool)>[
          ('saved', _with(_vice(), 'createdAt', null), true),
          ('old', _with(_vice(), 'createdAt', null), false),
        ]),
      );
      expectRecent(vices[0].createdAt);
      expect(vices[1].createdAt, _epoch);
    });

    test('activities pass the pending flag and keep their order', () {
      final List<ViceActivity> activities = ViceActivity.fromQuerySnapshot(
        _snapshot(<(String, Map<String, dynamic>, bool)>[
          ('a1', _with(_activity(), 'quantity', 1.0), false),
          ('a2', _with(_activity(), 'createdAt', null), true),
        ]),
      );
      expect(activities.map((ViceActivity a) => a.id), <String>['a1', 'a2']);
      expect(activities[0].quantity, 1);
      expectRecent(activities[1].createdAt);
      expect(activities.map((ViceActivity a) => a.pending), <bool>[
        false,
        true,
      ]);
    });
  });
}
