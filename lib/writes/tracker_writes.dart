import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:tracker/data/activity_triggers.dart';
import 'package:tracker/data/unit.dart';

enum WriteOp { create, update, delete }

// A write handed to the SDK: its future, and the document it leaves behind.
// [fields] holds what an update sets, through [comparableValue], so that the
// server's copy can later be checked for it.
@immutable
class SentWrite {
  const SentWrite(
    this.done, {
    required this.collection,
    required this.id,
    required this.op,
    this.fields = const <String, Object>{},
  });

  final Future<void> done;
  final String collection;
  final String id;
  final WriteOp op;
  final Map<String, Object> fields;
}

// The form a field value takes in [SentWrite.fields]: JSON-safe, and equal
// for a DateTime written and the Timestamp read back, and for a list written
// and the list read back (Dart lists compare by identity).
Object? comparableValue(Object? value) => switch (value) {
  Timestamp() => value.microsecondsSinceEpoch,
  DateTime() => value.microsecondsSinceEpoch,
  List<Object?>() => jsonEncode(value),
  _ => value,
};

// Every write the app makes. The field sets must match what firestore.rules
// accepts on create and update.
class TrackerWrites {
  TrackerWrites(this._firestore, {void Function()? onWrite})
    : _onWrite = onWrite;

  final FirebaseFirestore _firestore;
  final void Function()? _onWrite;

  SentWrite _issued(SentWrite write) {
    _onWrite?.call();
    return write;
  }

  CollectionReference<Map<String, dynamic>> get _vices =>
      _firestore.collection('vices');

  CollectionReference<Map<String, dynamic>> get _activities =>
      _firestore.collection('activities');

  SentWrite addVice({
    required String ownerID,
    required String name,
    required Unit unit,
  }) {
    // doc().set() rather than add(), which the backend treats the same, so
    // the id is known before the server answers.
    final DocumentReference<Map<String, dynamic>> vice = _vices.doc();
    return _issued(
      SentWrite(
        vice.set({
          'name': name,
          'unit': unit.name,
          'ownerID': ownerID,
          'createdAt': FieldValue.serverTimestamp(),
          'archived': false,
        }),
        collection: _vices.id,
        id: vice.id,
        op: WriteOp.create,
      ),
    );
  }

  SentWrite updateVice(String viceID, {String? name, Unit? unit}) {
    return _update(_vices, viceID, {'name': ?name, 'unit': ?unit?.name});
  }

  SentWrite setViceArchived(String viceID, {required bool archived}) {
    return _update(_vices, viceID, {'archived': archived});
  }

  // Generated on the device without a round trip, so a caller can hold one
  // id across retries and every retry writes the same document.
  String newActivityID() => _activities.doc().id;

  SentWrite recordActivity(
    String activityID, {
    required String ownerID,
    required String viceID,
    required int quantity,
    double? amount,
    required DateTime createdAt,
    List<String> triggers = const <String>[],
  }) {
    return _issued(
      SentWrite(
        _activities.doc(activityID).set({
          'amount': ?amount,
          'createdAt': createdAt,
          'ownerID': ownerID,
          'quantity': quantity,
          'viceID': viceID,
          if (triggers.isNotEmpty) triggersField: writeTriggers(triggers),
        }),
        collection: _activities.id,
        id: activityID,
        op: WriteOp.create,
      ),
    );
  }

  // Only the given fields are written: an untouched field may hold a legacy
  // value that the parser shows as a default.
  SentWrite updateActivity(
    String activityID, {
    int? quantity,
    double? amount,
    DateTime? createdAt,
    List<String>? triggers,
  }) {
    return _update(_activities, activityID, {
      'amount': ?amount,
      'createdAt': ?createdAt,
      'quantity': ?quantity,
      if (triggers != null) triggersField: writeTriggers(triggers),
    });
  }

  SentWrite deleteActivity(String activityID) {
    return _issued(
      SentWrite(
        _activities.doc(activityID).delete(),
        collection: _activities.id,
        id: activityID,
        op: WriteOp.delete,
      ),
    );
  }

  SentWrite _update(
    CollectionReference<Map<String, dynamic>> collection,
    String id,
    Map<String, Object> fields,
  ) {
    return _issued(
      SentWrite(
        collection.doc(id).update(fields),
        collection: collection.id,
        id: id,
        op: WriteOp.update,
        fields: <String, Object>{
          for (final MapEntry<String, Object>(:key, :value) in fields.entries)
            key: comparableValue(value)!,
        },
      ),
    );
  }

  // Resolves once every write queued before the call, an earlier launch's
  // included, has been accepted or refused; it does not say which.
  Future<void> waitForPendingWrites() => _firestore.waitForPendingWrites();

  // The server's copy of a document [ownerID] owns, or null when it holds
  // none. A query, not a get: the rules deny a get of a missing document, so
  // a get could not tell it from any other denial. Equality on ownerID
  // ordered by document id is served by the automatic single-field index.
  Future<Map<String, Object?>?> serverDocument(
    String collection,
    String id, {
    required String ownerID,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> found = await _firestore
        .collection(collection)
        .where('ownerID', isEqualTo: ownerID)
        .orderBy(FieldPath.documentId)
        .startAt([id])
        .endAt([id])
        .get(const GetOptions(source: Source.server));
    return found.docs.isEmpty ? null : found.docs.single.data();
  }
}
