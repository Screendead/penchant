import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The field that holds a document's sealed contents, as bytes.
const String sealedField = 'sealed';

/// The plaintext fields each collection seals. They are deleted in the same
/// update that adds [sealedField] (firestore.rules, `sealsPlaintext`).
const Map<String, List<String>> plaintextFields = <String, List<String>>{
  'vices': <String>['name', 'unit'],
  'activities': <String>['quantity'],
};

/// Seals a document's plaintext fields with the signed-in user's key. The
/// cipher binds the result to the document, so a sealed value copied onto
/// another document does not open.
abstract interface class Sealer {
  Future<Uint8List> seal({
    required String collection,
    required String docId,
    required String ownerID,
    String? viceID,
    required Map<String, Object?> fields,
  });
}

/// The signed-in user's sealer, or null while no key is on the device. Null
/// until the crypto core supplies one, so nothing is sealed before then.
final sealerProvider = Provider<Sealer?>((ref) => null);
