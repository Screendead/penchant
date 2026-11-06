import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tracker/data/json_fields.dart';

class ViceActivity {
  ViceActivity({
    required this.id,
    required this.viceID,
    required this.quantity,
    required this.ownerID,
    required this.createdAt,
    this.amount,
    this.pending = false,
  });

  final String id;
  final String viceID;
  final int quantity;
  // Optional and finer than [quantity], which a client writing it sets to the
  // amount rounded up, so that builds reading only quantity stay close.
  final double? amount;
  final String ownerID;
  final Timestamp createdAt;
  // A local write the server has not acknowledged yet.
  final bool pending;

  // What charts, totals and labels count.
  num get measure => amount ?? quantity;

  factory ViceActivity.fromJson({
    required String id,
    required Map<String, dynamic> json,
    bool pending = false,
  }) => ViceActivity(
    id: id,
    viceID: readString(json['viceID']),
    quantity: readInt(json['quantity']),
    amount: readAmount(json['amount']),
    ownerID: readString(json['ownerID']),
    createdAt: readTimestamp(json['createdAt'], pending: pending),
    pending: pending,
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
