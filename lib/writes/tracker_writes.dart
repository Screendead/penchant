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
    Future<void> Function(Blob envelope) write,
  ) async {
    final Uint8List envelope;
    try {
      envelope = await sealer.seal(
        content,
        context: sealContext(doc.parent.id, doc.id),
      );
    } on FirebaseException {
      rethrow;
    } catch (e) {
      // settleWrite shows only a FirebaseException as a failed save.
      throw FirebaseException(
        plugin: 'sealer',
        code: 'failed-precondition',
        message: 'Could not seal the change: $e',
      );
    }
    return write(Blob(envelope));
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
                (Blob envelope) =>
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
    return _issued(
      SentWrite(
        _activities.doc(activityID).set({
          'createdAt': createdAt,
          'ownerID': ownerID,
          'quantity': quantity,
          'viceID': viceID,
        }),
        collection: _activities.id,
        id: activityID,
        op: WriteOp.create,
      ),
    );
  }

  // Only the given fields are written: an untouched field may hold a legacy
  // value that the parser shows as a default. Activities have no sealed
  // field yet: the quantity stays plaintext (Jack, 2026-11-06). When the
  // triggers field lands it is sealed, and this must then reseal it.
  SentWrite updateActivity(
    String activityID, {
    int? quantity,
    DateTime? createdAt,
  }) {
    return _update(_activities, activityID, {
      'createdAt': ?createdAt,
      'quantity': ?quantity,
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

  // [SentWrite.fields] is empty: the envelope does not exist yet when the
  // write is handed back, so a later launch cannot check the server for a
  // queued sealed edit.
  SentWrite _sealedUpdate(
    FieldSealer sealer,
    CollectionReference<Map<String, dynamic>> collection,
    String id,
    Map<String, Object?> content,
  ) {
    final DocumentReference<Map<String, dynamic>> doc = collection.doc(id);
    return _issued(
      SentWrite(
        _sealing(
          sealer,
          doc,
          content,
          (Blob envelope) => doc.update({
            sealedField: envelope,
            for (final String field in contentFields[collection.id]!)
              field: FieldValue.delete(),
          }),
        ),
        collection: collection.id,
        id: id,
        op: WriteOp.update,
        fields: const <String, Object>{},
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
