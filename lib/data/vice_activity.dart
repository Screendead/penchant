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

  Map<String, dynamic> toJson() => {
        'viceID': viceID,
        'quantity': quantity,
        'ownerID': ownerID,
        'createdAt': createdAt,
      };
}
