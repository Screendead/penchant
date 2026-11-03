import 'package:cloud_firestore/cloud_firestore.dart' hide Settings;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tracker/account_settings.dart';
import 'package:tracker/authenticate.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/errors/not_found.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/main.dart';
import 'package:tracker/manage_data.dart';
import 'package:tracker/settings.dart';
import 'package:tracker/vice_activity_history_page.dart';
import 'package:tracker/vice_form.dart';

import 'support.dart';

Finder _rowButton(String viceName, String tooltip) => find.descendant(
  of: find.ancestor(of: find.text(viceName), matching: find.byType(ListTile)),
  matching: find.byTooltip(tooltip),
);

Future<void> _expectSignedOutWithNothingAbove(WidgetTester tester) async {
  await pumpUntil(tester, find.text('Register').hitTestable());
  expect(find.byType(Authenticate), findsOneWidget);
  expect(find.byType(ManageData, skipOffstage: false), findsNothing);
  expect(find.byType(Settings, skipOffstage: false), findsNothing);
  expect(
    find.byType(ViceActivityHistoryPage, skipOffstage: false),
    findsNothing,
  );
  expect(find.byType(CircularProgressIndicator), findsNothing);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets("Manage Data's Edit renames a vice and changes its unit", (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, 'e2e-edit-vice@example.com');
    await addVicesThroughManageData(tester);
    await recordActivity(tester, 'Coffee', 2);
    await expectRadar(tester, const <String>{
      'Coffee (2 drinks)',
      'Tea (0 drinks)',
      'Water (0 drinks)',
    });
    final String viceID = await storedViceID('Coffee');
    final DocumentReference<Map<String, dynamic>> stored = FirebaseFirestore
        .instance
        .collection('vices')
        .doc(viceID);
    const GetOptions server = GetOptions(source: Source.server);
    await FirebaseFirestore.instance.waitForPendingWrites().timeout(timeout);
    final Map<String, dynamic> before = (await stored.get(server)).data()!;

    await openFromDrawer(tester, 'Manage Data');
    await tap(tester, _rowButton('Coffee', 'Edit'));
    await pumpUntilRouteSettled(tester, find.text('Edit Vice'));
    expect(find.byType(NotFound), findsNothing);
    expect(find.byType(CloseButton), findsOneWidget);
    await screenshot(tester, 'edit-vice');
    await enterText(tester, 'Vice Name', 'Espresso');
    await tap(tester, find.byType(DropdownButtonFormField<Unit>));
    await tap(tester, find.text(Unit.hour.plural).last);
    await tap(tester, find.widgetWithText(TextButton, 'Save'));
    await pumpUntil(tester, find.byType(EditVice), present: false);
    await pumpUntil(tester, find.text('Espresso'));
    expect(find.text('Coffee'), findsNothing);

    await FirebaseFirestore.instance.waitForPendingWrites().timeout(timeout);
    expect((await stored.get(server)).data(), <String, dynamic>{
      ...before,
      'name': 'Espresso',
      'unit': 'hour',
    });

    await closeDrawerPage(tester);
    await expectRadar(tester, const <String>{
      'Espresso (2 hours)',
      'Tea (0 drinks)',
      'Water (0 drinks)',
    });
  });

  testWidgets('Record works from the Graph tab', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, 'e2e-graph-record@example.com');
    await addVicesThroughManageData(tester);

    await tap(tester, find.text('Graph'));
    await pumpUntil(tester, find.text('Usage Graph'));
    await recordActivity(tester, 'Tea', 3);
    await pumpUntil(tester, find.text('Activity recorded'));
    expect(find.text('Usage Graph'), findsOneWidget);
    expect(await storedActivities('Tea'), hasLength(1));

    await tap(tester, find.text('Today'));
    await expectRadar(tester, const <String>{
      'Coffee (0 drinks)',
      'Tea (3 drinks)',
      'Water (0 drinks)',
    });
  });

  testWidgets('Settings opens only real pages, and signing out from it lands '
      'on sign-in', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, 'e2e-settings-nav@example.com');

    await openFromDrawer(tester, 'Settings');
    await pumpUntil(tester, find.text('Account'));
    expect(find.text('Notifications'), findsNothing);
    expect(find.text('Privacy'), findsNothing);

    await tap(tester, find.text('Account'));
    await pumpUntilRouteSettled(tester, find.text('Account Settings'));
    expect(find.byType(AccountSettings), findsOneWidget);
    await tap(tester, find.byType(BackButton));
    await pumpUntil(tester, find.byType(AccountSettings), present: false);

    await tap(tester, find.text('Sign out'));
    await _expectSignedOutWithNothingAbove(tester);
  });

  testWidgets('a session that ends under pushed pages returns to sign-in', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, 'e2e-session-end@example.com');
    await addVicesThroughManageData(tester);

    await openFromDrawer(tester, 'Manage Data');
    await tap(tester, find.text('Coffee'));
    await pumpUntilRouteSettled(tester, find.text('Coffee history'));

    await FirebaseAuth.instance.signOut();
    await _expectSignedOutWithNothingAbove(tester);
  });
}
