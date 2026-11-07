import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/main.dart';
import 'package:tracker/manage_data.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/vice_activity_history_page.dart';
import 'package:tracker/vice_activity_editor_page.dart';
import 'package:tracker/widgets/day_dial.dart';
import 'package:tracker/widgets/sync_status.dart';
import 'package:tracker/writes/settle_write.dart';

import 'support.dart';

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('entries logged, edited and deleted offline show as not yet '
      'synced, then sync once, when the network returns', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, 'e2e-offline@example.com');
    await addVicesThroughManageData(tester);
    final Finder banner = find.text(OfflineBanner.message);
    final Finder notSynced = find.text(NotSyncedMarker.defaultLabel);
    expect(banner, findsNothing);

    await FirebaseFirestore.instance.disableNetwork();
    try {
      await pumpUntil(tester, banner);
      await pumpUntil(tester, find.text(SyncPill.offlineLabel));
      // An empty day offline may be one this device never fetched.
      await tap(tester, find.byTooltip('Previous day'));
      await pumpUntil(tester, find.text(ClearDay.offlineHeadline));
      expect(
        find.text(ClearDay.offlineBody, skipOffstage: false),
        findsOneWidget,
      );
      await tap(tester, find.byTooltip('Next day'));

      await recordActivity(tester, 'Coffee', 2);
      await pumpUntil(tester, find.text(queuedMessage));
      expect(find.text('Request timed out'), findsNothing);
      await expectTallies(tester, const <String>{
        'Coffee (2 drinks)',
        'Tea (0 drinks)',
        'Water (0 drinks)',
      });
      await pumpUntil(
        tester,
        find.text(PendingDayNote.text(1), skipOffstage: false),
      );
      await screenshot(tester, 'record-queued-offline');
      await recordActivity(tester, 'Coffee', 5);
      await recordActivity(tester, 'Coffee', 7);
      await pumpUntil(
        tester,
        find.text(PendingDayNote.text(3), skipOffstage: false),
      );

      await openFromMenu(tester, Homepage.habitsItem);
      // count() runs only on the server; offline the row counts what this
      // device holds. Each row resolves on its own.
      await pumpUntil(
        tester,
        habitsCount(
          ManageData.countText((count: 3, source: CountSource.deviceOffline)),
        ),
      );
      final Finder noneOnDevice = habitsCount(
        ManageData.countText((count: 0, source: CountSource.deviceOffline)),
      );
      await pumpUntilTrue(
        tester,
        () => noneOnDevice.evaluate().length == 2,
        () => 'two rows of $noneOnDevice',
      );
      await tap(tester, find.text('Coffee'));
      await pumpUntil(tester, historyTitle('Coffee'));
      await pumpUntil(tester, notSynced);
      expect(notSynced, findsNWidgets(3));
      await pumpUntil(tester, banner);

      await swipeToDelete(tester, historyEntry(5));
      await pumpUntil(tester, historyEntry(5), present: false);
      await pumpUntil(tester, find.text(queuedDeleteMessage));
      expect(deletedBar, findsNothing);

      await tap(tester, historyEntry(2));
      await pumpUntilRouteSettled(tester, find.text('Edit Coffee activity'));
      await enterText(tester, 'Quantity', '3');
      await tap(tester, find.widgetWithText(TextButton, 'Save'));
      await pumpUntil(
        tester,
        find.byType(ViceActivityEditorPage),
        present: false,
      );
      await pumpUntil(tester, find.text(queuedMessage));
      await pumpUntil(tester, historyEntry(3));

      await tap(tester, historyEntry(7));
      await pumpUntilRouteSettled(tester, find.text('Edit Coffee activity'));
      await tap(
        tester,
        find.descendant(
          of: find.byType(ViceActivityEditorPage),
          matching: find.byTooltip('Delete'),
        ),
      );
      // The history page is off stage until the editor has popped.
      await pumpUntil(tester, historyTitle('Coffee').hitTestable());
      await pumpUntil(
        tester,
        find.byType(ViceActivityEditorPage),
        present: false,
      );
      await pumpUntil(tester, find.text(queuedDeleteMessage));
      await pumpUntil(tester, historyEntry(7), present: false);
      expect(historyRows, findsOneWidget);
      expect(notSynced, findsOneWidget);
      await screenshot(tester, 'history-not-yet-synced');
    } finally {
      await FirebaseFirestore.instance.enableNetwork();
    }

    await pumpUntil(tester, notSynced, present: false);
    await pumpUntil(tester, banner, present: false);

    // A get() merges unacknowledged writes even from the server, so wait for
    // the queue to drain before reading what the emulator holds.
    await FirebaseFirestore.instance.waitForPendingWrites().timeout(timeout);
    // Today's pill has seen the same: back from history, then Habits.
    await tap(tester, find.byTooltip('Back'));
    await pumpUntil(
      tester,
      find.byType(ViceActivityHistoryPage),
      present: false,
    );
    await closeMenuPage(tester);
    await pumpUntil(tester, find.text(SyncPill.synced).hitTestable());
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> stored =
        await storedActivities('Coffee');
    expect(stored, hasLength(1));
    expect(stored.single.data()['quantity'], 3);
  });
}
