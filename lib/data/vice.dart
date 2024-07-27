import 'package:cloud_firestore/cloud_firestore.dart';

class Vice {
  Vice({
    required this.name,
    required this.units,
    required this.ownerID,
    required this.createdAt,
  });

  final String name;
  final int units;
  final String ownerID;
  final Timestamp createdAt;

  factory Vice.fromJson(Map<String, dynamic> json) {
    return Vice(
      name: json['name'] as String,
      units: json['units'] as int,
      ownerID: json['ownerID'] as String,
      createdAt: json['createdAt'] as Timestamp,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'units': units,
      'ownerID': ownerID,
      'createdAt': createdAt,
    };
  }
}
