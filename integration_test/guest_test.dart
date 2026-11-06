import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/account/account_copy.dart';
import 'package:tracker/authenticate.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/main.dart';

import 'support.dart';

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('a guest who adds an email keeps their entries after signing '
      'back in with it', (WidgetTester tester) async {
    const String email = 'e2e-guest@example.com';

    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    // Auth keeps the signed-in user in the iOS keychain across runs.
    await FirebaseAuth.instance.signOut();
    await tap(tester, find.byKey(Authenticate.guestStart));
    await pumpUntil(tester, find.byType(Homepage));
    final String guestUID = FirebaseAuth.instance.currentUser!.uid;
    expect(FirebaseAuth.instance.currentUser!.isAnonymous, isTrue);

    await addVicesThroughManageData(tester, <String>['Coffee']);
    await logOne(tester, 'Coffee');
    await expectTallies(tester, <String>{'Coffee (1 drink)'});

    await openFromMenu(tester, Homepage.settingsItem);
    await pumpFor(tester, const Duration(seconds: 1));
    await tap(tester, find.text('Account'));
    await pumpUntil(tester, find.text(AccountCopy.guestTitle));
    await enterText(tester, 'Email', email);
    await enterText(tester, 'Password', 'Passw0rdE2E');
    await enterText(tester, 'Confirm password', 'Passw0rdE2E');
    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, AccountCopy.linkAction),
    );
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tap(
      tester,
      find.widgetWithText(ElevatedButton, AccountCopy.linkAction),
    );
    await pumpUntil(tester, find.text(AccountCopy.linked(email)));
    expect(FirebaseAuth.instance.currentUser!.uid, guestUID);
    expect(FirebaseAuth.instance.currentUser!.isAnonymous, isFalse);

    await tap(tester, find.byTooltip('Back'));
    await pumpUntil(tester, find.text('Sign out').hitTestable());
    await pumpFor(tester, const Duration(seconds: 1));
    // A linked account signs out like any other, without the guest warning.
    await tap(tester, find.text('Sign out'));
    await pumpUntil(tester, find.byType(Homepage), present: false);
    expect(find.text(AccountCopy.guestSignOutTitle), findsNothing);

    await signIn(tester, email);
    await pumpUntil(tester, find.byType(Homepage));
    expect(FirebaseAuth.instance.currentUser!.uid, guestUID);
    await expectTallies(tester, <String>{'Coffee (1 drink)'});
  });
}
