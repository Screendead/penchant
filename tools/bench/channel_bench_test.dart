// Times JournalCipher through cryptography_flutter's platform channel to
// CryptoKit, as the app runs it. The tracker's macOS target did not build at
// the time, so this runs in a bare host app (tools/bench/README.md).
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:e2ee_channel_bench/crypto/journal_cipher.dart';
import 'package:e2ee_channel_bench/crypto/native_aes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('channel timings', (tester) async {
    final NativeAesReport report = await checkNativeAesGcm(nativeAesGcm(secretKeyLength: 32));
    expect(report.native, isTrue, reason: '$report');

    final JournalCipher cipher = JournalCipher(
      aes: nativeAesGcm(secretKeyLength: 32),
      key: SecretKey(List<int>.generate(32, (i) => i)),
    );
    const int n = 2000;
    final List<List<int>> blobs = <List<int>>[];
    final Stopwatch seal = Stopwatch()..start();
    for (int i = 0; i < n; i++) {
      blobs.add(await cipher.seal(collection: 'activities', docId: 'a$i', ownerID: 'alice', viceID: 'v', fields: {'q': 2}));
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
    // ignore: avoid_print
    print('E2EE BENCH $report; seal x$n ${seal.elapsedMilliseconds} ms; '
        'open sequential x$n ${open.elapsedMilliseconds} ms; '
        'open Future.wait x$n ${parallel.elapsedMilliseconds} ms');
  });
}
