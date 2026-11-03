import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tracker/data/json_fields.dart';

class ViceActivity {
  ViceActivity({
    required this.id,
    required this.viceID,
    required this.quantity,
    required this.ownerID,
    required this.createdAt,
    this.pending = false,
  });

  final String id;
  final String viceID;
  final int quantity;
  final String ownerID;
  final Timestamp createdAt;
  // A local write the server has not acknowledged yet.
  final bool pending;

  ViceActivity copyWith({
    String? id,
    String? viceID,
    int? quantity,
    String? ownerID,
    Timestamp? createdAt,
    bool? pending,
  }) {
    return ViceActivity(
      id: id ?? this.id,
      viceID: viceID ?? this.viceID,
      quantity: quantity ?? this.quantity,
      ownerID: ownerID ?? this.ownerID,
      createdAt: createdAt ?? this.createdAt,
      pending: pending ?? this.pending,
    );
  }

  factory ViceActivity.fromJson({
    required String id,
    required Map<String, dynamic> json,
    bool pending = false,
  }) => ViceActivity(
    id: id,
    viceID: readString(json['viceID']),
    quantity: readInt(json['quantity']),
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

  Map<String, dynamic> toJson() => {
    'viceID': viceID,
    'quantity': quantity,
    'ownerID': ownerID,
    'createdAt': createdAt,
  };
}
