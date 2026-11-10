import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/errors/report_error.dart';

/// The field that holds a document's content fields (a vice's name, unit and
/// category, an activity's triggers) once sealed. The structural fields every query and
/// rule needs (ownerID, createdAt, viceID, archived) stay beside it in
/// plaintext.
const String sealedField = 'sealed';

/// The content fields each collection seals. firestore.rules lists the same
/// fields (`sealedAlone`, `changedContent`), and so must every content field
/// added later. An activity's quantity and decimal amount stay plaintext
/// (Jack, 2026-11-06), so a server-side job can aggregate them.
const List<String> viceContentFields = <String>['name', 'unit', 'category'];
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

/// Inside an activity's envelope beside its content: [activityBinding] of the
/// plaintext fields stored next to the envelope when it was sealed. The key
/// is no content field, so a build that predates it opens the envelope and
/// ignores it.
const String boundField = 'b';

/// Whether an activity's plaintext fields are the ones its envelope was
/// sealed with. Only [intact] and [altered] come from an envelope carrying
/// [boundField]; an older envelope, a plaintext document and a locked one
/// are [unbound].
enum SealBinding { unbound, intact, altered }

/// 16 bytes of SHA-256 over the fields, base64url: short enough that an
/// entry without triggers stays in the 64-byte bucket. It needs no key of
/// its own, since only the journal key can put it inside an envelope.
String activityBinding({
  required int createdAtMicros,
  required String viceID,
  required int quantity,
  required double? amount,
}) {
  final List<int> digest = const DartSha256()
      .hashSync(
        utf8.encode(
          jsonEncode(<Object?>[
            createdAtMicros,
            viceID,
            quantity,
            amount?.toString(),
          ]),
        ),
      )
      .bytes;
  return base64Url.encode(digest.sublist(0, 16)).replaceAll('=', '');
}

SealBinding checkBinding(Map<String, Object?>? opened, String expected) {
  if (opened == null || !opened.containsKey(boundField)) {
    return SealBinding.unbound;
  }
  return opened[boundField] == expected
      ? SealBinding.intact
      : SealBinding.altered;
}

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

/// [json] with its envelope replaced by the [opened] content fields, or
/// unchanged when there are none.
Map<String, dynamic> unsealed(
  Map<String, dynamic> json,
  Map<String, Object?>? opened,
) => opened == null
    ? json
    : <String, dynamic>{
        for (final MapEntry<String, dynamic>(:key, :value) in json.entries)
          if (key != sealedField) key: value,
        for (final MapEntry<String, Object?>(:key, :value) in opened.entries)
          if (key != boundField) key: value,
      };
