import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/sync_status_provider.dart';
import 'package:tracker/providers/user_provider.dart';

import 'fakes.dart';

void main() {
  // Each call to the waiter is one waitForPendingWrites; the test completes it.
  late List<Completer<void>> waits;

  ProviderContainer container() {
    waits = <Completer<void>>[];
    final ProviderContainer c = ProviderContainer(
      overrides: [
        userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
        pendingWritesWaiterProvider.overrideWithValue(() {
          final Completer<void> wait = Completer<void>();
          waits.add(wait);
          return wait.future;
        }),
      ],
    );
    c.listen(syncStatusProvider, (_, _) {});
    return c;
  }

  SyncState stateOf(ProviderContainer c) => c.read(syncStatusProvider).state;

  // The user's stream, the provider's rebuild and the wait each take a turn;
  // a bare container rebuilds a provider when it is next read.
  Future<void> settle(WidgetTester tester, ProviderContainer c) async {
    for (int i = 0; i < 3; i++) {
      await tester.pump();
      c.read(syncStatusProvider);
    }
  }

  testWidgets('a first wait that returns at once is synced, with no time', (
    WidgetTester tester,
  ) async {
    final ProviderContainer c = container();
    await settle(tester, c);
    expect(waits, hasLength(1));
    expect(stateOf(c), SyncState.unknown);

    waits.single.complete();
    await tester.pump();
    expect(c.read(syncStatusProvider), const SyncStatus(SyncState.synced));
    c.dispose();
  });

  testWidgets('a slow first wait shows writes from an earlier session as '
      'pending until they are sent', (WidgetTester tester) async {
    final ProviderContainer c = container();
    await settle(tester, c);
    await tester.pump(SyncTracker.slowAfter);
    expect(stateOf(c), SyncState.pending);

    waits.single.complete();
    await tester.pump();
    expect(stateOf(c), SyncState.synced);
    expect(c.read(syncStatusProvider).lastSynced, isNotNull);
    c.dispose();
  });

  testWidgets('a write is pending until a wait issued after it returns', (
    WidgetTester tester,
  ) async {
    final ProviderContainer c = container();
    await settle(tester, c);
    waits.single.complete();
    await tester.pump();

    c.read(syncStatusProvider.notifier).track();
    expect(stateOf(c), SyncState.pending);
    c.read(syncStatusProvider.notifier).track();
    expect(waits, hasLength(3));

    // The first write's wait does not cover the second write.
    waits[1].complete();
    await tester.pump();
    expect(stateOf(c), SyncState.pending);

    waits[2].complete();
    await tester.pump();
    expect(stateOf(c), SyncState.synced);
    expect(c.read(syncStatusProvider).lastSynced, isNotNull);
    c.dispose();
  });

  testWidgets('a wait that fails says nothing it cannot know', (
    WidgetTester tester,
  ) async {
    final ProviderContainer c = container();
    await settle(tester, c);
    c.read(syncStatusProvider.notifier).track();
    waits.last.completeError(StateError('terminated'));
    await tester.pump();
    expect(stateOf(c), SyncState.unknown);
    c.dispose();
  });

  group('the header pill', () {
    Future<void> pump(
      WidgetTester tester, {
      required bool offline,
      required SyncState state,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            offlineProvider.overrideWith((ref) => Stream.value(offline)),
            syncStatusProvider.overrideWith(() => _Fixed(state)),
          ],
          child: const MaterialApp(home: Scaffold(body: SyncPill())),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('says Synced once every write has reached the server', (
      WidgetTester tester,
    ) async {
      await pump(tester, offline: false, state: SyncState.synced);
      expect(find.text(SyncPill.synced), findsOneWidget);
    });

    testWidgets('says Syncing while a write is on its way', (
      WidgetTester tester,
    ) async {
      await pump(tester, offline: false, state: SyncState.pending);
      expect(find.text(SyncPill.syncing), findsOneWidget);
    });

    testWidgets('says Offline offline, whatever is pending', (
      WidgetTester tester,
    ) async {
      await pump(tester, offline: true, state: SyncState.pending);
      expect(find.text(SyncPill.offlineLabel), findsOneWidget);
    });

    testWidgets('says nothing until it knows', (WidgetTester tester) async {
      await pump(tester, offline: false, state: SyncState.unknown);
      expect(find.byType(Text), findsNothing);
    });
  });

  test('the menu footer gives the last sync time only when it knows it', () {
    expect(
      SyncFooter.text(const SyncStatus(SyncState.synced), offline: false),
      'All entries synced',
    );
    expect(
      SyncFooter.text(
        SyncStatus(SyncState.synced, lastSynced: DateTime(2026, 11, 5, 21, 8)),
        offline: false,
      ),
      startsWith('All entries synced · last at '),
    );
    expect(
      SyncFooter.text(const SyncStatus(SyncState.unknown), offline: false),
      isNull,
    );
    expect(
      SyncFooter.text(const SyncStatus(SyncState.synced), offline: true),
      startsWith('Offline'),
    );
  });
}

class _Fixed extends SyncTracker {
  _Fixed(this.fixed);

  final SyncState fixed;

  @override
  SyncStatus build() => SyncStatus(fixed);
}
