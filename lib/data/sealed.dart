import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/errors/report_error.dart';

/// The field that holds a document's content fields (a vice's name, unit,
/// category, unit label and its singular, cost per unit and currency, an activity's triggers)
/// once sealed. The structural fields every query and rule needs (ownerID,
/// createdAt, viceID, archived) stay beside it in plaintext.
const String sealedField = 'sealed';

/// The content fields each collection seals. firestore.rules lists the same
/// fields (`sealedAlone`, `changedContent`), and so must every content field
/// added later. An activity's quantity and decimal amount stay plaintext
/// (Jack, 2026-11-06), so a server-side job can aggregate them.
const List<String> viceContentFields = <String>[
  'name',
  'unit',
  'category',
  'unitLabel',
  'unitSingular',
  'costPerUnit',
  'currency',
];
const List<String> activityContentFields = <String>['triggers'];

const Map<String, List<String>> contentFields = <String, List<String>>{
  'vices': viceContentFields,
  'activities': activityContentFields,
};

/// Shown for a vice whose sealed fields this device cannot open.
const String lockedViceName = 'Locked habit';

/// Seals and opens the content fields of one document with the user's key.
/// [context] names the document (`vices/{id}`), so an envelope copied onto
/// another document fails to open.
abstract interface class FieldSealer {
  Future<Uint8List> seal(
    Map<String, Object?> fields, {
    required String context,
  });

  Future<Map<String, Object?>> open(
    Uint8List envelope, {
    required String context,
  });
}

/// Null while no key is available: updates stay plaintext and nothing can be
/// created (TrackerWrites.canCreate). Only the key service overrides it, and
/// only while `e2eeEnabled` is true.
final sealerProvider = Provider<FieldSealer?>((ref) => null);

String sealContext(String collection, String id) => '$collection/$id';

/// Opens the sealed fields of the documents one listener receives. It never
/// throws, and reports each document it cannot open once.
class SealedOpener {
  SealedOpener(this.sealer);

  final FieldSealer? sealer;
  final Set<String> _reported = <String>{};

  /// Null for a plaintext document, and for a sealed one that will not open;
  /// [isSealed] tells them apart.
  Future<Map<String, Object?>?> open(
    String collection,
    String id,
    Map<String, dynamic> json,
  ) async {
    if (!isSealed(json)) {
      return null;
    }
    final String context = sealContext(collection, id);
    try {
      final Object? envelope = json[sealedField];
      final FieldSealer? sealer = this.sealer;
      if (envelope is! Blob) {
        throw const FormatException('the sealed field is not bytes');
      }
      if (sealer == null) {
        throw StateError('no key on this device');
      }
      return await sealer.open(envelope.bytes, context: context);
    } catch (e, stack) {
      if (_reported.add(context)) {
        reportError(e, stack, context: 'while opening $context');
      }
      return null;
    }
  }
}

bool isSealed(Map<String, dynamic> json) => json.containsKey(sealedField);

/// The map a parser reads content fields from: the document itself when it is
/// plaintext, the opened fields when sealed, or nothing when they would not
/// open.
Map<String, Object?> contentOf(
  Map<String, dynamic> json,
  Map<String, Object?>? opened,
) => isSealed(json) ? (opened ?? const <String, Object?>{}) : json;

/// [json] with its envelope replaced by the [opened] fields, or unchanged
/// when there are none.
Map<String, dynamic> unsealed(
  Map<String, dynamic> json,
  Map<String, Object?>? opened,
) => opened == null
    ? json
    : <String, dynamic>{
        for (final MapEntry<String, dynamic>(:key, :value) in json.entries)
          if (key != sealedField) key: value,
        ...opened,
      };
