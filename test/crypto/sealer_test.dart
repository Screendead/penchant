import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/crypto/journal_key.dart';
import 'package:tracker/crypto/sealer.dart';

Matcher failsWith(SealFailure failure) => throwsA(
  isA<SealException>().having(
    (SealException e) => e.failure,
    'failure',
    failure,
  ),
);

void main() {
  final AesGcm aes = AesGcm.with256bits();
  final JournalKey key = JournalKey.generate(Random(1));
  final Sealer sealer = key.sealer(aes);
  final List<int> aad = utf8.encode('vices/abc');
  final List<int> clear = utf8.encode('Coffee, 2 cups');

  test('round trips', () async {
    final Uint8List envelope = await sealer.seal(clear, aad: aad);
    expect(await sealer.open(envelope, aad: aad), clear);
  });

  test('lays the envelope out as version, nonce, ciphertext, tag', () async {
    final Uint8List envelope = await sealer.seal(clear);
    expect(envelope[0], Sealer.version);
    expect(envelope.length, Sealer.overhead + clear.length);
    expect(
      utf8.decode(envelope, allowMalformed: true),
      isNot(contains('Coffee')),
    );
  });

  test('draws a fresh nonce for every seal', () async {
    final Sealer real = Sealer(aes: aes, key: key.bytes);
    final Uint8List a = await real.seal(clear);
    final Uint8List b = await real.seal(clear);
    expect(a.sublist(1, 13), isNot(b.sublist(1, 13)));
    expect(a, isNot(b));
  });

  test('a changed byte anywhere after the version fails to open', () async {
    final Uint8List envelope = await sealer.seal(clear, aad: aad);
    for (int i = 1; i < envelope.length; i++) {
      final Uint8List tampered = Uint8List.fromList(envelope)..[i] ^= 0x01;
      await expectLater(
        sealer.open(tampered, aad: aad),
        failsWith(SealFailure.notAuthentic),
        reason: 'byte $i',
      );
    }
  });

  test('an unknown version is refused before decrypting', () async {
    final Uint8List envelope = await sealer.seal(clear);
    envelope[0] = 2;
    await expectLater(
      sealer.open(envelope),
      failsWith(SealFailure.unknownVersion),
    );
  });

  test('a truncated envelope is malformed', () async {
    final Uint8List envelope = await sealer.seal(clear);
    await expectLater(
      sealer.open(envelope.sublist(0, Sealer.overhead - 1)),
      failsWith(SealFailure.malformed),
    );
  });

  test('a wrong key fails', () async {
    final Uint8List envelope = await sealer.seal(clear, aad: aad);
    final Sealer other = JournalKey.generate(Random(2)).sealer(aes);
    await expectLater(
      other.open(envelope, aad: aad),
      failsWith(SealFailure.notAuthentic),
    );
  });

  test(
    'other associated data fails, so a blob cannot move documents',
    () async {
      final Uint8List envelope = await sealer.seal(clear, aad: aad);
      await expectLater(
        sealer.open(envelope, aad: utf8.encode('vices/xyz')),
        failsWith(SealFailure.notAuthentic),
      );
    },
  );

  test('refuses a key of the wrong length', () {
    expect(
      () => Sealer(aes: aes, key: List<int>.filled(16, 0)),
      throwsArgumentError,
    );
  });

  group('fields', () {
    test('round trip through padding', () async {
      final Map<String, Object?> fields = <String, Object?>{
        'name': 'Coffee ☕',
        'unit': 'cup',
      };
      final Uint8List envelope = await sealer.sealFields(fields, aad: aad);
      expect(envelope.length, 64 + Sealer.overhead);
      expect(await sealer.openFields(envelope, aad: aad), fields);
    });

    test('pad to the minimum bucket asked for', () async {
      final Uint8List envelope = await sealer.sealFields(<String, Object?>{
        'q': 1,
      }, minimumBucket: 256);
      expect(envelope.length, 256 + Sealer.overhead);
    });

    test('fill buckets to their last byte', () {
      expect(Sealer.bucketFor(62), 64);
      expect(Sealer.bucketFor(63), 256);
      expect(Sealer.bucketFor(4094), 4096);
      expect(() => Sealer.bucketFor(4095), throwsArgumentError);
    });

    test('a sealed non-object is bad plaintext', () async {
      final Uint8List envelope = await sealer.seal(
        Sealer.pad(utf8.encode('[1]'), 64),
      );
      await expectLater(
        sealer.openFields(envelope),
        failsWith(SealFailure.badPlaintext),
      );
    });

    test('a length prefix past the bucket is bad plaintext', () async {
      final Uint8List padded = Sealer.pad(utf8.encode('{}'), 64)..[0] = 0xff;
      final Uint8List envelope = await sealer.seal(padded);
      await expectLater(
        sealer.openFields(envelope),
        failsWith(SealFailure.badPlaintext),
      );
    });
  });
}
