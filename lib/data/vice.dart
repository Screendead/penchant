import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tracker/data/unit.dart';

class Vice {
  Vice({
    required this.id,
    required this.name,
    required this.unit,
    required this.ownerID,
    required this.createdAt,
    required this.archived,
  });

  final String id;
  final String name;
  final Unit unit;
  final String ownerID;
  final Timestamp createdAt;
  final bool archived;

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
      archived: json['archived'] as bool,
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
      'archived': archived,
    };
  }
}
