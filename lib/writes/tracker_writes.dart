import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tracker/data/unit.dart';

// Every write the app makes. The field sets must match what firestore.rules
// accepts on create and update.
class TrackerWrites {
  TrackerWrites(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _vices =>
      _firestore.collection('vices');

  CollectionReference<Map<String, dynamic>> get _activities =>
      _firestore.collection('activities');

  Future<void> addVice({
    required String ownerID,
    required String name,
    required Unit unit,
  }) {
    return _vices.add({
      'name': name,
      'unit': unit.name,
      'ownerID': ownerID,
      'createdAt': FieldValue.serverTimestamp(),
      'archived': false,
    });
  }

  Future<void> updateVice(String viceID, {String? name, Unit? unit}) {
    return _vices.doc(viceID).update({'name': ?name, 'unit': ?unit?.name});
  }

  Future<void> setViceArchived(String viceID, {required bool archived}) {
    return _vices.doc(viceID).update({'archived': archived});
  }

  // Generated on the device without a round trip, so a caller can hold one
  // id across retries and every retry writes the same document.
  String newActivityID() => _activities.doc().id;

  Future<void> recordActivity(
    String activityID, {
    required String ownerID,
    required String viceID,
    required int quantity,
    required DateTime createdAt,
  }) {
    return _activities.doc(activityID).set({
      'createdAt': createdAt,
      'ownerID': ownerID,
      'quantity': quantity,
      'viceID': viceID,
    });
  }

  // Only the given fields are written: an untouched field may hold a legacy
  // value that the parser shows as a default.
  Future<void> updateActivity(
    String activityID, {
    int? quantity,
    DateTime? createdAt,
  }) {
    return _activities.doc(activityID).update({
      'createdAt': ?createdAt,
      'quantity': ?quantity,
    });
  }

  Future<void> deleteActivity(String activityID) {
    return _activities.doc(activityID).delete();
  }
}
