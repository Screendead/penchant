import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tracker/data/category.dart';
import 'package:tracker/data/json_fields.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/data/unit.dart';

class Vice {
  Vice({
    required this.id,
    required this.name,
    required this.unit,
    required this.ownerID,
    required this.createdAt,
    required this.archived,
    this.locked = false,
    this.category = ViceCategory.fallback,
    this.categoryStored = true,
    this.unitLabel,
    this.unitSingular,
    this.costPerUnit,
    this.currency,
  });

  final String id;
  final String name;
  final Unit unit;
  final String ownerID;
  final Timestamp createdAt;
  final bool archived;
  // Sealed fields this device could not open: [name], [unit] and [category]
  // are placeholders, and must never be written back.
  final bool locked;
  final ViceCategory category;
  // False for a document written before the field, which the category
  // migration fills in. An unknown name counts as stored: a later version
  // wrote it. A locked vice counts as stored, so nothing writes to it.
  final bool categoryStored;
  // Optional, sealed only. An older build that edits the name, unit or
  // category reseals without them, so each may vanish: null falls back to the
  // preset's words and no spend.
  final String? unitLabel;
  // [unitLabel]'s form for one (cup for cups); ignored without a label.
  final String? unitSingular;
  final double? costPerUnit;
  // ISO 4217; a cost without one is shown as a plain number.
  final String? currency;

  UnitWords get units => UnitWords(unit, unitLabel, unitSingular);

  // What [measure] of this habit cost, or null when it has no price.
  double? spendOf(double measure) {
    final double? cost = costPerUnit;
    return cost == null ? null : measure * cost;
  }

  factory Vice.fromJson({
    required String id,
    required Map<String, dynamic> json,
    bool pending = false,
    Map<String, Object?>? opened,
  }) {
    final bool locked = isSealed(json) && opened == null;
    final Map<String, Object?> content = contentOf(json, opened);
    return Vice(
      id: id,
      name: locked ? lockedViceName : readString(content['name']),
      unit: Unit.fromString(content['unit']),
      ownerID: readString(json['ownerID']),
      createdAt: readTimestamp(json['createdAt'], pending: pending),
      archived: readBool(json['archived'], fallback: false),
      locked: locked,
      category: ViceCategory.fromString(content['category']),
      categoryStored: locked || content['category'] is String,
      unitLabel: readUnitLabel(content['unitLabel']),
      unitSingular: readUnitLabel(content['unitSingular']),
      costPerUnit: readCostPerUnit(content['costPerUnit']),
      currency: readCurrency(content['currency']),
    );
  }

  static Future<List<Vice>> openQuerySnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    SealedOpener opener,
  ) {
    return Future.wait(
      snapshot.docs.map((doc) async {
        final Map<String, dynamic> json = doc.data();
        return Vice.fromJson(
          id: doc.id,
          json: json,
          pending: doc.metadata.hasPendingWrites,
          opened: await opener.open('vices', doc.id, json),
        );
      }),
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
