import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/account/account_copy.dart';
import 'package:tracker/authenticate.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/homepage.dart';

import 'support.dart';

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('a guest who signs out erases their journal from the server', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(e2eApp());
    // Auth keeps the signed-in user in the iOS keychain across runs.
    await FirebaseAuth.instance.signOut();
    await tap(tester, find.byKey(Authenticate.guestStart));
    await pumpUntil(tester, find.byType(Homepage));
    // A guest starts with no habits, so on the onboarding.
    await skipTheOnboarding(tester);
    expect(FirebaseAuth.instance.currentUser!.isAnonymous, isTrue);

    await addVicesThroughManageData(tester, <String>['Coffee']);
    await logOne(tester, 'Coffee');
    await expectTallies(tester, <String>{'Coffee (1 drink)'});
    final String viceID = await storedViceID('Coffee');
    final String activityID = (await storedActivities('Coffee')).single.id;

    await openFromMenu(tester, Homepage.settingsItem);
    // Sign out pops Settings; popping while its push is still animating trips
    // a framework Hero assertion.
    await pumpFor(tester, const Duration(seconds: 1));
    await tap(tester, find.text('Sign out'));
    await pumpUntil(tester, find.text(AccountCopy.guestSignOutTitle));
    await tap(tester, find.text(AccountCopy.guestSignOutAction));
    await expectSignInWithNothingAbove(tester);
    expect(FirebaseAuth.instance.currentUser, isNull);
    expect(await existsBypassingRules('vices', viceID), isFalse);
    expect(await existsBypassingRules('activities', activityID), isFalse);
  });

  testWidgets('a guest who adds an email keeps their entries after signing '
      'back in with it', (WidgetTester tester) async {
    const String email = 'e2e-guest@example.com';

    await tester.pumpWidget(e2eApp());
    // Auth keeps the signed-in user in the iOS keychain across runs.
    await FirebaseAuth.instance.signOut();
    await tap(tester, find.byKey(Authenticate.guestStart));
    await pumpUntil(tester, find.byType(Homepage));
    // A guest starts with no habits, so on the onboarding.
    await skipTheOnboarding(tester);
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
    await expectSignInWithNothingAbove(tester);
    expect(find.text(AccountCopy.guestSignOutTitle), findsNothing);

    await signIn(tester, email);
    await pumpUntil(tester, find.byType(Homepage));
    expect(FirebaseAuth.instance.currentUser!.uid, guestUID);
    await expectTallies(tester, <String>{'Coffee (1 drink)'});
  });
}
