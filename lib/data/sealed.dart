import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/errors/report_error.dart';

/// The field that holds a document's content fields (a vice's name and unit,
/// an activity's quantity) once sealed. The structural fields every query and
/// rule needs (ownerID, createdAt, viceID, archived) stay beside it in
/// plaintext.
const String sealedField = 'sealed';

/// Shown for a vice whose sealed fields this device cannot open.
const String lockedViceName = 'Locked habit';

/// Seals and opens the content fields of one document with the user's key.
/// [context] names the document (`vices/{id}`), so an envelope copied onto
/// another document fails to open.
abstract interface class FieldSealer {
  Future<String> seal(Map<String, Object?> fields, {required String context});

  Future<Map<String, Object?>> open(String envelope, {required String context});
}

/// Null while no key is available, and then writes stay plaintext. The key
/// work (r2-e2ee-crypto-core) overrides this.
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
      if (envelope is! String) {
        throw const FormatException('the sealed field is not a string');
      }
      if (sealer == null) {
        throw StateError('no key on this device');
      }
      return await sealer.open(envelope, context: context);
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
