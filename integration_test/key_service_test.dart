import 'package:cloud_firestore/cloud_firestore.dart' hide Settings;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/crypto/e2ee_enabled.dart';
import 'package:tracker/crypto/key_service.dart';
import 'package:tracker/crypto/key_store.dart';
import 'package:tracker/crypto/key_wiring.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/main.dart';

import 'support.dart';

const GetOptions _server = GetOptions(source: Source.server);

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('with E2EE on, the first launch makes a key in the keychain, '
      'records only its id and wrapped copy, and seals with it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...keyServiceOverrides,
          e2eeEnabledProvider.overrideWithValue(true),
        ],
        child: const MyApp(),
      ),
    );
    await register(tester, 'e2e-key-service@example.com');
    final String uid = FirebaseAuth.instance.currentUser!.uid;
    addTearDown(() => KeyStore().delete(uid));

    await addVicesThroughManageData(tester, const <String>['Coffee']);
    await recordActivity(tester, 'Coffee', 1);
    await expectTallies(tester, const <String>{'Coffee (1 drink)'});

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
    final Map<String, dynamic> vice = vices.docs.single.data();
    expect(vice.containsKey(sealedField), isTrue);
    expect(vice.containsKey('name'), isFalse);
  });
}
