import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class JournalCipherException implements Exception {
  JournalCipherException(this.message);

  final String message;

  @override
  String toString() => 'JournalCipherException: $message';
}

/// Seals a document's private fields into one `enc` blob:
/// `version(1) | nonce(12) | AES-256-GCM ciphertext | tag(16)`.
///
/// The plaintext is a 2-byte big-endian length, the JSON, then zeros up to a
/// fixed bucket, so the stored size reveals only the bucket. firestore.rules
/// accepts exactly [blobLengths].
class JournalCipher {
  JournalCipher({required this.aes, required SecretKey key}) : _key = key {
    if (aes.secretKeyLength != 32) {
      throw ArgumentError('JournalCipher needs AES-256-GCM');
    }
  }

  final AesGcm aes;
  final SecretKey _key;

  static const int version = 1;
  static const int nonceLength = 12;
  static const int tagLength = 16;
  static const int overhead = 1 + nonceLength + tagLength;

  /// Padded plaintext sizes. Mirrored in firestore.rules as [blobLengths].
  static const List<int> buckets = <int>[64, 256, 1024, 4096];

  /// A vice is always at least 256, which hides the length of any 60-code-unit
  /// name whose JSON, with its unit, fits 254 bytes. jsonEncode writes a
  /// control character or an unpaired surrogate as a 6-byte \uXXXX escape, so
  /// about 35 of them in one name reach the 1024 bucket; limits.dart rejects
  /// neither.
  static const Map<String, int> minimumBucket = <String, int>{
    'vices': 256,
    'activities': 64,
  };

  static List<int> get blobLengths =>
      buckets.map((int b) => b + overhead).toList(growable: false);

  static int bucketFor(int jsonLength, {int minimum = 64}) {
    for (final int bucket in buckets) {
      if (bucket >= minimum && jsonLength + 2 <= bucket) {
        return bucket;
      }
    }

    throw JournalCipherException(
      'Sealed fields are $jsonLength bytes; the largest bucket holds '
      '${buckets.last - 2}',
    );
  }

  // Document IDs are Firestore auto-IDs and owner IDs are Auth uids; neither
  // contains ':', so the fields cannot run into each other.
  static List<int> aadFor({
    required String collection,
    required String docId,
    required String ownerID,
    String? viceID,
  }) {
    final String tail = viceID == null ? '' : ':$viceID';
    return utf8.encode('tracker:v1:$collection:$docId:$ownerID$tail');
  }

  static Uint8List pad(List<int> json, int bucket) {
    final Uint8List padded = Uint8List(bucket);
    padded[0] = json.length >> 8;
    padded[1] = json.length & 0xff;
    padded.setRange(2, 2 + json.length, json);
    return padded;
  }

  static List<int> unpad(List<int> padded) {
    if (padded.length < 2) {
      throw JournalCipherException('Padded plaintext too short');
    }

    final int length = (padded[0] << 8) | padded[1];

    if (length + 2 > padded.length) {
      throw JournalCipherException('Length prefix exceeds the bucket');
    }

    return padded.sublist(2, 2 + length);
  }

  Future<Uint8List> seal({
    required String collection,
    required String docId,
    required String ownerID,
    String? viceID,
    required Map<String, Object?> fields,
  }) async {
    final List<int> json = utf8.encode(jsonEncode(fields));
    final int bucket = bucketFor(
      json.length,
      minimum: minimumBucket[collection] ?? buckets.first,
    );
    final SecretBox box = await aes.encrypt(
      pad(json, bucket),
      secretKey: _key,
      aad: aadFor(
        collection: collection,
        docId: docId,
        ownerID: ownerID,
        viceID: viceID,
      ),
    );

    final BytesBuilder out = BytesBuilder(copy: false)
      ..addByte(version)
      ..add(box.nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return out.toBytes();
  }

  /// Throws [JournalCipherException] on a wrong length or version, and
  /// [SecretBoxAuthenticationError] on a wrong key, a tampered blob or a blob
  /// moved to another document.
  Future<Map<String, dynamic>> open({
    required String collection,
    required String docId,
    required String ownerID,
    String? viceID,
    required List<int> blob,
  }) async {
    if (!blobLengths.contains(blob.length)) {
      throw JournalCipherException('Unexpected blob length ${blob.length}');
    }

    if (blob[0] != version) {
      throw JournalCipherException('Unknown blob version ${blob[0]}');
    }

    final SecretBox box = SecretBox(
      blob.sublist(1 + nonceLength, blob.length - tagLength),
      nonce: blob.sublist(1, 1 + nonceLength),
      mac: Mac(blob.sublist(blob.length - tagLength)),
    );
    final List<int> padded = await aes.decrypt(
      box,
      secretKey: _key,
      aad: aadFor(
        collection: collection,
        docId: docId,
        ownerID: ownerID,
        viceID: viceID,
      ),
    );

    return jsonDecode(utf8.decode(unpad(padded))) as Map<String, dynamic>;
  }
}
