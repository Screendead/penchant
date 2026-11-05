import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/main.dart';
import 'package:tracker/manage_data.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/vice_activity_editor_page.dart';
import 'package:tracker/widgets/clean_day.dart';
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
      // An empty day offline may be one this device never fetched.
      await tap(tester, find.byTooltip('Previous day'));
      await pumpUntil(tester, find.text(CleanDay.offlineHeadline));
      await tap(tester, find.text('Jump to Today'));

      await recordActivity(tester, 'Coffee', 2);
      await pumpUntil(tester, find.text(queuedMessage));
      expect(find.text('Request timed out'), findsNothing);
      await expectChart(tester, const <String>{
        'Coffee (2 drinks)',
        'Tea (0 drinks)',
        'Water (0 drinks)',
      });
      await pumpUntil(tester, find.text(PendingDayNote.text(1)));
      await screenshot(tester, 'record-queued-offline');
      await recordActivity(tester, 'Coffee', 5);
      await recordActivity(tester, 'Coffee', 7);
      await pumpUntil(tester, find.text(PendingDayNote.text(3)));

      await openFromDrawer(tester, 'Manage Data');
      // count() runs only on the server; offline the row counts what this
      // device holds. Each row resolves on its own.
      await pumpUntil(
        tester,
        find.text(
          ManageData.countText((count: 3, source: CountSource.deviceOffline)),
        ),
      );
      final Finder noneOnDevice = find.text(
        ManageData.countText((count: 0, source: CountSource.deviceOffline)),
      );
      await pumpUntilTrue(
        tester,
        () => noneOnDevice.evaluate().length == 2,
        () => 'two rows of $noneOnDevice',
      );
      await tap(tester, find.text('Coffee'));
      await pumpUntil(tester, find.text('Coffee history'));
      await pumpUntil(tester, notSynced);
      expect(notSynced, findsNWidgets(3));
      await pumpUntil(tester, banner);

      final Finder fiveRow = find.ancestor(
        of: find.text('Quantity: 5'),
        matching: find.byType(Card),
      );
      await tap(
        tester,
        find.descendant(of: fiveRow, matching: find.byTooltip('Delete')),
      );
      await pumpUntil(tester, find.text('Quantity: 5'), present: false);
      await pumpUntil(tester, find.text(queuedDeleteMessage));
      expect(find.text('Activity deleted'), findsNothing);

      await tap(tester, find.text('Quantity: 2'));
      await pumpUntilRouteSettled(tester, find.text('Edit Coffee activity'));
      await enterText(tester, 'Quantity', '3');
      await tap(tester, find.widgetWithText(TextButton, 'Save'));
      await pumpUntil(
        tester,
        find.byType(ViceActivityEditorPage),
        present: false,
      );
      await pumpUntil(tester, find.text(queuedMessage));
      await pumpUntil(tester, find.text('Quantity: 3'));

      await tap(tester, find.text('Quantity: 7'));
      await pumpUntilRouteSettled(tester, find.text('Edit Coffee activity'));
      await tap(
        tester,
        find.descendant(
          of: find.byType(ViceActivityEditorPage),
          matching: find.byTooltip('Delete'),
        ),
      );
      // The history page is off stage until the editor has popped.
      await pumpUntil(tester, find.text('Coffee history').hitTestable());
      await pumpUntil(
        tester,
        find.byType(ViceActivityEditorPage),
        present: false,
      );
      await pumpUntil(tester, find.text(queuedDeleteMessage));
      await pumpUntil(tester, find.text('Quantity: 7'), present: false);
      expect(find.byType(Card), findsOneWidget);
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
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> stored =
        await storedActivities('Coffee');
    expect(stored, hasLength(1));
    expect(stored.single.data()['quantity'], 3);
  });
}
