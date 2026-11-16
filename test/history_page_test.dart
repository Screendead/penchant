import 'dart:async';

import 'package:clock/clock.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/vice_activity_history_page.dart';

import 'fakes.dart';

void main() {
  const int pageSize = ViceActivityHistoryPage.pageSize;
  final Vice coffee = fakeVice('coffee');
  final DateTime newest = DateTime(2026, 11, 2, 12);

  // Newest first, as the query orders them.
  List<ViceActivity> stored(int count) => [
    for (int i = 0; i < count; i++)
      fakeActivity(coffee.id, i + 1, newest.subtract(Duration(hours: i))),
  ];

  late List<int> requestedLimits;
  late List<ViceActivityGraphQuery> summaryQueries;

  setUp(() {
    requestedLimits = <int>[];
    summaryQueries = <ViceActivityGraphQuery>[];
  });

  Future<void> pumpHistory(
    WidgetTester tester,
    int count, {
    Stream<User?>? users,
    bool alwaysUse24HourFormat = false,
    List<ViceActivity>? entries,
    Object? summaryError,
  }) async {
    final List<ViceActivity> all = entries ?? stored(count);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProvider.overrideWith(
            (ref) => users ?? Stream.value(FakeUser(ownerID)),
          ),
          viceListProvider.overrideWithValue(AsyncData([coffee])),
          viceActivityHistoryProvider.overrideWith((
            ref,
            ViceActivityHistoryQuery query,
          ) {
            requestedLimits.add(query.limit);
            if (ref.watch(userProvider).value == null) {
              return const AsyncLoading();
            }
            return AsyncData(all.take(query.limit).toList());
          }),
          viceActivityGraphProvider.overrideWith((
            ref,
            ViceActivityGraphQuery query,
          ) {
            summaryQueries.add(query);
            if (summaryError != null) {
              return AsyncError(summaryError, StackTrace.empty);
            }
            return AsyncData([
              for (final ViceActivity a in all)
                if (!a.createdAt.toDate().isBefore(query.start) &&
                    a.createdAt.toDate().isBefore(query.end))
                  a,
            ]);
          }),
        ],
        child: MediaQuery(
          data: MediaQueryData.fromView(
            tester.view,
          ).copyWith(alwaysUse24HourFormat: alwaysUse24HourFormat),
          child: MaterialApp(home: ViceActivityHistoryPage(viceID: coffee.id)),
        ),
      ),
    );
    await tester.pump();
  }

  Finder quantity(int value) => find.descendant(
    of: find.byType(Dismissible),
    matching: find.text(coffee.unit.label(value)),
  );

  Future<void> scrollToEnd(WidgetTester tester) async {
    await tester.dragUntilVisible(
      find.text('Show older'),
      find.byType(SingleChildScrollView),
      const Offset(0, -2000),
    );
  }

  testWidgets('shows one page and offers the older entries', (tester) async {
    await pumpHistory(tester, pageSize * 2 + 5);

    expect(requestedLimits.toSet(), {pageSize + 1});
    await scrollToEnd(tester);
    expect(quantity(pageSize), findsOneWidget);
    expect(quantity(pageSize + 1), findsNothing);

    await tester.tap(find.text('Show older'));
    await tester.pump();

    expect(requestedLimits.last, pageSize * 2 + 1);
    await scrollToEnd(tester);
    expect(quantity(pageSize * 2), findsOneWidget);
    expect(quantity(pageSize * 2 + 1), findsNothing);
  });

  testWidgets('offers nothing more once every entry is shown', (tester) async {
    await pumpHistory(tester, pageSize);

    await tester.dragUntilVisible(
      quantity(pageSize),
      find.byType(SingleChildScrollView),
      const Offset(0, -2000),
    );
    expect(find.text('Show older'), findsNothing);
  });

  testWidgets('drops the held list when the user changes', (tester) async {
    final StreamController<User?> users = StreamController<User?>();
    addTearDown(users.close);
    await pumpHistory(tester, 3, users: users.stream);
    users.add(FakeUser(ownerID));
    await tester.pump();
    await tester.pump();
    expect(quantity(1), findsOneWidget);

    users.add(null);
    await tester.pump();
    await tester.pump();

    expect(quantity(1), findsNothing);
  });

  testWidgets('times follow the device 24-hour setting', (tester) async {
    await pumpHistory(tester, 2, alwaysUse24HourFormat: true);
    expect(find.text('11:00'), findsOneWidget);
    expect(find.textContaining('AM'), findsNothing);

    await pumpHistory(tester, 2);
    expect(find.text('11:00\u202fAM'), findsOneWidget);
  });

  testWidgets("a row names its entry's trigger", (tester) async {
    await pumpHistory(
      tester,
      0,
      entries: [
        fakeActivity(
          coffee.id,
          1,
          newest,
          triggers: const <String>['work/meeting'],
        ),
      ],
    );

    expect(
      find.descendant(
        of: find.byType(Dismissible),
        matching: find.text('Meeting'),
      ),
      findsOneWidget,
    );
  });

  group('Last 30 days card', () {
    final DateTime now = DateTime(2026, 11, 2, 13);

    Finder card() => find.ancestor(
      of: find.text(ViceActivityHistoryPage.summaryTitle),
      matching: find.byType(MergeSemantics),
    );

    Finder inCard(String text) =>
        find.descendant(of: card(), matching: find.textContaining(text));

    testWidgets('totals the last 30 days and names the busiest hours', (
      tester,
    ) async {
      await withClock(Clock.fixed(now), () async {
        await pumpHistory(
          tester,
          0,
          alwaysUse24HourFormat: true,
          entries: [
            fakeActivity(coffee.id, 2, DateTime(2026, 11, 2, 9)),
            fakeActivity(coffee.id, 1, DateTime(2026, 10, 20, 10)),
            // The first of the 30 days, and the day before it.
            fakeActivity(coffee.id, 3, DateTime(2026, 10, 4, 8)),
            fakeActivity(coffee.id, 40, DateTime(2026, 10, 3, 22)),
          ],
        );

        expect(summaryQueries.toSet(), {
          (
            viceID: coffee.id,
            start: DateTime(2026, 10, 4),
            end: DateTime(2026, 11, 3),
          ),
        });
        expect(card(), findsOneWidget);
        expect(
          find.descendant(of: card(), matching: find.text('Last 30 days')),
          findsOneWidget,
        );
        expect(inCard('6 ${coffee.unit.plural}'), findsOneWidget);
        expect(inCard('Mostly 08:00–11:00'), findsOneWidget);
      });
    });

    testWidgets('says when nothing was logged in them', (tester) async {
      await withClock(Clock.fixed(now), () async {
        await pumpHistory(
          tester,
          0,
          entries: [fakeActivity(coffee.id, 4, DateTime(2026, 9, 1, 9))],
        );

        expect(inCard('0 ${coffee.unit.plural}'), findsOneWidget);
        expect(inCard(ViceActivityHistoryPage.summaryNothing), findsOneWidget);
        // The older entry still lists below.
        expect(quantity(4), findsOneWidget);
      });
    });

    testWidgets('says when the days could not load', (tester) async {
      await withClock(Clock.fixed(now), () async {
        await pumpHistory(tester, 3, summaryError: StateError('offline'));

        expect(inCard(ViceActivityHistoryPage.summaryFailed), findsOneWidget);
        expect(quantity(1), findsOneWidget);
      });
    });

    testWidgets('reads as one node', (tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await withClock(Clock.fixed(now), () async {
        await pumpHistory(
          tester,
          0,
          alwaysUse24HourFormat: true,
          entries: [fakeActivity(coffee.id, 1, DateTime(2026, 11, 1, 9))],
        );

        // The busiest three hours start at the earliest that holds the most.
        expect(
          tester.getSemantics(card()),
          matchesSemantics(
            label:
                'Last 30 days\n1 ${coffee.unit.singular}\nMostly 07:00–10:00',
          ),
        );
      });
      semantics.dispose();
    });
  });
}
