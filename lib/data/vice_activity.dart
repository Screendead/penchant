import 'package:cloud_firestore/cloud_firestore.dart';

class ViceActivity {
  ViceActivity({
    required this.id,
    required this.viceID,
    required this.quantity,
    required this.ownerID,
    required this.createdAt,
  });

  final String id;
  final String viceID;
  final int quantity;
  final String ownerID;
  final Timestamp createdAt;

  ViceActivity copyWith({
    String? id,
    String? viceID,
    int? quantity,
    String? ownerID,
    Timestamp? createdAt,
  }) {
    return ViceActivity(
      id: id ?? this.id,
      viceID: viceID ?? this.viceID,
      quantity: quantity ?? this.quantity,
      ownerID: ownerID ?? this.ownerID,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory ViceActivity.fromJson({
    required String id,
    required Map<String, dynamic> json,
  }) =>
      ViceActivity(
        id: id,
        viceID: json['viceID'] as String,
        quantity: json['quantity'] as int,
        ownerID: json['ownerID'] as String,
        createdAt: json['createdAt'] as Timestamp,
      );

  static List<ViceActivity> fromQuerySnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return snapshot.docs.map((doc) {
      return ViceActivity.fromJson(id: doc.id, json: doc.data());
    }).toList();
  }

  Map<String, dynamic> toJson() => {
        'viceID': viceID,
        'quantity': quantity,
        'ownerID': ownerID,
        'createdAt': createdAt,
      };
}
