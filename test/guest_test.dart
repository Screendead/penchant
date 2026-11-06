import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/account/account_copy.dart';
import 'package:tracker/account/auth_errors.dart';
import 'package:tracker/account_settings.dart';
import 'package:tracker/authenticate.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/settings.dart';

import 'fake_account.dart';
import 'fake_writes.dart';
import 'fakes.dart';

final User _guest = FakeUser(ownerID, email: null, isAnonymous: true);

Future<void> _pump(
  WidgetTester tester,
  FakeAccount account,
  Widget home, {
  Map<String, WidgetBuilder> routes = const <String, WidgetBuilder>{},
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountProvider.overrideWithValue(account),
        exportShareProvider.overrideWithValue(FakeExportShare()),
        userProvider.overrideWith((ref) => Stream.value(_guest)),
        userProfileProvider.overrideWith((ref) => Stream.value(_guest)),
      ],
      child: MaterialApp(home: home, routes: routes),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _root(String route) => Scaffold(
  body: Builder(
    builder: (context) => TextButton(
      onPressed: () => Navigator.of(context).pushNamed(route),
      child: const Text('root'),
    ),
  ),
);

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

Future<void> _fillLink(WidgetTester tester, String email) async {
  await tester.enterText(find.widgetWithText(TextField, 'Email'), email);
  await tester.enterText(
    find.widgetWithText(TextField, 'Password'),
    'Morn1ng7',
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'Confirm password'),
    'Morn1ng7',
  );
  await tester.pump();
}

void main() {
  group('the sign-in screen', () {
    testWidgets('starts without an account', (tester) async {
      final FakeAccount account = FakeAccount();
      await _pump(tester, account, const Authenticate());
      await tester.ensureVisible(find.byKey(Authenticate.guestStart));
      await tester.tap(find.byKey(Authenticate.guestStart));
      await tester.pumpAndSettle();
      expect(account.ops, <String>['startAsGuest']);
    });

    testWidgets('says why a guest start failed', (tester) async {
      final FakeAccount account = FakeAccount()
        ..respond = (_) async =>
            throw FirebaseAuthException(code: 'operation-not-allowed');
      await _pump(tester, account, const Authenticate());
      await tester.ensureVisible(find.byKey(Authenticate.guestStart));
      await tester.tap(find.byKey(Authenticate.guestStart));
      await tester.pumpAndSettle();
      expect(
        find.text(
          AccountCopy.startAsGuestFailed(
            authErrorMessage(
              FirebaseAuthException(code: 'operation-not-allowed'),
            ),
          ),
        ),
        findsOneWidget,
      );
    });
  });

  group('account settings for a guest', () {
    testWidgets('offers to save the journal instead of a profile', (
      tester,
    ) async {
      await _pump(tester, FakeAccount(), const AccountSettings());
      expect(find.text(AccountCopy.guestTitle), findsOneWidget);
      expect(find.text('Update Profile'), findsNothing);
      expect(find.text(AccountCopy.notVerified), findsNothing);
    });

    testWidgets('links the email and password once both are valid', (
      tester,
    ) async {
      final FakeAccount account = FakeAccount();
      await _pump(tester, account, const AccountSettings());
      ElevatedButton button() => tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, AccountCopy.linkAction),
      );
      expect(button().onPressed, isNull);

      await _fillLink(tester, 'sam@example.com');
      expect(button().onPressed, isNotNull);
      await _tapText(tester, AccountCopy.linkAction);

      expect(account.calls, <Write>[
        const Write('linkEmail', '', {
          'email': 'sam@example.com',
          'password': 'Morn1ng7',
        }),
      ]);
      expect(find.text(AccountCopy.linked('sam@example.com')), findsOneWidget);
    });

    for (final String code in <String>[
      'email-already-in-use',
      'credential-already-in-use',
    ]) {
      testWidgets('an address with an account already ($code) says the '
          'journal would be left behind', (tester) async {
        final FakeAccount account = FakeAccount()
          ..respond = (_) async => throw FirebaseAuthException(code: code);
        await _pump(tester, account, const AccountSettings());
        await _fillLink(tester, 'sam@example.com');
        await _tapText(tester, AccountCopy.linkAction);
        expect(find.text(AccountCopy.linkEmailTaken), findsOneWidget);
      });
    }

    testWidgets('deletion warns, asks no password, and deletes', (
      tester,
    ) async {
      final FakeAccount account = FakeAccount()..isGuest = true;
      await _pump(
        tester,
        account,
        _root('/account'),
        routes: <String, WidgetBuilder>{
          '/account': (_) => const AccountSettings(),
        },
      );
      await _tapText(tester, 'root');
      await _tapText(tester, AccountCopy.deleteTitle);
      expect(find.text(AccountCopy.guestDeleteConfirmBody), findsOneWidget);
      await _tapText(tester, AccountCopy.deleteConfirmContinue);
      expect(account.calls, <Write>[
        const Write('deleteAccount', '', {'password': null}),
      ]);
      expect(find.text(AccountCopy.deleted), findsOneWidget);
    });
  });

  group('signing a guest out', () {
    Future<FakeAccount> openSettings(WidgetTester tester) async {
      final FakeAccount account = FakeAccount()..isGuest = true;
      await _pump(
        tester,
        account,
        _root('/settings'),
        routes: <String, WidgetBuilder>{'/settings': (_) => const Settings()},
      );
      await _tapText(tester, 'root');
      return account;
    }

    testWidgets('shows Guest for the account', (tester) async {
      await openSettings(tester);
      expect(find.text(AccountCopy.guest), findsOneWidget);
    });

    testWidgets('warns that the journal is lost, and cancelling keeps it', (
      tester,
    ) async {
      final FakeAccount account = await openSettings(tester);
      await _tapText(tester, 'Sign out');
      expect(find.text(AccountCopy.guestSignOutBody), findsOneWidget);
      await _tapText(tester, AccountCopy.cancel);
      expect(account.calls, isEmpty);
      expect(find.byType(Settings), findsOneWidget);
    });

    testWidgets('confirming signs out without waiting for unsynced entries', (
      tester,
    ) async {
      final FakeAccount account = await openSettings(tester);
      await _tapText(tester, 'Sign out');
      await _tapText(tester, AccountCopy.guestSignOutAction);
      expect(account.calls, <Write>[
        const Write('signOut', '', {'discardUnsynced': true}),
      ]);
      expect(find.text('root'), findsOneWidget);
    });
  });
}
