import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/manage_data.dart';
import 'package:tracker/main.dart';
import 'package:tracker/vice_activity_editor_page.dart';

import 'support.dart';

// A get() merges writes the server has not acknowledged, even with
// Source.server. Waiting first makes the read the emulator's, and a write the
// rules reject has been rolled back by then.
Future<void> _waitForEmulator() =>
    FirebaseFirestore.instance.waitForPendingWrites().timeout(timeout);

Future<Map<String, dynamic>> _storedVice(String name) async {
  await _waitForEmulator();
  final QuerySnapshot<Map<String, dynamic>> vices = await FirebaseFirestore
      .instance
      .collection('vices')
      .where('ownerID', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
      .where('name', isEqualTo: name)
      .get();
  expect(vices.docs, hasLength(1), reason: 'vice $name');
  return vices.docs.single.data();
}

Future<void> _setArchived(
  WidgetTester tester,
  String viceName, {
  required bool archived,
}) async {
  await openFromMenu(tester, Homepage.habitsItem);
  await tap(tester, find.text(viceName));
  await pumpUntilRouteSettled(tester, historyTitle(viceName));
  await tap(tester, find.byTooltip(archived ? 'Archive' : 'Unarchive'));
  await pumpUntil(tester, find.byTooltip(archived ? 'Unarchive' : 'Archive'));
  expect((await _storedVice(viceName))['archived'], archived);
  await tap(tester, find.byTooltip('Back'));
  await pumpUntilRouteSettled(tester, find.byType(ManageData));
  await closeMenuPage(tester);
}

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('archiving a vice takes it off Today and unarchiving brings it '
      'back', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, 'e2e-archive@example.com');
    await addVicesThroughManageData(tester, const <String>[
      'Coffee',
      'Tea',
      'Water',
      'Juice',
    ]);
    expect((await _storedVice('Juice'))['archived'], isFalse);

    const Set<String> withJuice = <String>{
      'Coffee (2 drinks)',
      'Tea (0 drinks)',
      'Water (0 drinks)',
      'Juice (0 drinks)',
    };
    await recordActivity(tester, 'Coffee', 2);
    await expectTallies(tester, withJuice);

    await _setArchived(tester, 'Juice', archived: true);
    await expectTallies(tester, const <String>{
      'Coffee (2 drinks)',
      'Tea (0 drinks)',
      'Water (0 drinks)',
    });

    await _setArchived(tester, 'Juice', archived: false);
    await expectTallies(tester, withJuice);
  });

  testWidgets('a vice stored without the archived field shows on Today, '
      'takes a recording, and can be archived', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, 'e2e-legacy-vice@example.com');
    await addVicesThroughManageData(tester, const <String>['Coffee', 'Tea']);
    await recordActivity(tester, 'Coffee', 2);
    await expectTallies(tester, const <String>{
      'Coffee (2 drinks)',
      'Tea (0 drinks)',
    });

    await createBypassingRules('vices', 'legacy-vice', <String, Object>{
      'name': <String, Object>{'stringValue': 'Kombucha'},
      'unit': <String, Object>{'stringValue': 'drink'},
      'ownerID': <String, Object>{
        'stringValue': FirebaseAuth.instance.currentUser!.uid,
      },
      'createdAt': <String, Object>{
        'timestampValue': DateTime.now().toUtc().toIso8601String(),
      },
    });
    expect((await _storedVice('Kombucha')).containsKey('archived'), isFalse);
    await expectTallies(tester, const <String>{
      'Coffee (2 drinks)',
      'Tea (0 drinks)',
      'Kombucha (0 drinks)',
    });

    await recordActivity(tester, 'Kombucha', 3);
    await expectTallies(tester, const <String>{
      'Coffee (2 drinks)',
      'Tea (0 drinks)',
      'Kombucha (3 drinks)',
    });
    await _waitForEmulator();
    expect((await storedActivities('Kombucha')).single.data()['quantity'], 3);

    await _setArchived(tester, 'Kombucha', archived: true);
    await expectTallies(tester, const <String>{
      'Coffee (2 drinks)',
      'Tea (0 drinks)',
    });
  });

  testWidgets('the editor saves a changed quantity', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, 'e2e-edit@example.com');
    await addVicesThroughManageData(tester);
    await recordActivity(tester, 'Coffee', 2);

    await openFromMenu(tester, Homepage.habitsItem);
    await pumpUntil(tester, habitsCount('1 entry'));
    await tap(tester, find.text('Coffee'));
    await pumpUntil(tester, historyTitle('Coffee'));
    await tap(tester, historyEntry(2));
    await pumpUntilRouteSettled(tester, find.text('Edit Coffee activity'));
    await enterText(tester, 'Quantity', '5');
    await tap(tester, find.widgetWithText(TextButton, 'Save'));
    await pumpUntil(
      tester,
      find.byType(ViceActivityEditorPage),
      present: false,
    );
    await pumpUntil(tester, historyEntry(5));

    await _waitForEmulator();
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> stored =
        await storedActivities('Coffee');
    expect(stored, hasLength(1));
    expect(stored.single.data()['quantity'], 5);
  });

  testWidgets('a decimal quantity is stored as its amount, totals count it '
      'exactly, and the editor changes it', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, 'e2e-amount@example.com');
    await addVicesThroughManageData(tester, const <String>['Coffee', 'Tea']);

    await recordActivity(tester, 'Coffee', 1.5);
    await recordActivity(tester, 'Coffee', 2);
    await expectTallies(tester, <String>{
      'Coffee (${Unit.drink.label(3.5)})',
      'Tea (${Unit.drink.label(0)})',
    });
    await _waitForEmulator();
    final List<Map<String, dynamic>> recorded = <Map<String, dynamic>>[
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in await storedActivities('Coffee'))
        doc.data(),
    ];
    expect(recorded, hasLength(2));
    final Map<String, dynamic> decimal = recorded.singleWhere(
      (Map<String, dynamic> a) => a.containsKey('amount'),
    );
    expect(decimal['amount'], 1.5);
    expect(decimal['quantity'], 2);
    expect(
      recorded.singleWhere(
        (Map<String, dynamic> a) => a != decimal,
      )['quantity'],
      2,
    );

    await openFromMenu(tester, Homepage.habitsItem);
    await tap(tester, find.text('Coffee'));
    await pumpUntil(tester, historyTitle('Coffee'));
    await tap(tester, historyEntry(1.5));
    await pumpUntilRouteSettled(tester, find.text('Edit Coffee activity'));
    expect(
      tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, 'Quantity'))
          .controller!
          .text,
      formatAmount(1.5),
    );
    await enterText(tester, 'Quantity', formatAmount(2.25));
    await tap(tester, find.widgetWithText(TextButton, 'Save'));
    await pumpUntil(
      tester,
      find.byType(ViceActivityEditorPage),
      present: false,
    );
    await pumpUntil(tester, historyEntry(2.25));

    await _waitForEmulator();
    final Map<String, dynamic> edited = (await storedActivities('Coffee'))
        .map((QueryDocumentSnapshot<Map<String, dynamic>> d) => d.data())
        .singleWhere((Map<String, dynamic> a) => a.containsKey('amount'));
    expect(edited['amount'], 2.25);
    expect(edited['quantity'], 3);
  });
}
