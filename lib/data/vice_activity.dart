import 'package:cloud_firestore/cloud_firestore.dart';

class ViceActivity {
  ViceActivity({
    required this.id,
    required this.viceID,
    required this.quantity,
    required this.ownerID,
    required this.createdAt,
    this.sealed = false,
    this.unreadable = false,
  });

  final String id;
  final String viceID;
  final int quantity;
  final String ownerID;
  final Timestamp createdAt;

  /// The quantity lives in `enc`, not in a plaintext field.
  final bool sealed;

  /// Sealed, but the blob did not open; [quantity] is 0 and not real.
  final bool unreadable;

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
      sealed: sealed,
      unreadable: unreadable,
    );
  }

  /// Reads either shape: plaintext `quantity`, or `enc` with [opened]
  /// holding what it decrypted to (null when it did not open).
  factory ViceActivity.fromJson({
    required String id,
    required Map<String, dynamic> json,
    Map<String, dynamic>? opened,
  }) {
    final bool sealed = json.containsKey('enc');

    return ViceActivity(
      id: id,
      viceID: json['viceID'] as String,
      quantity: sealed
          ? (opened?['q'] as int? ?? 0)
          : json['quantity'] as int,
      ownerID: json['ownerID'] as String,
      createdAt: json['createdAt'] as Timestamp,
      sealed: sealed,
      unreadable: sealed && opened == null,
    );
  }

  Map<String, dynamic> toJson() => {
        'viceID': viceID,
        'quantity': quantity,
        'ownerID': ownerID,
        'createdAt': createdAt,
      };
}
