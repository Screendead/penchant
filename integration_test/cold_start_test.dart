import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/authenticate.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/homepage.dart';

import 'support.dart';

// A new ProviderScope key throws away the old container, so userProvider
// starts from loading again, as on a launch with a persisted session. The old
// tree goes first: on macOS two live menu bars assert.
Future<void> _relaunch(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(e2eApp(key: UniqueKey()));
}

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('a signed-in launch goes straight home, never via sign-in, and '
      'a signed-out one shows sign-in', (WidgetTester tester) async {
    await _relaunch(tester);
    await register(tester, 'e2e-cold-start@example.com');

    await _relaunch(tester);
    expect(find.byType(Authenticate), findsNothing);
    await pumpUntilNeverShowing(tester, find.byType(Homepage), <String>[
      'A private journal of your days.',
    ]);

    await FirebaseAuth.instance.signOut();
    await _relaunch(tester);
    await pumpUntil(tester, find.byType(Authenticate));
  });
}
