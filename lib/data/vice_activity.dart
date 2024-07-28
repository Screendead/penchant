import 'package:cloud_firestore/cloud_firestore.dart';

class ViceActivity {
  ViceActivity({
    required this.id,
    required this.timestamp,
    required this.viceID,
    required this.quantity,
    required this.ownerID,
  });

  final String id;
  final Timestamp timestamp;
  final String viceID;
  final int quantity;
  final String ownerID;

  factory ViceActivity.fromJson({
    required String id,
    required Map<String, dynamic> json,
  }) =>
      ViceActivity(
        id: id,
        timestamp: json['timestamp'] as Timestamp,
        viceID: json['viceID'] as String,
        quantity: json['quantity'] as int,
        ownerID: json['ownerID'] as String,
      );

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'viceID': viceID,
        'quantity': quantity,
        'ownerID': ownerID,
      };
}
