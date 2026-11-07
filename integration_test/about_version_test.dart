import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tracker/crypto/journal_key.dart';
import 'package:tracker/crypto/key_store.dart';
import 'package:tracker/crypto/native_aes.dart';
import 'package:tracker/crypto/recovery_key.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/main.dart' as app;

import 'support.dart';

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await clearEmulators();
  });

  testWidgets('Settings shows the version the binary was built with', (
    WidgetTester tester,
  ) async {
    app.startApp();
    // MyApp is built only once Bootstrap has started Firebase.
    await pumpUntil(tester, find.byType(app.MyApp));
    await register(tester, 'about@example.com');

    await openFromMenu(tester, Homepage.settingsItem);
    final PackageInfo info = await PackageInfo.fromPlatform();
    expect(info.version, matches(RegExp(r'^\d+\.\d+\.\d+$')));
    await pumpUntil(tester, find.text('${info.version} (${info.buildNumber})'));
  });

  // Run here rather than in a file of their own: each file rebuilds the app.
  testWidgets('the keychain keeps a journal key per uid', (
    WidgetTester tester,
  ) async {
    final KeyStore store = KeyStore();
    const String uid = 'e2e-keychain-probe';
    await store.delete(uid);

    final JournalKey key = JournalKey.generate();
    final StoredKey saved = await store.save(
      uid,
      journalKey: key,
      recoveryKey: RecoveryKey.generate(),
    );
    // The CI log records where the key landed: synced or thisDevice.
    debugPrint('E2EE journal key stored: ${saved.location.name}');

    final StoredKey read = (await store.read(uid))!;
    expect(read.journalKey.sameAs(key), isTrue);
    expect(read.recoveryKey, saved.recoveryKey);
    expect(read.location, saved.location);
    await expectLater(
      store.save(uid, journalKey: JournalKey.generate()),
      throwsA(isA<KeyConflictException>()),
    );

    await store.delete(uid);
    expect(await store.read(uid), isNull);
  });

  testWidgets('AES-GCM runs in CryptoKit, not Dart', (
    WidgetTester tester,
  ) async {
    final NativeAesReport report = await checkNativeAesGcm(
      nativeAesGcm(secretKeyLength: 32),
    );
    debugPrint('E2EE $report');
    expect(report.native, isTrue, reason: '$report');
  });
}
