import 'dart:async';

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

  setUp(() {
    requestedLimits = <int>[];
  });

  Future<void> pumpHistory(
    WidgetTester tester,
    int count, {
    Stream<User?>? users,
    bool alwaysUse24HourFormat = false,
  }) async {
    final List<ViceActivity> all = stored(count);
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
}
