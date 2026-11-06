import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/crypto/journal_key.dart';
import 'package:tracker/crypto/recovery_key.dart';
import 'package:tracker/crypto/sealer.dart';

void main() {
  final AesGcm aes128 = AesGcm.with128bits();
  final JournalKey key = JournalKey.generate(Random(3));
  final Uint8List recovery = RecoveryKey.generate(Random(4));

  test('generates 256-bit keys that differ', () {
    expect(JournalKey.generate().bytes, hasLength(32));
    expect(JournalKey.generate().sameAs(JournalKey.generate()), isFalse);
  });

  test('refuses a key of the wrong length', () {
    expect(() => JournalKey(List<int>.filled(16, 0)), throwsArgumentError);
  });

  test('unwraps with the recovery key it was wrapped under', () async {
    final Uint8List wrapped = await key.wrap(
      aes128: aes128,
      recoveryKey: recovery,
      uid: 'u1',
    );
    final JournalKey back = await JournalKey.unwrap(
      wrapped,
      aes128: aes128,
      recoveryKey: recovery,
      uid: 'u1',
    );
    expect(back.sameAs(key), isTrue);
  });

  test('a valid recovery key for another journal does not unwrap', () async {
    final Uint8List wrapped = await key.wrap(
      aes128: aes128,
      recoveryKey: recovery,
      uid: 'u1',
    );
    await expectLater(
      JournalKey.unwrap(
        wrapped,
        aes128: aes128,
        recoveryKey: RecoveryKey.generate(Random(5)),
        uid: 'u1',
      ),
      throwsA(isA<SealException>()),
    );
  });

  test("another user's wrapped key does not unwrap", () async {
    final Uint8List wrapped = await key.wrap(
      aes128: aes128,
      recoveryKey: recovery,
      uid: 'u1',
    );
    await expectLater(
      JournalKey.unwrap(
        wrapped,
        aes128: aes128,
        recoveryKey: recovery,
        uid: 'u2',
      ),
      throwsA(isA<SealException>()),
    );
  });

  test('a recovery key that came through its typed form unwraps', () async {
    final Uint8List wrapped = await key.wrap(
      aes128: aes128,
      recoveryKey: recovery,
      uid: 'u1',
    );
    final RecoveryKeyParse typed = RecoveryKey.parse(
      RecoveryKey.format(recovery).toLowerCase(),
    );
    final JournalKey back = await JournalKey.unwrap(
      wrapped,
      aes128: aes128,
      recoveryKey: (typed as RecoveryKeyOk).key,
      uid: 'u1',
    );
    expect(back.sameAs(key), isTrue);
  });
}
