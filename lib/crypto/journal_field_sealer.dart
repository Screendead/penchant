import 'dart:convert';
import 'dart:typed_data';

import 'package:tracker/crypto/sealed_files.dart';
import 'package:tracker/crypto/sealer.dart';
import 'package:tracker/data/sealed.dart';

/// The one [FieldSealer]: the journal key's [Sealer], with the document path
/// as associated data, so an envelope copied onto another document fails as
/// [SealFailure.notAuthentic]. It seals device files with the same key.
class JournalFieldSealer implements FieldSealer, FileSealer {
  JournalFieldSealer(this._sealer);

  final Sealer _sealer;

  @override
  Future<Uint8List> seal(
    Map<String, Object?> fields, {
    required String context,
  }) => _sealer.sealFields(fields, aad: utf8.encode(context));

  @override
  Future<Map<String, Object?>> open(
    Uint8List envelope, {
    required String context,
  }) => _sealer.openFields(envelope, aad: utf8.encode(context));

  @override
  Future<Uint8List> sealFile(List<int> bytes, {required String context}) =>
      _sealer.sealFile(bytes, aad: utf8.encode(context));

  @override
  Future<Uint8List> openFile(List<int> envelope, {required String context}) =>
      _sealer.openFile(envelope, aad: utf8.encode(context));
}
