import 'package:cloud_firestore/cloud_firestore.dart' hide Settings;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tracker/crypto/journal_key.dart';
import 'package:tracker/crypto/key_service.dart';
import 'package:tracker/crypto/key_store.dart';
import 'package:tracker/crypto/native_aes.dart';
import 'package:tracker/crypto/recovery_key.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/manage_data.dart';
import 'package:tracker/main.dart' as app;

import 'support.dart';

const GetOptions _server = GetOptions(source: Source.server);

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await clearEmulators();
  });

  testWidgets('register, add a vice, record an activity, see it listed, '
      'sealed under a key made in the keychain', (WidgetTester tester) async {
    app.startApp();
    // MyApp is built only once Bootstrap has started Firebase.
    await pumpUntil(tester, find.byType(app.MyApp));
    await register(tester, 'e2e@example.com');
    final String uid = FirebaseAuth.instance.currentUser!.uid;
    addTearDown(() => KeyStore().delete(uid));
    await addVicesThroughManageData(tester);

    await recordActivity(tester, 'Coffee', 2);
    await expectTallies(tester, const <String>{
      'Coffee (2 drinks)',
      'Tea (0 drinks)',
      'Water (0 drinks)',
    });

    await openFromMenu(tester, Homepage.habitsItem);
    await pumpUntil(tester, find.byType(ManageData));
    // Each row's count is its own server request, so the rows fill in any order.
    await pumpUntil(tester, habitsCount('1 entry'));
    await pumpUntilTrue(
      tester,
      () => habitsCount('0 entries').evaluate().length == 2,
      () => "two '0 entries' rows",
    );
    for (final String name in <String>['Coffee', 'Tea', 'Water']) {
      expect(
        find.descendant(of: find.byType(ManageData), matching: find.text(name)),
        findsOneWidget,
      );
    }

    // The first launch made a key in the keychain and records only its id
    // and wrapped copy.
    final StoredKey stored = (await KeyStore().read(uid))!;
    debugPrint('E2EE key service stored the key: ${stored.location.name}');
    final Map<String, dynamic> record =
        (await FirebaseFirestore.instance.doc('keys/$uid').get(_server))
            .data()!;
    expect(record.keys.toSet(), <String>{
      'keyID',
      'wrapped',
      'createdAt',
      'saved',
      'cardDismissed',
    });
    expect(record['keyID'], keyIDOf(stored.journalKey));
    await FirebaseFirestore.instance.waitForPendingWrites().timeout(timeout);
    final QuerySnapshot<Map<String, dynamic>> vices = await FirebaseFirestore
        .instance
        .collection('vices')
        .where('ownerID', isEqualTo: uid)
        .get(_server);
    expect(vices.docs, hasLength(3));
    for (final QueryDocumentSnapshot<Map<String, dynamic>> vice in vices.docs) {
      expect(vice.data().containsKey(sealedField), isTrue);
      expect(vice.data().containsKey('name'), isFalse);
    }

    // Settings shows the version the binary was built with.
    await closeMenuPage(tester);
    await openFromMenu(tester, Homepage.settingsItem);
    final PackageInfo info = await PackageInfo.fromPlatform();
    expect(info.version, matches(RegExp(r'^\d+\.\d+\.\d+$')));
    await pumpUntil(tester, find.text('${info.version} (${info.buildNumber})'));
  });

  // Here rather than in a file of their own: on macOS each file rebuilds the
  // app.
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
