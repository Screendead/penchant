import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tracker/data/activity_triggers.dart';
import 'package:tracker/data/json_fields.dart';

class ViceActivity {
  ViceActivity({
    required this.id,
    required this.viceID,
    required this.quantity,
    required this.ownerID,
    required this.createdAt,
    this.triggers = const <String>[],
    this.pending = false,
  });

  final String id;
  final String viceID;
  final int quantity;
  final String ownerID;
  final Timestamp createdAt;
  // Paths in lib/data/trigger_tree.dart or free-text labels; empty for an
  // activity logged without any.
  final List<String> triggers;
  // A local write the server has not acknowledged yet.
  final bool pending;

  factory ViceActivity.fromJson({
    required String id,
    required Map<String, dynamic> json,
    bool pending = false,
  }) => ViceActivity(
    id: id,
    viceID: readString(json['viceID']),
    quantity: readInt(json['quantity']),
    ownerID: readString(json['ownerID']),
    createdAt: readTimestamp(json['createdAt'], pending: pending),
    triggers: readTriggers(json[triggersField]),
    pending: pending,
  );

  static List<ViceActivity> fromQuerySnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return snapshot.docs.map((doc) {
      return ViceActivity.fromJson(
        id: doc.id,
        json: doc.data(),
        pending: doc.metadata.hasPendingWrites,
      );
    }).toList();
  }
}
