import 'package:flutter/foundation.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/writes/tracker_writes.dart';

@immutable
class Write {
  const Write(this.op, this.id, [this.fields = const <String, Object?>{}]);

  final String op;
  final String id;
  final Map<String, Object?> fields;

  @override
  bool operator ==(Object other) =>
      other is Write &&
      other.op == op &&
      other.id == id &&
      mapEquals(other.fields, fields);

  @override
  int get hashCode => Object.hash(op, id, Object.hashAllUnordered(fields.keys));

  @override
  String toString() => 'Write($op, $id, $fields)';
}

// Records every write instead of sending it. [respond] decides how each one
// completes; by default it succeeds at once.
class FakeTrackerWrites implements TrackerWrites {
  final List<Write> writes = <Write>[];
  Future<void> Function(Write write)? respond;
  int _ids = 0;

  Future<void> _write(Write write) {
    writes.add(write);
    return respond?.call(write) ?? Future<void>.value();
  }

  @override
  Future<void> addVice({
    required String ownerID,
    required String name,
    required Unit unit,
  }) => _write(
    Write('addVice', '', <String, Object?>{
      'ownerID': ownerID,
      'name': name,
      'unit': unit,
    }),
  );

  @override
  Future<void> setViceArchived(String viceID, {required bool archived}) =>
      _write(
        Write('setViceArchived', viceID, <String, Object?>{
          'archived': archived,
        }),
      );

  @override
  String newActivityID() => 'activity-${++_ids}';

  @override
  Future<void> recordActivity(
    String activityID, {
    required String ownerID,
    required String viceID,
    required int quantity,
    required DateTime createdAt,
  }) => _write(
    Write('recordActivity', activityID, <String, Object?>{
      'ownerID': ownerID,
      'viceID': viceID,
      'quantity': quantity,
      'createdAt': createdAt,
    }),
  );

  @override
  Future<void> updateActivity(
    String activityID, {
    int? quantity,
    DateTime? createdAt,
  }) => _write(
    Write('updateActivity', activityID, <String, Object?>{
      'quantity': ?quantity,
      'createdAt': ?createdAt,
    }),
  );

  @override
  Future<void> deleteActivity(String activityID) =>
      _write(Write('deleteActivity', activityID));
}
