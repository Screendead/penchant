import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tracker/authenticate.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/main.dart';

import 'support.dart';

// A new ProviderScope key throws away the old container, so userProvider
// starts from loading again, as on a launch with a persisted session.
Future<void> _relaunch(WidgetTester tester) =>
    tester.pumpWidget(ProviderScope(key: UniqueKey(), child: const MyApp()));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

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
      'Sign In to Your Account',
    ]);

    await FirebaseAuth.instance.signOut();
    await _relaunch(tester);
    await pumpUntil(tester, find.byType(Authenticate));
  });
}
