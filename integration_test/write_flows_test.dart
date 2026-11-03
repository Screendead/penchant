import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/main.dart';
import 'package:tracker/vice_activity_editor_page.dart';

import 'support.dart';

Future<Map<String, dynamic>> _storedVice(String name) async {
  final QuerySnapshot<Map<String, dynamic>> vices = await FirebaseFirestore
      .instance
      .collection('vices')
      .where('ownerID', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
      .where('name', isEqualTo: name)
      .get();
  expect(vices.docs, hasLength(1), reason: 'vice $name');
  return vices.docs.single.data();
}

Finder _rowButton(String viceName, String tooltip) => find.descendant(
  of: find.ancestor(of: find.text(viceName), matching: find.byType(ListTile)),
  matching: find.byTooltip(tooltip),
);

Future<void> _setArchived(
  WidgetTester tester,
  String viceName, {
  required bool archived,
}) async {
  await openFromDrawer(tester, 'Manage Data');
  await tap(tester, _rowButton(viceName, archived ? 'Archive' : 'Unarchive'));
  await pumpUntil(
    tester,
    _rowButton(viceName, archived ? 'Unarchive' : 'Archive'),
  );
  // The button flips on the local snapshot, before the server has the write.
  final DateTime deadline = DateTime.now().add(timeout);
  while ((await _storedVice(viceName))['archived'] != archived) {
    if (DateTime.now().isAfter(deadline)) {
      fail('$viceName never stored archived: $archived');
    }
    await pumpFor(tester, const Duration(milliseconds: 500));
  }
  await closeDrawerPage(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

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
    await expectRadar(tester, withJuice);

    await _setArchived(tester, 'Juice', archived: true);
    await expectRadar(tester, const <String>{
      'Coffee (2 drinks)',
      'Tea (0 drinks)',
      'Water (0 drinks)',
    });

    await _setArchived(tester, 'Juice', archived: false);
    await expectRadar(tester, withJuice);
  });

  testWidgets('the editor saves a changed quantity', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, 'e2e-edit@example.com');
    await addVicesThroughManageData(tester);
    await recordActivity(tester, 'Coffee', 2);

    await openFromDrawer(tester, 'Manage Data');
    await pumpUntil(tester, find.text('1 activities'));
    await tap(tester, find.text('Coffee'));
    await pumpUntil(tester, find.text('Coffee history'));
    await tap(tester, find.text('Quantity: 2'));
    await pumpUntilRouteSettled(tester, find.text('Edit Coffee activity'));
    await enterText(tester, 'Quantity', '5');
    await tap(tester, find.widgetWithText(TextButton, 'Save'));
    await pumpUntil(
      tester,
      find.byType(ViceActivityEditorPage),
      present: false,
    );
    await pumpUntil(tester, find.text('Quantity: 5'));

    final List<QueryDocumentSnapshot<Map<String, dynamic>>> stored =
        await storedActivities('Coffee');
    expect(stored, hasLength(1));
    expect(stored.single.data()['quantity'], 5);
  });
}
