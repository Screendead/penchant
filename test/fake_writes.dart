import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:tracker/data/category.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/writes/queued_write_journal.dart';
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
// completes; by default it succeeds at once. [server] stands for the server's
// copies, keyed 'collection/id', for the check of an earlier launch's writes,
// which waits on [pendingWrites], or not at all when it is null.
class FakeTrackerWrites implements TrackerWrites {
  final List<Write> writes = <Write>[];
  Future<void> Function(Write write)? respond;
  final Map<String, Map<String, Object?>> server =
      <String, Map<String, Object?>>{};
  Future<void>? pendingWrites;
  Object? serverError;
  final List<String> checked = <String>[];
  int _ids = 0;
  // False stands for a device whose journal key has not loaded: creates
  // throw, as TrackerWrites' do.
  @override
  bool canCreate = true;

  void _requireKey() {
    if (!canCreate) {
      throw StateError('no journal key to seal a new document with');
    }
  }

  SentWrite _write(
    Write write, {
    required String collection,
    required WriteOp op,
    Map<String, Object> fields = const <String, Object>{},
  }) {
    writes.add(write);
    return SentWrite(
      respond?.call(write) ?? Future<void>.value(),
      collection: collection,
      id: write.id,
      op: op,
      fields: <String, Object>{
        for (final MapEntry<String, Object>(:key, :value) in fields.entries)
          key: comparableValue(value)!,
      },
    );
  }

  @override
  SentWrite addVice({
    required String ownerID,
    required String name,
    required Unit unit,
    ViceCategory category = ViceCategory.fallback,
  }) {
    _requireKey();
    return _write(
      Write('addVice', 'vice-${++_ids}', <String, Object?>{
        'ownerID': ownerID,
        'name': name,
        'unit': unit,
        'category': category,
      }),
      collection: 'vices',
      op: WriteOp.create,
    );
  }

  @override
  SentWrite updateVice(
    Vice vice, {
    String? name,
    Unit? unit,
    ViceCategory? category,
  }) => _write(
    Write('updateVice', vice.id, <String, Object?>{
      'name': ?name,
      'unit': ?unit,
      'category': ?category,
    }),
    collection: 'vices',
    op: WriteOp.update,
    fields: <String, Object>{
      'name': ?name,
      'unit': ?unit?.name,
      'category': ?category?.name,
    },
  );

  @override
  Future<bool> fillViceCategory(String viceID, ViceCategory category) {
    writes.add(
      Write('fillViceCategory', viceID, <String, Object?>{
        'category': category,
      }),
    );
    final Map<String, Object?>? copy = server['vices/$viceID'];
    if (copy != null && copy.containsKey('category')) {
      return Future<bool>.value(false);
    }
    return (respond?.call(writes.last) ?? Future<void>.value()).then((_) {
      copy?['category'] = category.name;
      return true;
    });
  }

  @override
  SentWrite setViceArchived(String viceID, {required bool archived}) => _write(
    Write('setViceArchived', viceID, <String, Object?>{'archived': archived}),
    collection: 'vices',
    op: WriteOp.update,
    fields: <String, Object>{'archived': archived},
  );

  @override
  String newActivityID() => 'activity-${++_ids}';

  @override
  SentWrite recordActivity(
    String activityID, {
    required String ownerID,
    required String viceID,
    required int quantity,
    double? amount,
    required DateTime createdAt,
    List<String> triggers = const <String>[],
  }) {
    _requireKey();
    return _write(
      Write('recordActivity', activityID, <String, Object?>{
        'ownerID': ownerID,
        'viceID': viceID,
        'quantity': quantity,
        'amount': ?amount,
        'createdAt': createdAt,
        if (triggers.isNotEmpty) 'triggers': triggers,
      }),
      collection: 'activities',
      op: WriteOp.create,
    );
  }

  @override
  SentWrite updateActivity(
    String activityID, {
    int? quantity,
    double? amount,
    DateTime? createdAt,
    List<String>? triggers,
  }) => _write(
    Write('updateActivity', activityID, <String, Object?>{
      'quantity': ?quantity,
      'amount': ?amount,
      'createdAt': ?createdAt,
      'triggers': ?triggers,
    }),
    collection: 'activities',
    op: WriteOp.update,
    fields: <String, Object>{
      'quantity': ?quantity,
      'amount': ?amount,
      'createdAt': ?createdAt,
      'triggers': ?triggers,
    },
  );

  @override
  SentWrite deleteActivity(String activityID) => _write(
    Write('deleteActivity', activityID),
    collection: 'activities',
    op: WriteOp.delete,
  );

  @override
  Future<void> waitForPendingWrites() => pendingWrites ?? Future<void>.value();

  @override
  Future<Map<String, Object?>?> serverDocument(
    String collection,
    String id, {
    required String ownerID,
  }) async {
    checked.add('$collection/$id');
    if (serverError case final Object error) {
      throw error;
    }
    return server['$collection/$id'];
  }
}

// A journal held in memory, one per container: path_provider has no plugin
// under flutter test.
Override memoryJournal([MemoryJournalStore? store]) =>
    queuedWriteJournalProvider.overrideWith(
      (ref) => QueuedWriteJournal(store ?? MemoryJournalStore()),
    );

// The journal's file, held in memory.
class MemoryJournalStore implements JournalStore {
  MemoryJournalStore([this.contents]);

  String? contents;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> write(String contents) async {
    this.contents = contents;
  }
}
