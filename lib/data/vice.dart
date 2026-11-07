import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tracker/data/category.dart';
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
    this.category = ViceCategory.fallback,
    this.categoryStored = true,
  });

  final String id;
  final String name;
  final Unit unit;
  final String ownerID;
  final Timestamp createdAt;
  final bool archived;
  final ViceCategory category;
  // False for a document written before the field, which the category
  // migration fills in. An unknown name counts as stored: a later version
  // wrote it.
  final bool categoryStored;

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
      category: ViceCategory.fromString(json['category']),
      categoryStored: json['category'] is String,
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
