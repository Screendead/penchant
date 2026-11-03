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
    this.sealed = false,
    this.unreadable = false,
  });

  static const String unreadableName = 'Unreadable entry';

  final String id;
  final String name;
  final Unit unit;
  final String ownerID;
  final Timestamp createdAt;
  final bool archived;

  /// Name and unit live in `enc`, not in plaintext fields.
  final bool sealed;

  /// Sealed, but the blob did not open: wrong key, tampered, or moved.
  final bool unreadable;

  /// Reads either shape: plaintext `name`/`unit`, or `enc` with [opened]
  /// holding what it decrypted to (null when it did not open).
  factory Vice.fromJson({
    required String id,
    required Map<String, dynamic> json,
    Map<String, dynamic>? opened,
  }) {
    if (json.containsKey('enc')) {
      return Vice(
        id: id,
        name: opened?['n'] as String? ?? unreadableName,
        unit: Unit.tryParse(opened?['u'] as String?) ?? Unit.item,
        ownerID: json['ownerID'] as String,
        createdAt: json['createdAt'] as Timestamp,
        archived: json['archived'] as bool? ?? false,
        sealed: true,
        unreadable: opened == null,
      );
    }

    return Vice(
      id: id,
      name: json['name'] as String,
      unit: Unit.fromString(json['unit'] as String),
      ownerID: json['ownerID'] as String,
      createdAt: json['createdAt'] as Timestamp,
      archived: json['archived'] as bool,
    );
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
