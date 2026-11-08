import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/vice_activity_history_page.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/pill_drop.dart';
import 'package:tracker/widgets/sync_status.dart';

import 'fakes.dart';

void main() {
  final DateTime now = DateTime.now();
  final ViceActivity synced = fakeActivity('coffee', 1, now);
  final ViceActivity pending = ViceActivity(
    id: 'pending',
    viceID: 'coffee',
    quantity: 2,
    ownerID: ownerID,
    createdAt: Timestamp.fromDate(now),
    pending: true,
  );
  final ViceActivity acknowledged = ViceActivity(
    id: 'pending',
    viceID: 'coffee',
    quantity: 2,
    ownerID: ownerID,
    createdAt: Timestamp.fromDate(now),
  );

  test('the pending note groups digits and picks the English plural', () {
    expect(PendingDayNote.text(1), '1 entry not yet synced');
    expect(PendingDayNote.text(1500), '1,500 entries not yet synced');
  });

  testWidgets('offline, Today counts the day\'s entries the server has not '
      'acknowledged', (WidgetTester tester) async {
    final StreamController<List<ViceActivity>> day =
        StreamController<List<ViceActivity>>();
    // close() completes only once a listener has drained the stream.
    addTearDown(() => unawaited(day.close()));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...habitOverrides([fakeVice('coffee')]),
          userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
          offlineProvider.overrideWith((ref) => Stream.value(true)),
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

    day.add([synced, acknowledged]);
    await tester.pump();
    expect(find.textContaining('not yet synced'), findsNothing);
  });

  testWidgets('online, a pending entry adds no note that would move the '
      'tallies', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...habitOverrides([fakeVice('coffee')]),
          offlineProvider.overrideWith((ref) => Stream.value(false)),
          viceActivityDayProvider.overrideWith(
            (ref, DateTime selected) => AsyncData([pending]),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: ViceTracker())),
      ),
    );
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
          ...habitOverrides([fakeVice('coffee')]),
          offlineProvider.overrideWith((ref) => Stream.value(true)),
          viceActivityDayProvider.overrideWith(
            (ref, DateTime selected) => AsyncData([pending]),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: ViceTracker())),
      ),
    );
    // A pending bead's rim turns until it syncs, so nothing settles.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // Today scrolls; at this size the note sits below the dial.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pump(const Duration(seconds: 1));

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
          of: find.text(Unit.values.first.label(2)),
          matching: find.byType(Dismissible),
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
    await tester.pumpAndSettle();
    expect(find.text(OfflineBanner.message), findsNothing);
  });

  group('the offline pill', () {
    Future<StreamController<bool>> pump(
      WidgetTester tester, {
      required bool reduced,
    }) async {
      final StreamController<bool> offline = StreamController<bool>();
      addTearDown(() => unawaited(offline.close()));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [offlineProvider.overrideWith((ref) => offline.stream)],
          child: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: const MaterialApp(
              home: Scaffold(
                body: Column(children: [OfflineBanner(), Text('Today')]),
              ),
            ),
          ),
        ),
      );
      offline.add(false);
      await tester.pump();
      await tester.pump();
      return offline;
    }

    double y(WidgetTester tester) => tester
        .widget<Transform>(
          find
              .ancestor(
                of: find.text(OfflineBanner.message),
                matching: find.byType(Transform),
              )
              .first,
        )
        .transform
        .getTranslation()
        .y;

    testWidgets('drops in on a spring that overshoots, and lifts away', (
      WidgetTester tester,
    ) async {
      final StreamController<bool> offline = await pump(tester, reduced: false);
      offline.add(true);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(y(tester), lessThan(-50));
      final List<double> path = <double>[];
      for (int i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        path.add(y(tester));
      }
      // Past its place, then back.
      expect(path.reduce(max), greaterThan(0.5));
      await tester.pumpAndSettle();
      expect(y(tester), moreOrLessEquals(0, epsilon: 0.01));

      offline.add(false);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));
      expect(y(tester), inExclusiveRange(PillDrop.liftTo, 0));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump();
      expect(find.text(OfflineBanner.message), findsNothing);
    });

    testWidgets('only fades under reduce motion', (WidgetTester tester) async {
      final StreamController<bool> offline = await pump(tester, reduced: true);
      offline.add(true);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(y(tester), 0);
      final Opacity fade = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.text(OfflineBanner.message),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(fade.opacity, inExclusiveRange(0.3, 0.7));
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.binding.hasScheduledFrame, isFalse);

      offline.add(false);
      await tester.pump();
      await tester.pump();
      await tester.pump(PillDrop.reducedLift);
      await tester.pump();
      expect(find.text(OfflineBanner.message), findsNothing);
    });
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
