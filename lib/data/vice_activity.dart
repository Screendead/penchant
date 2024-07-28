import 'package:cloud_firestore/cloud_firestore.dart';

class ViceActivity {
  ViceActivity({
    required this.timestamp,
    required this.viceID,
    required this.quantity,
    required this.ownerID,
  });

  final Timestamp timestamp;
  final String viceID;
  final int quantity;
  final String ownerID;

  factory ViceActivity.fromJson(Map<String, dynamic> json) => ViceActivity(
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
