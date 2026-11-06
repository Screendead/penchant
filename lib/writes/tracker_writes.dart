import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';

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
// for a DateTime written and the Timestamp read back.
Object? comparableValue(Object? value) => switch (value) {
  Timestamp() => value.microsecondsSinceEpoch,
  DateTime() => value.microsecondsSinceEpoch,
  _ => value,
};

// Every write the app makes. The field sets must match what firestore.rules
// accepts on create and update. With a [FieldSealer], content fields go into
// one sealed field; without one, every field is plaintext.
class TrackerWrites {
  TrackerWrites(
    this._firestore, {
    void Function()? onWrite,
    FieldSealer? sealer,
  }) : _onWrite = onWrite,
       _sealer = sealer;

  final FirebaseFirestore _firestore;
  final void Function()? _onWrite;
  final FieldSealer? _sealer;

  // The SDK sees the write only once the envelope exists, so an offline
  // write still queues, a moment later.
  Future<void> _sealing(
    FieldSealer sealer,
    DocumentReference<Map<String, dynamic>> doc,
    Map<String, Object?> content,
    Future<void> Function(String envelope) write,
  ) async {
    final String envelope = await sealer.seal(
      content,
      context: sealContext(doc.parent.id, doc.id),
    );
    return write(envelope);
  }

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
    final Map<String, Object> structural = <String, Object>{
      'ownerID': ownerID,
      'createdAt': FieldValue.serverTimestamp(),
      'archived': false,
    };
    final FieldSealer? sealer = _sealer;
    return _issued(
      SentWrite(
        sealer == null
            ? vice.set({'name': name, 'unit': unit.name, ...structural})
            : _sealing(
                sealer,
                vice,
                <String, Object?>{'name': name, 'unit': unit.name},
                (String envelope) =>
                    vice.set({sealedField: envelope, ...structural}),
              ),
        collection: _vices.id,
        id: vice.id,
        op: WriteOp.create,
      ),
    );
  }

  // Sealed, the whole content is written again, so [vice] supplies what is
  // unchanged, and a legacy vice's plaintext fields are removed.
  SentWrite updateVice(Vice vice, {String? name, Unit? unit}) {
    final FieldSealer? sealer = _sealer;
    if (sealer == null) {
      return _update(_vices, vice.id, {'name': ?name, 'unit': ?unit?.name});
    }
    if (vice.locked) {
      throw StateError('a locked vice has no content to write back');
    }
    return _sealedUpdate(sealer, _vices, vice.id, <String, Object?>{
      'name': name ?? vice.name,
      'unit': (unit ?? vice.unit).name,
    });
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
    required DateTime createdAt,
  }) {
    final DocumentReference<Map<String, dynamic>> activity = _activities.doc(
      activityID,
    );
    final Map<String, Object> structural = <String, Object>{
      'createdAt': createdAt,
      'ownerID': ownerID,
      'viceID': viceID,
    };
    final FieldSealer? sealer = _sealer;
    return _issued(
      SentWrite(
        sealer == null
            ? activity.set({'quantity': quantity, ...structural})
            : _sealing(
                sealer,
                activity,
                <String, Object?>{'quantity': quantity},
                (String envelope) =>
                    activity.set({sealedField: envelope, ...structural}),
              ),
        collection: _activities.id,
        id: activityID,
        op: WriteOp.create,
      ),
    );
  }

  // Only the given fields are written: an untouched field may hold a legacy
  // value that the parser shows as a default. Sealed, the quantity is the
  // whole content; a later content field must be passed here too, or a
  // reseal drops it.
  SentWrite updateActivity(
    String activityID, {
    int? quantity,
    DateTime? createdAt,
  }) {
    final FieldSealer? sealer = _sealer;
    if (sealer == null || quantity == null) {
      return _update(_activities, activityID, {
        'createdAt': ?createdAt,
        'quantity': ?quantity,
      });
    }
    return _sealedUpdate(
      sealer,
      _activities,
      activityID,
      <String, Object?>{'quantity': quantity},
      also: {'createdAt': ?createdAt},
    );
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

  // [SentWrite.fields] holds only the plaintext fields: the envelope does
  // not exist yet when the write is handed back, so a later launch cannot
  // check the server for the sealed part of a queued edit.
  SentWrite _sealedUpdate(
    FieldSealer sealer,
    CollectionReference<Map<String, dynamic>> collection,
    String id,
    Map<String, Object?> content, {
    Map<String, Object> also = const <String, Object>{},
  }) {
    final DocumentReference<Map<String, dynamic>> doc = collection.doc(id);
    return _issued(
      SentWrite(
        _sealing(
          sealer,
          doc,
          content,
          (String envelope) => doc.update({
            sealedField: envelope,
            for (final String field in content.keys) field: FieldValue.delete(),
            ...also,
          }),
        ),
        collection: collection.id,
        id: id,
        op: WriteOp.update,
        fields: <String, Object>{
          for (final MapEntry<String, Object>(:key, :value) in also.entries)
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
