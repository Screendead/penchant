import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/main.dart';
import 'package:tracker/vice_activity_history_page.dart';
import 'package:tracker/writes/tracker_writes.dart';

import 'support.dart';

final TrackerWrites _writes = TrackerWrites(FirebaseFirestore.instance);

String get _uid => FirebaseAuth.instance.currentUser!.uid;

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('Today charts an account with more vices than an `in` filter '
      'takes', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, 'e2e-many-vices@example.com');

    final List<String> names = <String>[
      for (int i = 1; i <= 31; i++) 'Vice ${i.toString().padLeft(2, '0')}',
    ];
    for (final String name in names) {
      await _writes.addVice(ownerID: _uid, name: name, unit: Unit.drink);
    }

    await recordActivity(tester, names.last, 2);
    await expectRadar(tester, <String>{
      for (final String name in names)
        '$name (${name == names.last ? '2 drinks' : '0 drinks'})',
    });
  });

  testWidgets('the history page shows 50 entries at a time and the next 50 on '
      'request', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, 'e2e-history-pages@example.com');

    const int pageSize = ViceActivityHistoryPage.pageSize;
    // Two pages and two more, so the second page is full and still has older
    // entries.
    const int stored = 2 * pageSize + 2;
    await _writes.addVice(ownerID: _uid, name: 'Coffee', unit: Unit.drink);
    final String viceID = await storedViceID('Coffee');
    final DateTime newest = DateTime(2026, 1, 31, 12);
    // Quantity n is the n-th newest, so the oldest is the last page's only row.
    for (int n = 1; n <= stored; n++) {
      await _writes.recordActivity(
        _writes.newActivityID(),
        ownerID: _uid,
        viceID: viceID,
        quantity: n,
        createdAt: newest.subtract(Duration(hours: n)),
      );
    }

    await openFromDrawer(tester, 'Manage Data');
    await pumpUntil(tester, find.text('$stored activities'));
    await tap(tester, find.text('Coffee'));
    await pumpUntilRouteSettled(tester, find.text('Coffee history'));

    final Finder list = find.byType(Scrollable).last;
    final Finder showOlder = find.text('Show older');
    await tester.scrollUntilVisible(showOlder, 400, scrollable: list);
    expect(find.text('Quantity: $pageSize'), findsOneWidget);
    expect(find.text('Quantity: ${pageSize + 1}'), findsNothing);

    await tap(tester, showOlder);
    // Until the larger query delivers, the page shows the first query's
    // look-ahead list, which has pageSize + 1 rows and no button. Only the
    // second query yields 2 * pageSize rows plus the button.
    await pumpUntilTrue(
      tester,
      () =>
          tester
              .widget<ListView>(find.byType(ListView).last)
              .semanticChildCount ==
          2 * pageSize + 1,
      () => 'the history list to hold ${2 * pageSize} rows and "Show older"',
    );
    await tester.scrollUntilVisible(showOlder, 400, scrollable: list);
    expect(find.text('Quantity: ${2 * pageSize}'), findsOneWidget);
    expect(find.text('Quantity: ${2 * pageSize + 1}'), findsNothing);
  });
}
