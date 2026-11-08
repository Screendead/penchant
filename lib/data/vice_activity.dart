import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tracker/data/activity_triggers.dart';
import 'package:tracker/data/json_fields.dart';
import 'package:tracker/data/sealed.dart';

typedef StoredMeasure = ({int quantity, double? amount});

// How a typed value is written: a whole number as quantity alone, the shape
// every build reads; anything finer also as amount, with quantity rounded up
// so that a build reading quantity alone still counts it. [keepAmount] is for
// an entry that already carries an amount, which a whole number then replaces.
StoredMeasure storedMeasure(num value, {bool keepAmount = false}) =>
    value is int && !keepAmount
    ? (quantity: value, amount: null)
    : (quantity: max(1, value.ceil()), amount: value.toDouble());

class ViceActivity {
  ViceActivity({
    required this.id,
    required this.viceID,
    required this.quantity,
    required this.ownerID,
    required this.createdAt,
    this.amount,
    this.triggers = const <String>[],
    this.pending = false,
    this.locked = false,
  });

  final String id;
  final String viceID;
  final int quantity;
  // Optional and finer than [quantity], which a client writing it sets to the
  // amount rounded up, so that builds reading only quantity stay close.
  final double? amount;
  final String ownerID;
  final Timestamp createdAt;
  // Paths in lib/data/trigger_tree.dart or free-text labels; empty for an
  // activity logged without any.
  final List<String> triggers;
  // A local write the server has not acknowledged yet.
  final bool pending;
  // Sealed fields this device could not open, which must never be written
  // back. The quantity stays plaintext (Jack, 2026-11-06), so it is real.
  final bool locked;

  // What charts, totals and labels count. Every write of an amount sets
  // quantity to storedMeasure's rounding of it, so a quantity that disagrees
  // was edited later by a build that knows nothing of amount, and wins.
  num get measure {
    final double? amount = this.amount;
    return amount != null && quantity == max(1, amount.ceil())
        ? amount
        : quantity;
  }

  factory ViceActivity.fromJson({
    required String id,
    required Map<String, dynamic> json,
    bool pending = false,
    Map<String, Object?>? opened,
  }) {
    final bool locked = isSealed(json) && opened == null;
    return ViceActivity(
      id: id,
      viceID: readString(json['viceID']),
      quantity: readInt(json['quantity']),
      amount: readAmount(json['amount']),
      ownerID: readString(json['ownerID']),
      createdAt: readTimestamp(json['createdAt'], pending: pending),
      triggers: readTriggers(contentOf(json, opened)[triggersField]),
      pending: pending,
      locked: locked,
    );
  }

  static Future<ViceActivity> open(
    DocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, dynamic> json,
    SealedOpener opener,
  ) async => ViceActivity.fromJson(
    id: doc.id,
    json: json,
    pending: doc.metadata.hasPendingWrites,
    opened: await opener.open('activities', doc.id, json),
  );

  static Future<List<ViceActivity>> openQuerySnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    SealedOpener opener,
  ) => Future.wait(
    snapshot.docs.map((doc) => ViceActivity.open(doc, doc.data(), opener)),
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
