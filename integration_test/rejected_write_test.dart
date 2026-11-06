import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/main.dart';
import 'package:tracker/widgets/rejected_writes_banner.dart';
import 'package:tracker/widgets/sync_status.dart';
import 'package:tracker/writes/queued_write_journal.dart';
import 'package:tracker/writes/settle_write.dart';
import 'package:tracker/writes/tracker_writes.dart';

import 'support.dart';

void main() {
  ensureE2EBinding();

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

  testWidgets('an Undo refused before its own timeout, because the entry it '
      'undoes was refused, is not called a failed Undo', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, 'e2e-rejected-undo-early@example.com');
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
      await deleteBypassingRules('vices', coffeeID);
    } finally {
      // Well inside the Undo's own timeout, so its refusal reaches the Undo.
      await FirebaseFirestore.instance.enableNetwork();
    }

    const List<String> forbidden = <String>['Unable to undo', 'Not deleted'];
    await pumpUntilNeverShowing(
      tester,
      inBanner('Not saved: Coffee, 2 drinks, '),
      forbidden,
    );
    // Settles once the server has answered the delete as well; a snackbar
    // would still be showing a second later.
    await FirebaseFirestore.instance.waitForPendingWrites();
    await pumpFor(tester, const Duration(seconds: 1));
    for (final String text in forbidden) {
      expect(find.textContaining(text), findsNothing);
    }
  });

  testWidgets('an entry queued offline that is lost before the next launch '
      'is named on that launch, and one the server holds is not', (
    WidgetTester tester,
  ) async {
    // The journal file outlives the run, so the test sets what it starts
    // from, before the app loads it: an entry another user's launch left,
    // which must stay unchecked.
    const FileJournalStore file = FileJournalStore(emulatorProjectId);
    final QueuedWrite foreign = QueuedWrite(
      uid: 'someone-else',
      what: 'Not saved: Coffee, 1 drink',
      collection: 'activities',
      id: 'foreign',
      op: WriteOp.create,
    );
    await file.write(jsonEncode(<Object>[foreign.toJson()]));
    Future<List<Object?>> journaled({required String by}) async => <Object?>[
      for (final Object? entry
          in jsonDecode(await file.read() ?? '[]') as List<Object?>)
        if (entry case {
          'uid': final String owner,
          'what': final Object what,
        } when owner == by)
          what,
    ];
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, 'e2e-rejected-restart@example.com');
    await addVicesThroughManageData(tester);
    final String coffeeID = await storedViceID('Coffee');
    final String uid = FirebaseAuth.instance.currentUser!.uid;
    final Finder banner = find.byType(RejectedWritesBanner);
    Finder inBanner(String text) =>
        find.descendant(of: banner, matching: find.textContaining(text));
    final Finder rejected = inBanner('Not saved: Coffee, 2 drinks, ');

    await FirebaseFirestore.instance.disableNetwork();
    addTearDown(() => FirebaseFirestore.instance.enableNetwork());
    await pumpUntil(tester, find.text(OfflineBanner.message));
    await recordActivity(tester, 'Coffee', 2);
    await pumpUntil(tester, find.text(queuedMessage));
    expect(
      await journaled(by: uid),
      contains(startsWith('Not saved: Coffee, 2 drinks, ')),
    );

    // The launch ends with the entry still queued. Under the emulators the
    // cache is off, so terminating drops the queue: the next launch's server
    // holds no such entry, as after a refusal. Termination leaves the write's
    // future unresolved, so nothing in this launch removes it from the
    // journal.
    await FirebaseFirestore.instance.terminate();
    // A write whose answer the earlier launch missed, but the server took.
    final QueuedWriteJournal earlier = QueuedWriteJournal(file);
    await earlier.add(
      QueuedWrite(
        uid: uid,
        what: 'Not saved: the habit Coffee',
        collection: 'vices',
        id: coffeeID,
        op: WriteOp.create,
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());

    // The next launch: Auth kept the session; Firestore starts afresh, online.
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await pumpUntil(tester, rejected);
    expect(inBanner('The server refused this change.'), findsOneWidget);
    await screenshot(tester, 'rejected-write-earlier-launch');
    final DateTime deadline = DateTime.now().add(timeout);
    while ((await journaled(by: uid)).isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        fail(
          'The journal still holds the checked writes: ${await file.read()}',
        );
      }
      await pumpFor(tester, const Duration(milliseconds: 100));
    }
    // Both entries are checked by now, so the vice's would be showing.
    expect(inBanner('the habit Coffee'), findsNothing);
    expect(inBanner(foreign.what), findsNothing);
    expect(await journaled(by: foreign.uid), <Object>[foreign.what]);

    await tap(
      tester,
      find.descendant(
        of: banner,
        matching: find.text(RejectedWritesBanner.dismissLabel),
      ),
    );
    await pumpUntil(tester, rejected, present: false);
  });
}
