// Pure-Dart timings on the host: the path flutter test takes, since the
// CryptoKit plugin is absent here. tools/bench/cryptokit_bench.swift times the
// native primitive on the same Mac.
// E2EE_BENCH=1 flutter test test/bench/e2ee_bench_test.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/crypto/journal_cipher.dart';
import 'package:tracker/crypto/key_service.dart';
import 'package:tracker/crypto/recovery_key.dart';

import '../crypto/fakes.dart';

String _us(Duration d, int n) => '${(d.inMicroseconds / n).toStringAsFixed(1)} us';

void main() {
  final bool run = Platform.environment['E2EE_BENCH'] != null;

  test('timings', skip: !run, () async {
    final JournalCipher cipher = JournalCipher(
      aes: AesGcm.with256bits(),
      key: SecretKey(List<int>.generate(32, (i) => i)),
    );
    const int n = 2000;

    final List<Uint8List> blobs = <Uint8List>[];
    final Stopwatch seal = Stopwatch()..start();
    for (int i = 0; i < n; i++) {
      blobs.add(await cipher.seal(
        collection: 'activities', docId: 'a$i', ownerID: 'alice', viceID: 'v', fields: {'q': i % 5 + 1},
      ));
    }
    seal.stop();

    final Stopwatch open = Stopwatch()..start();
    for (int i = 0; i < n; i++) {
      await cipher.open(collection: 'activities', docId: 'a$i', ownerID: 'alice', viceID: 'v', blob: blobs[i]);
    }
    open.stop();

    final Stopwatch parallel = Stopwatch()..start();
    await Future.wait([
      for (int i = 0; i < n; i++)
        cipher.open(collection: 'activities', docId: 'a$i', ownerID: 'alice', viceID: 'v', blob: blobs[i]),
    ]);
    parallel.stop();

    final Uint8List vice = await cipher.seal(
      collection: 'vices', docId: 'v', ownerID: 'alice', fields: {'n': 'Coffee', 'u': 'drink'},
    );
    final Stopwatch viceOpen = Stopwatch()..start();
    for (int i = 0; i < 200; i++) {
      await cipher.open(collection: 'vices', docId: 'v', ownerID: 'alice', blob: vice);
    }
    viceOpen.stop();

    final KeyService service = KeyService(
      store: FakeKeyStore(), remote: FakeKeysRemote(),
      aes256: AesGcm.with256bits(), aes128: AesGcm.with128bits(), random: Random(1),
    );
    final Stopwatch setUp = Stopwatch()..start();
    final KeyReady ready = await service.setUp('alice');
    setUp.stop();

    final KeyService other = KeyService(
      store: FakeKeyStore(), remote: service.remote,
      aes256: AesGcm.with256bits(), aes128: AesGcm.with128bits(),
    );
    final Stopwatch unlock = Stopwatch()..start();
    await other.unlock('alice', ready.stored.recoveryKey!);
    unlock.stop();

    final String plain = RecoveryKey.normalise(ready.stored.recoveryKey!);
    final String typo = plain.replaceRange(20, 21, plain[20] == 'X' ? 'Y' : 'X');
    final Stopwatch locate = Stopwatch()..start();
    RecoveryKey.parse(typo);
    locate.stop();

    // ignore: avoid_print
    print([
      'seal activity (93 B), sequential x$n: ${seal.elapsedMilliseconds} ms, ${_us(seal.elapsed, n)} each',
      'open activity (93 B), sequential x$n: ${open.elapsedMilliseconds} ms, ${_us(open.elapsed, n)} each',
      'open activity (93 B), Future.wait x$n: ${parallel.elapsedMilliseconds} ms',
      'open vice (285 B) x200: ${_us(viceOpen.elapsed, 200)} each',
      'setUp (mint, check seal, recovery wrap; fake remote): ${setUp.elapsedMicroseconds} us',
      'unlock with recovery key (unwrap, check; fake remote): ${unlock.elapsedMicroseconds} us',
      'locate one typo (up to 992 SHA-256): ${locate.elapsedMicroseconds} us',
    ].join('\n'));
  });
}
