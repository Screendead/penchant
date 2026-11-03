import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/vice_activity_history_page.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/sync_status.dart';

import 'fakes.dart';

void main() {
  final DateTime now = DateTime.now();
  final ViceActivity synced = fakeActivity('coffee', 1, now);
  final ViceActivity pending = fakeActivity(
    'coffee',
    2,
    now,
  ).copyWith(id: 'pending', pending: true);

  testWidgets('Today counts the day\'s entries the server has not '
      'acknowledged', (WidgetTester tester) async {
    final StreamController<List<ViceActivity>> day =
        StreamController<List<ViceActivity>>();
    // close() completes only once a listener has drained the stream.
    addTearDown(() => unawaited(day.close()));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unarchivedViceListProvider.overrideWith(
            (ref) => AsyncData([fakeVice('coffee')]),
          ),
          userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
          viceActivityDayForUserProvider.overrideWith((ref, key) => day.stream),
        ],
        child: const MaterialApp(home: Scaffold(body: ViceTracker())),
      ),
    );
    // Lets the user resolve, so the day's query is listening.
    await tester.pump();

    day.add([synced, pending]);
    await tester.pump();
    expect(find.text(PendingDayNote.text(1)), findsOneWidget);

    day.add([synced, pending.copyWith(pending: false)]);
    await tester.pump();
    expect(find.textContaining('not yet synced'), findsNothing);
  });

  testWidgets('at text scale 3 on a small phone the pending note wraps '
      'rather than overflowing', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(375 * 2, 667 * 2);
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unarchivedViceListProvider.overrideWith(
            (ref) => AsyncData([fakeVice('coffee')]),
          ),
          viceActivityDayProvider.overrideWith(
            (ref, DateTime selected) => AsyncData([pending]),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: ViceTracker())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(PendingDayNote.text(1)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the history page marks only the entries not yet synced', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
          offlineProvider.overrideWith((ref) => Stream.value(false)),
          viceListProvider.overrideWith(
            (ref) => AsyncData([fakeVice('coffee')]),
          ),
          viceActivityHistoryProvider.overrideWith(
            (ref, ViceActivityHistoryQuery query) =>
                AsyncData([synced, pending]),
          ),
        ],
        child: const MaterialApp(
          home: ViceActivityHistoryPage(viceID: 'coffee'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(NotSyncedMarker.defaultLabel), findsOneWidget);
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Quantity: 2'),
          matching: find.byType(Card),
        ),
        matching: find.text(NotSyncedMarker.defaultLabel),
      ),
      findsOneWidget,
    );
    expect(find.text(OfflineBanner.message), findsNothing);
  });

  testWidgets('the banner follows the offline state', (
    WidgetTester tester,
  ) async {
    final StreamController<bool> offline = StreamController<bool>();
    addTearDown(() => unawaited(offline.close()));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [offlineProvider.overrideWith((ref) => offline.stream)],
        child: const MaterialApp(home: Scaffold(body: OfflineBanner())),
      ),
    );

    expect(find.text(OfflineBanner.message), findsNothing);
    offline.add(true);
    await tester.pump();
    expect(find.text(OfflineBanner.message), findsOneWidget);
    offline.add(false);
    await tester.pump();
    await tester.pump();
    expect(find.text(OfflineBanner.message), findsNothing);
  });

  test('sustainedOffline reports offline only once the cache has answered '
      'for the whole delay, and online at once', () async {
    const Duration delay = Duration(milliseconds: 300);
    Future<void> wait(Duration duration) => Future<void>.delayed(duration);
    final StreamController<bool> fromCache = StreamController<bool>();
    final List<bool> seen = <bool>[];
    final StreamSubscription<bool> subscription = sustainedOffline(
      fromCache.stream,
      delay,
    ).listen(seen.add);

    // A warm-cache launch: the cache answers, then the server.
    fromCache.add(true);
    await wait(delay ~/ 3);
    fromCache.add(false);
    await wait(delay * 2);
    expect(seen, <bool>[false]);

    fromCache.add(true);
    await wait(delay ~/ 3);
    expect(seen, <bool>[false]);
    await wait(delay);
    expect(seen, <bool>[false, true]);

    fromCache.add(false);
    await wait(Duration.zero);
    expect(seen, <bool>[false, true, false]);

    await subscription.cancel();
  });
}
