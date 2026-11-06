import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:tracker/crypto/sealer.dart';

/// The one random AES-256 data key a user's journal is sealed with.
class JournalKey {
  JournalKey(List<int> bytes) : bytes = Uint8List.fromList(bytes) {
    if (bytes.length != length) {
      throw ArgumentError('A journal key is $length bytes');
    }
  }

  factory JournalKey.generate([Random? random]) {
    final Random source = random ?? Random.secure();
    return JournalKey(List<int>.generate(length, (_) => source.nextInt(256)));
  }

  static const int length = 32;

  final Uint8List bytes;

  Sealer sealer(AesGcm aes256) => Sealer(aes: aes256, key: bytes);

  bool sameAs(JournalKey other) {
    int diff = 0;
    for (int i = 0; i < length; i++) {
      diff |= bytes[i] ^ other.bytes[i];
    }
    return diff == 0;
  }

  /// Seals this key under [recoveryKey], bound to [uid], so the wrapped copy
  /// opens only for that user. Unwrapping needs only the recovery key, which
  /// the user holds; the wrapped copy alone reveals nothing.
  Future<Uint8List> wrap({
    required AesGcm aes128,
    required List<int> recoveryKey,
    required String uid,
  }) => Sealer(aes: aes128, key: recoveryKey).seal(bytes, aad: wrapAad(uid));

  /// Throws [SealException] (`notAuthentic`) for another user's wrap or a
  /// recovery key that is valid but not this journal's.
  static Future<JournalKey> unwrap(
    List<int> wrapped, {
    required AesGcm aes128,
    required List<int> recoveryKey,
    required String uid,
  }) async {
    final Uint8List opened = await Sealer(
      aes: aes128,
      key: recoveryKey,
    ).open(wrapped, aad: wrapAad(uid));

    if (opened.length != length) {
      throw SealException(
        SealFailure.badPlaintext,
        'The wrapped key is ${opened.length} bytes',
      );
    }

    return JournalKey(opened);
  }

  static List<int> wrapAad(String uid) =>
      utf8.encode('penchant:v1:journal-key-wrap:$uid');
}
