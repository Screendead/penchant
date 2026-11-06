import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tracker/data/json_fields.dart';
import 'package:tracker/data/sealed.dart';

class ViceActivity {
  ViceActivity({
    required this.id,
    required this.viceID,
    required this.quantity,
    required this.ownerID,
    required this.createdAt,
    this.pending = false,
    this.locked = false,
  });

  final String id;
  final String viceID;
  final int quantity;
  final String ownerID;
  final Timestamp createdAt;
  // A local write the server has not acknowledged yet.
  final bool pending;
  // Sealed fields this device could not open: [quantity] is a placeholder,
  // and must never be written back.
  final bool locked;

  factory ViceActivity.fromJson({
    required String id,
    required Map<String, dynamic> json,
    bool pending = false,
    Map<String, Object?>? opened,
  }) {
    final bool locked = isSealed(json) && opened == null;
    return ViceActivity(
      id: id,
      viceID: readString(json['viceID']),
      quantity: readInt(contentOf(json, opened)['quantity']),
      ownerID: readString(json['ownerID']),
      createdAt: readTimestamp(json['createdAt'], pending: pending),
      pending: pending,
      locked: locked,
    );
  }

  static Future<ViceActivity> open(
    DocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, dynamic> json,
    SealedOpener opener,
  ) async => ViceActivity.fromJson(
    id: doc.id,
    json: json,
    pending: doc.metadata.hasPendingWrites,
    opened: await opener.open('activities', doc.id, json),
  );

  static Future<List<ViceActivity>> openQuerySnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    SealedOpener opener,
  ) => Future.wait(
    snapshot.docs.map((doc) => ViceActivity.open(doc, doc.data(), opener)),
  );

  static List<ViceActivity> fromQuerySnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return snapshot.docs.map((doc) {
      return ViceActivity.fromJson(
        id: doc.id,
        json: doc.data(),
        pending: doc.metadata.hasPendingWrites,
      );
    }).toList();
  }
}
