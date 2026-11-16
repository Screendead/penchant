import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:tracker/crypto/journal_field_sealer.dart';
import 'package:tracker/crypto/sealed_files.dart';
import 'package:tracker/crypto/sealer.dart';
import 'package:tracker/data/sealed.dart';

// The app's real envelope under a fixed key, with AES-GCM in Dart rather than
// CryptoKit, so tests on any host and the e2e tests share one format.
class FakeSealer implements FieldSealer {
  FakeSealer({int keyByte = 7})
    : _real = JournalFieldSealer(
        Sealer(aes: AesGcm.with256bits(), key: List<int>.filled(32, keyByte)),
      );

  final JournalFieldSealer _real;
  final List<String> opened = <String>[];

  @override
  Future<Uint8List> seal(
    Map<String, Object?> fields, {
    required String context,
  }) => _real.seal(fields, context: context);

  @override
  Future<Map<String, Object?>> open(
    Uint8List envelope, {
    required String context,
  }) async {
    final Map<String, Object?> fields = await _real.open(
      envelope,
      context: context,
    );
    opened.add(context);
    return fields;
  }
}

// The same envelope for whole device files, apart from [FakeSealer] so that
// overriding sealerProvider with one does not turn on the device files in
// tests that never set their folders.
class FakeFileSealer implements FileSealer {
  FakeFileSealer({int keyByte = 7})
    : _real = JournalFieldSealer(
        Sealer(aes: AesGcm.with256bits(), key: List<int>.filled(32, keyByte)),
      );

  final JournalFieldSealer _real;

  @override
  Future<Uint8List> sealFile(List<int> bytes, {required String context}) =>
      _real.sealFile(bytes, context: context);

  @override
  Future<Uint8List> openFile(List<int> envelope, {required String context}) =>
      _real.openFile(envelope, context: context);
}
