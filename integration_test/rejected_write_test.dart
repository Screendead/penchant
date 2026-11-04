import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/main.dart';
import 'package:tracker/widgets/rejected_writes_banner.dart';
import 'package:tracker/widgets/sync_status.dart';
import 'package:tracker/writes/settle_write.dart';

import 'support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('an entry saved offline that the server refuses on reconnect '
      'is named on screen until dismissed', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, 'e2e-rejected@example.com');
    await addVicesThroughManageData(tester);
    final String coffeeID = await storedViceID('Coffee');
    final Finder banner = find.byType(RejectedWritesBanner);
    Finder inBanner(String text) =>
        find.descendant(of: banner, matching: find.textContaining(text));
    final Finder rejected = inBanner('Not saved: Coffee, 2 drinks, ');

    await FirebaseFirestore.instance.disableNetwork();
    try {
      await pumpUntil(tester, find.text(OfflineBanner.message));
      await recordActivity(tester, 'Coffee', 2);
      // The dialog has given up waiting and called the entry queued, so the
      // refusal below reaches nothing that is still listening for it.
      await pumpUntil(tester, find.text(queuedMessage));
      expect(rejected, findsNothing);
      // Another device deletes the vice meanwhile, so the rules' ownership
      // get() fails when the entry reaches the server.
      await deleteBypassingRules('vices', coffeeID);
    } finally {
      await FirebaseFirestore.instance.enableNetwork();
    }

    await pumpUntil(tester, rejected);
    expect(inBanner('The server refused this change.'), findsOneWidget);
    await screenshot(tester, 'rejected-write-banner');

    final QuerySnapshot<Map<String, dynamic>> stored = await FirebaseFirestore
        .instance
        .collection('activities')
        .where('ownerID', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
        .get(const GetOptions(source: Source.server));
    expect(stored.docs, isEmpty);

    await tap(
      tester,
      find.descendant(
        of: banner,
        matching: find.text(RejectedWritesBanner.dismissLabel),
      ),
    );
    await pumpUntil(tester, rejected, present: false);
  });

  testWidgets('an Undo of an entry the server refuses is not called not '
      'deleted', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, 'e2e-rejected-undo@example.com');
    await addVicesThroughManageData(tester);
    final String coffeeID = await storedViceID('Coffee');
    final Finder banner = find.byType(RejectedWritesBanner);
    Finder inBanner(String text) =>
        find.descendant(of: banner, matching: find.textContaining(text));

    await FirebaseFirestore.instance.disableNetwork();
    try {
      await pumpUntil(tester, find.text(OfflineBanner.message));
      await recordActivity(tester, 'Coffee', 2);
      await pumpUntil(tester, find.text(queuedMessage));
      await tap(tester, find.text('Undo'));
      // The Undo has given up waiting too, so its refusal goes to the banner
      // rather than to a snackbar.
      await pumpUntil(tester, find.text(queuedDeleteMessage));
      await deleteBypassingRules('vices', coffeeID);
    } finally {
      await FirebaseFirestore.instance.enableNetwork();
    }

    await pumpUntil(tester, inBanner('Not saved: Coffee, 2 drinks, '));
    // Settles once the server has answered the delete as well.
    await FirebaseFirestore.instance.waitForPendingWrites();
    await pumpFor(tester, const Duration(seconds: 1));
    expect(inBanner('Not deleted'), findsNothing);
  });
}
