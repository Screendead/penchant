import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tracker/data/json_fields.dart';
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
    bool pending = false,
  }) {
    return Vice(
      id: id,
      name: readString(json['name']),
      unit: Unit.fromString(json['unit']),
      ownerID: readString(json['ownerID']),
      createdAt: readTimestamp(json['createdAt'], pending: pending),
      archived: readBool(json['archived'], fallback: false),
    );
  }

  static List<Vice> fromQuerySnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return snapshot.docs.map((doc) {
      return Vice.fromJson(
        id: doc.id,
        json: doc.data(),
        pending: doc.metadata.hasPendingWrites,
      );
    }).toList();
  }
}
