import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:tracker/data/updated_at.dart';
import 'package:tracker/data/activity_content.dart';
import 'package:tracker/data/activity_triggers.dart';
import 'package:tracker/data/category.dart';
import 'package:tracker/data/check_in.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/data/habit_line.dart';
import 'package:tracker/data/habit_strength.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/urge.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/notes/follow_up.dart';

enum WriteOp { create, update, delete }

// A habit's own unit label (with its singular) and price, each optional. Sealed content only:
// without a journal key none of it is written.
typedef UnitAndPrice = ({
  String? unitLabel,
  String? unitSingular,
  double? costPerUnit,
  String? currency,
});

const UnitAndPrice noUnitAndPrice = (
  unitLabel: null,
  unitSingular: null,
  costPerUnit: null,
  currency: null,
);

UnitAndPrice unitAndPriceOf(Vice vice) => (
  unitLabel: vice.unitLabel,
  unitSingular: vice.unitSingular,
  costPerUnit: vice.costPerUnit,
  currency: vice.currency,
);

// Absent values are left out of the envelope, never written as null.
Map<String, Object?> _unitAndPriceContent(UnitAndPrice value) =>
    <String, Object?>{
      'unitLabel': ?value.unitLabel,
      'unitSingular': ?value.unitSingular,
      'costPerUnit': ?value.costPerUnit,
      'currency': ?value.currency,
    };

// A change to a habit's line: `(line: null)` removes it. Sealed content only,
// like [UnitAndPrice].
typedef LineChange = ({HabitLine? line});

// Likewise a habit's strength: `(strength: null)` removes it.
typedef StrengthChange = ({HabitStrength? strength});

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
// accepts on create and update. With a [FieldSealer], content fields go into
// one sealed field. The rules refuse a create without one, so without a
// sealer only updates and deletes are written, in plaintext.
class TrackerWrites {
  TrackerWrites(
    this._firestore, {
    void Function()? onWrite,
    FieldSealer? sealer,
    String? Function()? zone,
  }) : _onWrite = onWrite,
       _sealer = sealer,
       _zone = zone;

  final FirebaseFirestore _firestore;
  final void Function()? _onWrite;
  final FieldSealer? _sealer;
  // The device's time zone as last read, or null while unknown; a log never
  // waits for it.
  final String? Function()? _zone;

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

  /// Whether [addVice], [recordActivity], [setDayNote], [recordUrge] and
  /// [recordCheckIn] can write: the journal key has
  /// loaded. Callers check first and tell the user rather than lose input.
  bool get canCreate => _sealer != null;

  /// Whether [updateActivity] can write [content]: anything but a legacy
  /// entry's triggers needs the journal key.
  bool canWrite(ActivityContent content) =>
      _sealer != null || content.triggersAlone;

  FieldSealer _createSealer() {
    final FieldSealer? sealer = _sealer;
    if (sealer == null) {
      throw StateError('no journal key to seal a new document with');
    }
    return sealer;
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
    ViceCategory category = ViceCategory.fallback,
    UnitAndPrice unitAndPrice = noUnitAndPrice,
    HabitLine? line,
    HabitStrength? strength,
  }) {
    // doc().set() rather than add(), which the backend treats the same, so
    // the id is known before the server answers.
    final FieldSealer sealer = _createSealer();
    final DocumentReference<Map<String, dynamic>> vice = _vices.doc();
    return _issued(
      SentWrite(
        _sealing(
          sealer,
          vice,
          <String, Object?>{
            'name': name,
            'unit': unit.name,
            'category': category.name,
            ..._unitAndPriceContent(unitAndPrice),
            ...?line?.content,
            ...?strength?.content,
          },
          (Blob envelope) => vice.set({
            sealedField: envelope,
            'ownerID': ownerID,
            'createdAt': FieldValue.serverTimestamp(),
            'archived': false,
          }),
        ),
        collection: _vices.id,
        id: vice.id,
        op: WriteOp.create,
      ),
    );
  }

  // Sealed, the whole content is written again, so [vice] supplies what is
  // unchanged, and a legacy vice's plaintext fields are removed. A null
  // [unitAndPrice] keeps the vice's; a given one replaces all three, so a
  // null inside it clears that value. [line] and [strength] likewise: null
  // keeps the vice's.
  SentWrite updateVice(
    Vice vice, {
    String? name,
    Unit? unit,
    ViceCategory? category,
    UnitAndPrice? unitAndPrice,
    LineChange? line,
    StrengthChange? strength,
  }) {
    final FieldSealer? sealer = _sealer;
    if (sealer == null) {
      if (unitAndPrice != null && unitAndPrice != unitAndPriceOf(vice)) {
        throw StateError('no journal key to seal a unit label or price with');
      }
      if (line != null && line.line != vice.line) {
        throw StateError('no journal key to seal a line with');
      }
      if (strength != null && strength.strength != vice.strength) {
        throw StateError('no journal key to seal a strength with');
      }
      return _update(_vices, vice.id, {
        'name': ?name,
        'unit': ?unit?.name,
        'category': ?category?.name,
      });
    }
    if (vice.locked) {
      throw StateError('a locked vice has no content to write back');
    }
    return _sealedUpdate(sealer, _vices, vice.id, <String, Object?>{
      'name': name ?? vice.name,
      'unit': (unit ?? vice.unit).name,
      'category': (category ?? vice.category).name,
      ..._unitAndPriceContent(unitAndPrice ?? unitAndPriceOf(vice)),
      ...?(line == null ? vice.line : line.line)?.content,
      ...?(strength == null ? vice.strength : strength.strength)?.content,
    });
  }

  // Sets [category] only if the server's copy still has none, so a stale
  // cache cannot overwrite a category chosen on another device. A transaction
  // needs the server, so offline this fails rather than queues; true when it
  // wrote. A sealed copy is left alone: every sealed write carries a category,
  // the plaintext migrator's included.
  Future<bool> fillViceCategory(String viceID, ViceCategory category) {
    final DocumentReference<Map<String, dynamic>> vice = _vices.doc(viceID);
    return _firestore.runTransaction<bool>((Transaction transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> current = await transaction
          .get(vice);
      final Map<String, dynamic>? data = current.data();
      if (data == null || data.containsKey('category') || isSealed(data)) {
        return false;
      }
      transaction.update(vice, {'category': category.name});
      return true;
    });
  }

  SentWrite setViceArchived(String viceID, {required bool archived}) {
    return _update(_vices, viceID, {'archived': archived});
  }

  // Generated on the device without a round trip, so a caller can hold one
  // id across retries and every retry writes the same document.
  String newActivityID() => _activities.doc().id;

  // A new entry's sealed content also says where and how it was logged:
  // the device's time zone, the device clock now, and [loggedVia]. A
  // [restoring] entry's content (an undone delete) is written back as it was.
  SentWrite recordActivity(
    String activityID, {
    required String ownerID,
    required String viceID,
    required int quantity,
    double? amount,
    required DateTime createdAt,
    List<String> triggers = const <String>[],
    int? urge,
    String? note,
    LoggedVia? loggedVia,
    double? abv,
    double? caffeineMg,
    ActivityContent? restoring,
  }) {
    final FieldSealer sealer = _createSealer();
    final DocumentReference<Map<String, dynamic>> activity = _activities.doc(
      activityID,
    );
    final ActivityContent content =
        restoring ??
        ActivityContent(
          triggers: triggers,
          urge: urge,
          note: note,
          zone: _zone?.call(),
          writtenAt: clock.now(),
          loggedVia: loggedVia,
          abv: abv,
          caffeineMg: caffeineMg,
        );
    return _issued(
      SentWrite(
        // Sealed even without triggers, so the stored shape does not say
        // whether the entry has any.
        _sealing(
          sealer,
          activity,
          content.toMap(),
          (Blob envelope) => activity.set({
            'amount': ?amount,
            'createdAt': createdAt,
            'ownerID': ownerID,
            'quantity': quantity,
            'viceID': viceID,
            sealedField: envelope,
            ...updatedNow,
          }),
        ),
        collection: _activities.id,
        id: activityID,
        op: WriteOp.create,
      ),
    );
  }

  // Only the given fields are written: an untouched field may hold a legacy
  // value that the parser shows as a default. The quantity, amount and time
  // stay plaintext (Jack 2026-11-06); [content] is the whole new envelope
  // (ViceActivity.content with the answers changed), so what the user cannot
  // edit survives, and must be null for an entry whose envelope would not
  // open. Without a key only a legacy entry's triggers can change, in
  // plaintext; any other content fails like a refused save.
  SentWrite updateActivity(
    String activityID, {
    int? quantity,
    double? amount,
    DateTime? createdAt,
    ActivityContent? content,
  }) {
    final Map<String, Object> plaintext = <String, Object>{
      'amount': ?amount,
      'createdAt': ?createdAt,
      'quantity': ?quantity,
    };
    final FieldSealer? sealer = _sealer;
    if (sealer == null && content != null && !content.triggersAlone) {
      return _issued(
        SentWrite(
          Future<void>.error(
            FirebaseException(
              plugin: 'sealer',
              code: 'failed-precondition',
              message: 'The journal key has not loaded',
            ),
          ),
          collection: _activities.id,
          id: activityID,
          op: WriteOp.update,
        ),
      );
    }
    if (sealer == null || content == null) {
      return _update(_activities, activityID, {
        ...plaintext,
        if (content != null) triggersField: writeTriggers(content.triggers),
      }, stamp: true);
    }
    final DocumentReference<Map<String, dynamic>> doc = _activities.doc(
      activityID,
    );
    return _issued(
      SentWrite(
        _sealing(
          sealer,
          doc,
          content.toMap(),
          (Blob envelope) => doc.update({
            ...plaintext,
            sealedField: envelope,
            triggersField: FieldValue.delete(),
            ...updatedNow,
          }),
        ),
        collection: _activities.id,
        id: activityID,
        op: WriteOp.update,
        fields: <String, Object>{
          for (final MapEntry<String, Object>(:key, :value)
              in plaintext.entries)
            key: comparableValue(value)!,
        },
      ),
    );
  }

  // The content of an entry as this device holds it (a write it just queued
  // included), to seal again whole when its answers change; null when it is
  // not on the device, will not open, or no key has loaded.
  Future<ActivityContent?> cachedContent(String activityID) async {
    final FieldSealer? sealer = _sealer;
    if (sealer == null) {
      return null;
    }
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = await _activities
          .doc(activityID)
          .get(const GetOptions(source: Source.cache));
      final Map<String, dynamic>? data = doc.data();
      if (data == null) {
        return null;
      }
      final Map<String, Object?>? opened = await SealedOpener(
        sealer,
      ).open(_activities.id, activityID, data);
      if (isSealed(data) && opened == null) {
        return null;
      }
      return ActivityContent.read(contentOf(data, opened));
    } on FirebaseException {
      return null;
    }
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

  CollectionReference<Map<String, dynamic>> get _dayNotes =>
      _firestore.collection(dayNotesCollection);

  // The note about [day] (a [dayKey]), under its one id. With no [replacing]
  // note this is a create; with one, an update of the envelope alone, since
  // the rules fix `ownerID`, `day` and `createdAt`. A create where another
  // device already made that day's note is refused, and settles as such.
  // Callers check [dayNoteError] first: past the envelope the seal fails.
  SentWrite setDayNote({
    required String ownerID,
    required String day,
    required String text,
    List<String> triggers = const <String>[],
    FollowUp? followUp,
    DayNote? replacing,
  }) {
    final FieldSealer sealer = _createSealer();
    if (replacing != null && replacing.locked) {
      throw StateError('a locked day note cannot be replaced unseen');
    }
    final DocumentReference<Map<String, dynamic>> note = _dayNotes.doc(
      dayNoteID(ownerID, day),
    );
    return _issued(
      SentWrite(
        _sealing(
          sealer,
          note,
          dayNoteContent(text: text, triggers: triggers, followUp: followUp),
          (Blob envelope) => replacing == null
              ? note.set({
                  sealedField: envelope,
                  'ownerID': ownerID,
                  'day': day,
                  'createdAt': FieldValue.serverTimestamp(),
                  ...updatedNow,
                })
              : note.update({sealedField: envelope, ...updatedNow}),
        ),
        collection: _dayNotes.id,
        id: note.id,
        op: replacing == null ? WriteOp.create : WriteOp.update,
      ),
    );
  }

  SentWrite deleteDayNote({required String ownerID, required String day}) {
    final String id = dayNoteID(ownerID, day);
    return _issued(
      SentWrite(
        _dayNotes.doc(id).delete(),
        collection: _dayNotes.id,
        id: id,
        op: WriteOp.delete,
      ),
    );
  }

  CollectionReference<Map<String, dynamic>> get _urges =>
      _firestore.collection(urgesCollection);

  // On the device, so Undo and the check-in can name the urge before the
  // server answers.
  String newUrgeID() => _urges.doc().id;

  // Born sealed, like a day note. `createdAt` is the device clock, as an
  // entry's is: a pending server timestamp matches no range query, so an
  // urge noted offline would vanish from Trends.
  SentWrite recordUrge(
    String urgeID, {
    required String ownerID,
    required String viceID,
    required DateTime createdAt,
    required int strength,
  }) {
    final FieldSealer sealer = _createSealer();
    final DocumentReference<Map<String, dynamic>> urge = _urges.doc(urgeID);
    return _issued(
      SentWrite(
        _sealing(
          sealer,
          urge,
          UrgeContent(strength: strength, zone: _zone?.call()).toMap(),
          (Blob envelope) => urge.set({
            sealedField: envelope,
            'ownerID': ownerID,
            'viceID': viceID,
            'createdAt': createdAt,
          }),
        ),
        collection: _urges.id,
        id: urgeID,
        op: WriteOp.create,
      ),
    );
  }

  // The whole envelope again: the rules let nothing else change.
  SentWrite updateUrge(String urgeID, UrgeContent content) {
    final FieldSealer sealer = _createSealer();
    final DocumentReference<Map<String, dynamic>> urge = _urges.doc(urgeID);
    return _issued(
      SentWrite(
        _sealing(
          sealer,
          urge,
          content.toMap(),
          (Blob envelope) => urge.update({sealedField: envelope}),
        ),
        collection: _urges.id,
        id: urgeID,
        op: WriteOp.update,
      ),
    );
  }

  SentWrite deleteUrge(String urgeID) {
    return _issued(
      SentWrite(
        _urges.doc(urgeID).delete(),
        collection: _urges.id,
        id: urgeID,
        op: WriteOp.delete,
      ),
    );
  }

  // One urge, from the server or else this device's cache: the check-in's
  // answer reseals the whole content, so it needs the strength. Null when
  // the urge is gone, will not open, or nothing answers.
  Future<Urge?> readUrge(String urgeID, {required String ownerID}) async {
    final FieldSealer? sealer = _sealer;
    if (sealer == null) {
      return null;
    }
    final DocumentReference<Map<String, dynamic>> doc = _urges.doc(urgeID);
    DocumentSnapshot<Map<String, dynamic>>? snapshot;
    try {
      snapshot = await doc.get();
    } on FirebaseException {
      try {
        snapshot = await doc.get(const GetOptions(source: Source.cache));
      } on FirebaseException {
        return null;
      }
    }
    final Map<String, dynamic>? data = snapshot.data();
    if (data == null || data['ownerID'] != ownerID) {
      return null;
    }
    final Urge urge = await Urge.open(snapshot, data, SealedOpener(sealer));
    return urge.locked ? null : urge;
  }

  CollectionReference<Map<String, dynamic>> get _checkIns =>
      _firestore.collection(checkInsCollection);

  // Born sealed and never changed: the rules allow create and delete only.
  // [checkInID] is drawn when the prompt is scheduled, so a press heard
  // twice names one document. `createdAt` is the device clock at answering,
  // as an entry's is.
  SentWrite recordCheckIn(
    String checkInID, {
    required String ownerID,
    required DateTime createdAt,
    required int strength,
    required DateTime promptedAt,
    required CheckInVia via,
  }) {
    final FieldSealer sealer = _createSealer();
    final DocumentReference<Map<String, dynamic>> checkIn = _checkIns.doc(
      checkInID,
    );
    return _issued(
      SentWrite(
        _sealing(
          sealer,
          checkIn,
          CheckInContent(
            strength: strength,
            promptedAt: promptedAt,
            zone: _zone?.call(),
            via: via,
          ).toMap(),
          (Blob envelope) => checkIn.set({
            sealedField: envelope,
            'ownerID': ownerID,
            'createdAt': createdAt,
          }),
        ),
        collection: _checkIns.id,
        id: checkInID,
        op: WriteOp.create,
      ),
    );
  }

  SentWrite deleteCheckIn(String checkInID) {
    return _issued(
      SentWrite(
        _checkIns.doc(checkInID).delete(),
        collection: _checkIns.id,
        id: checkInID,
        op: WriteOp.delete,
      ),
    );
  }

  // [stamp] adds [updatedNow] to the write but not to [SentWrite.fields]: an
  // unresolved server timestamp has no value to check the server's copy for.
  SentWrite _update(
    CollectionReference<Map<String, dynamic>> collection,
    String id,
    Map<String, Object> fields, {
    bool stamp = false,
  }) {
    return _issued(
      SentWrite(
        collection.doc(id).update({...fields, if (stamp) ...updatedNow}),
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
