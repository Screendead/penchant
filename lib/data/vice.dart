import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tracker/data/unit.dart';

class Vice {
  Vice({
    required this.id,
    required this.name,
    required this.unit,
    required this.ownerID,
    required this.createdAt,
  });

  final String id;
  final String name;
  final Unit unit;
  final String ownerID;
  final Timestamp createdAt;

  factory Vice.fromJson({
    required String id,
    required Map<String, dynamic> json,
  }) {
    return Vice(
      id: id,
      name: json['name'] as String,
      unit: Unit.fromString(json['unit'] as String),
      ownerID: json['ownerID'] as String,
      createdAt: json['createdAt'] as Timestamp,
    );
  }

  static List<Vice> fromQuerySnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return snapshot.docs.map((doc) {
      return Vice.fromJson(id: doc.id, json: doc.data());
    }).toList();
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'unit': unit.name,
      'ownerID': ownerID,
      'createdAt': createdAt,
    };
  }
}
