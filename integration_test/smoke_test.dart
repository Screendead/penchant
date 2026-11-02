import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/main.dart' as app;

const Duration _timeout = Duration(seconds: 30);

Future<void> _clearEmulators() async {
  final HttpClient client = HttpClient();
  try {
    for (final Uri uri in <Uri>[
      Uri.parse(
        'http://$emulatorHost:$firestoreEmulatorPort/emulator/v1/projects/'
        '$emulatorProjectId/databases/(default)/documents',
      ),
      Uri.parse(
        'http://$emulatorHost:$authEmulatorPort/emulator/v1/projects/'
        '$emulatorProjectId/accounts',
      ),
    ]) {
      final HttpClientResponse response = await (await client.deleteUrl(
        uri,
      )).close();
      await response.drain<void>();
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('DELETE $uri returned ${response.statusCode}');
      }
    }
  } finally {
    client.close();
  }
}

// pumpAndSettle never settles here: spinners animate indefinitely and the
// record dialog rewrites its clock field every second.
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  bool present = true,
}) async {
  final DateTime deadline = DateTime.now().add(_timeout);
  while (finder.evaluate().isEmpty == present) {
    if (DateTime.now().isAfter(deadline)) {
      final Iterable<String> onScreen = find
          .byType(Text)
          .evaluate()
          .map((Element e) => (e.widget as Text).data)
          .whereType<String>();
      throw TestFailure(
        'Timed out waiting for $finder to ${present ? 'appear' : 'vanish'}. '
        'Text on screen: ${onScreen.join(' | ')}',
      );
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _pumpUntil(tester, finder);
  await tester.tap(finder);
  await tester.pump();
}

// enterText does not pump, so a button enabled by onChanged would still be
// disabled for the next tap.
Future<void> _enterText(WidgetTester tester, String label, String text) async {
  final Finder field = find.widgetWithText(TextFormField, label);
  await _pumpUntil(tester, field);
  await tester.enterText(field, text);
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  setUpAll(() async {
    if (!useFirebaseEmulators) {
      fail(
        'Run with --dart-define=USE_FIREBASE_EMULATORS=true '
        '(tools/e2e.sh does this); without it the app talks to production.',
      );
    }
    await _clearEmulators();
  });

  testWidgets('register, add a vice, record an activity, see it listed', (
    WidgetTester tester,
  ) async {
    await app.main();
    // Auth keeps the signed-in user in the iOS keychain, which survives both
    // reinstalls and the emulator wipe in setUpAll.
    await FirebaseAuth.instance.signOut();

    await _tap(tester, find.text('Register'));
    await _enterText(tester, 'Email', 'e2e@example.com');
    await _enterText(tester, 'Password', 'Passw0rdE2E');
    await _enterText(tester, 'Confirm Password', 'Passw0rdE2E');
    await _tap(tester, find.widgetWithText(ElevatedButton, 'Register'));
    await _pumpUntil(tester, find.byType(Homepage));

    // A new account has no UI path to the add-vice screen: Manage Data hides
    // its add button until an activity exists. Three vices, because the home
    // radar chart asserts at least three axes.
    for (final String name in <String>['Coffee', 'Tea', 'Water']) {
      unawaited(
        Navigator.of(
          tester.element(find.byType(Homepage)),
        ).pushNamed('/vices/add'),
      );
      await _pumpUntil(tester, find.text('Add Vice'));
      await _enterText(tester, 'Vice Name', name);
      await _tap(tester, find.byType(DropdownButtonFormField<Unit>));
      await _tap(tester, find.text(Unit.drink.plural).last);
      await _tap(tester, find.widgetWithText(TextButton, 'Save'));
      await _pumpUntil(tester, find.text('Add Vice'), present: false);
    }

    await _tap(tester, find.widgetWithText(TextButton, 'Record'));
    final Finder dialog = find.byType(AlertDialog);
    await _pumpUntil(tester, dialog);
    await _tap(tester, find.byType(DropdownButtonFormField<Vice>));
    await _tap(tester, find.text('Coffee').last);
    await _enterText(tester, 'Quantity', '2');
    await _tap(
      tester,
      find.descendant(of: dialog, matching: find.text('Record')),
    );
    await _pumpUntil(tester, dialog, present: false);

    await _pumpUntil(tester, find.byType(RadarChart));

    await _tap(tester, find.byTooltip('Open navigation menu'));
    // Let the drawer finish sliding in; its tiles are off-screen until then.
    await tester.pump(const Duration(seconds: 1));
    await _tap(tester, find.text('Manage Data'));
    await _pumpUntil(tester, find.text('Your Vices'));
    expect(find.text('Coffee'), findsOneWidget);
    expect(find.text('Tea'), findsOneWidget);
    expect(find.text('Water'), findsOneWidget);
    expect(find.text('1 activities'), findsOneWidget);
    expect(find.text('0 activities'), findsNWidgets(2));
  });
}
