import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

enum SealFailure {
  /// Too short to hold a version, nonce and tag.
  malformed,

  /// A version this build cannot read.
  unknownVersion,

  /// A wrong key, a changed byte, or other associated data than it was
  /// sealed with. AES-GCM cannot tell these apart.
  notAuthentic,

  /// Opened, but the padded plaintext inside is not well formed.
  badPlaintext,
}

class SealException implements Exception {
  SealException(this.failure, this.message);

  final SealFailure failure;
  final String message;

  @override
  String toString() => 'SealException(${failure.name}): $message';
}

/// AES-GCM with a fresh random 96-bit nonce per seal, written as one envelope:
/// `version(1) | nonce(12) | ciphertext | tag(16)`.
///
/// The key length is the [aes] instance's: 32 bytes for the journal key,
/// 16 for the recovery key that wraps it.
class Sealer {
  Sealer({required this.aes, required List<int> key, Random? random})
    : _key = SecretKey(List<int>.unmodifiable(key)),
      _random = random ?? Random.secure() {
    if (key.length != aes.secretKeyLength) {
      throw ArgumentError(
        'The key is ${key.length} bytes; this AES-GCM takes '
        '${aes.secretKeyLength}',
      );
    }
  }

  final AesGcm aes;
  final SecretKey _key;
  final Random _random;

  static const int version = 1;
  static const int nonceLength = 12;
  static const int tagLength = 16;
  static const int overhead = 1 + nonceLength + tagLength;

  /// Padded plaintext sizes for [sealFields], so a stored envelope's length
  /// reveals only its bucket. A future rules check on exact lengths would
  /// mirror these plus [overhead].
  static const List<int> buckets = <int>[64, 256, 1024, 4096];

  Future<Uint8List> seal(
    List<int> clearText, {
    List<int> aad = const <int>[],
  }) async {
    final List<int> nonce = List<int>.generate(
      nonceLength,
      (_) => _random.nextInt(256),
    );
    final SecretBox box = await aes.encrypt(
      clearText,
      secretKey: _key,
      nonce: nonce,
      aad: aad,
    );

    return (BytesBuilder(copy: false)
          ..addByte(version)
          ..add(box.nonce)
          ..add(box.cipherText)
          ..add(box.mac.bytes))
        .toBytes();
  }

  /// Throws [SealException]; never returns unauthenticated bytes.
  Future<Uint8List> open(
    List<int> envelope, {
    List<int> aad = const <int>[],
  }) async {
    if (envelope.length < overhead) {
      throw SealException(
        SealFailure.malformed,
        'An envelope is at least $overhead bytes; this one is '
        '${envelope.length}',
      );
    }

    if (envelope[0] != version) {
      throw SealException(
        SealFailure.unknownVersion,
        'Unknown envelope version ${envelope[0]}',
      );
    }

    final SecretBox box = SecretBox(
      envelope.sublist(1 + nonceLength, envelope.length - tagLength),
      nonce: envelope.sublist(1, 1 + nonceLength),
      mac: Mac(envelope.sublist(envelope.length - tagLength)),
    );

    try {
      return Uint8List.fromList(
        await aes.decrypt(box, secretKey: _key, aad: aad),
      );
    } on SecretBoxAuthenticationError {
      throw SealException(
        SealFailure.notAuthentic,
        'The envelope does not open with this key and associated data',
      );
    }
  }

  /// Seals [fields] as JSON padded to the smallest bucket of at least
  /// [minimumBucket] that holds it.
  Future<Uint8List> sealFields(
    Map<String, Object?> fields, {
    List<int> aad = const <int>[],
    int minimumBucket = 64,
  }) {
    final List<int> json = utf8.encode(jsonEncode(fields));
    return seal(
      pad(json, bucketFor(json.length, minimum: minimumBucket)),
      aad: aad,
    );
  }

  Future<Map<String, dynamic>> openFields(
    List<int> envelope, {
    List<int> aad = const <int>[],
  }) async {
    final List<int> json = unpad(await open(envelope, aad: aad));

    try {
      final Object? decoded = jsonDecode(utf8.decode(json));
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } on FormatException {
      // Reported below with the other shapes.
    }

    throw SealException(
      SealFailure.badPlaintext,
      'The sealed fields are not a JSON object',
    );
  }

  /// Seals a whole file's [bytes], padded by [padFile], so its length on
  /// disk reveals only a power of two. [pad]'s 2-byte prefix and [buckets]
  /// cap a document field at 4094 bytes; files are larger.
  Future<Uint8List> sealFile(
    List<int> bytes, {
    List<int> aad = const <int>[],
  }) => seal(padFile(bytes), aad: aad);

  Future<Uint8List> openFile(
    List<int> envelope, {
    List<int> aad = const <int>[],
  }) async => unpadFile(await open(envelope, aad: aad));

  static const int smallestFileBucket = 4096;

  /// A 4-byte big-endian length, the bytes, then zeros up to the smallest
  /// power of two of at least [smallestFileBucket] that holds them.
  static Uint8List padFile(List<int> bytes) {
    if (bytes.length > 0x7fffffff - 4) {
      throw ArgumentError('${bytes.length} bytes are too many for one file');
    }
    int bucket = smallestFileBucket;
    while (bucket < bytes.length + 4) {
      bucket *= 2;
    }
    return Uint8List(bucket)
      ..[0] = (bytes.length >> 24) & 0xff
      ..[1] = (bytes.length >> 16) & 0xff
      ..[2] = (bytes.length >> 8) & 0xff
      ..[3] = bytes.length & 0xff
      ..setRange(4, 4 + bytes.length, bytes);
  }

  static Uint8List unpadFile(List<int> padded) {
    if (padded.length < 4) {
      throw SealException(SealFailure.badPlaintext, 'No length prefix');
    }
    final int length =
        (padded[0] << 24) | (padded[1] << 16) | (padded[2] << 8) | padded[3];
    if (length + 4 > padded.length) {
      throw SealException(
        SealFailure.badPlaintext,
        'The length prefix exceeds the padded plaintext',
      );
    }
    return Uint8List.fromList(padded.sublist(4, 4 + length));
  }

  static int bucketFor(int jsonLength, {int minimum = 64}) {
    for (final int bucket in buckets) {
      if (bucket >= minimum && jsonLength + 2 <= bucket) {
        return bucket;
      }
    }

    throw ArgumentError(
      'The fields are $jsonLength bytes of JSON; the largest bucket holds '
      '${buckets.last - 2}',
    );
  }

  /// A 2-byte big-endian length, the bytes, then zeros up to [bucket].
  static Uint8List pad(List<int> bytes, int bucket) {
    if (bytes.length + 2 > bucket) {
      throw ArgumentError('${bytes.length} bytes do not fit $bucket');
    }

    return Uint8List(bucket)
      ..[0] = bytes.length >> 8
      ..[1] = bytes.length & 0xff
      ..setRange(2, 2 + bytes.length, bytes);
  }

  static List<int> unpad(List<int> padded) {
    if (padded.length < 2) {
      throw SealException(SealFailure.badPlaintext, 'No length prefix');
    }

    final int length = (padded[0] << 8) | padded[1];

    if (length + 2 > padded.length) {
      throw SealException(
        SealFailure.badPlaintext,
        'The length prefix exceeds the padded plaintext',
      );
    }

    return padded.sublist(2, 2 + length);
  }
}
