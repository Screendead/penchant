import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/account/account_copy.dart';
import 'package:tracker/account/export.dart';
import 'package:tracker/account_settings.dart';
import 'package:tracker/authenticate.dart';
import 'package:tracker/data/free_text_triggers.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/settings.dart';
import 'package:tracker/sign_in.dart';

import 'fake_account.dart';
import 'fake_writes.dart';
import 'fakes.dart';

const String _email = 'someone@example.com';

Future<void> _pump(
  WidgetTester tester,
  FakeAccount account,
  Widget home, {
  FakeExportShare? share,
  Stream<User?>? users,
  Map<String, WidgetBuilder> routes = const <String, WidgetBuilder>{},
}) async {
  final User user = FakeUser(ownerID, email: _email);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountProvider.overrideWithValue(account),
        exportShareProvider.overrideWithValue(share ?? FakeExportShare()),
        userProvider.overrideWith((ref) => Stream.value(user)),
        userProfileProvider.overrideWith((ref) => users ?? Stream.value(user)),
      ],
      child: MaterialApp(home: home, routes: routes),
    ),
  );
  await tester.pump();
}

// The app's root screens are Scaffolds, which is where a snackbar shown after
// popping back to them appears.
Widget _root(String route) => Scaffold(
  body: Builder(
    builder: (context) => TextButton(
      onPressed: () => Navigator.of(context).pushNamed(route),
      child: const Text('root'),
    ),
  ),
);

Future<void> _enter(WidgetTester tester, String label, String text) async {
  await tester.enterText(find.widgetWithText(TextFormField, label), text);
  await tester.pump();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  // Scrolling ignores taps until it settles, and focusing a field scrolls.
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

FirebaseAuthException _authError(String code) => FirebaseAuthException(
  code: code,
  message: 'There is no user record corresponding to this identifier.',
);

void main() {
  group('sign in', () {
    testWidgets('a wrong password reads the same as an unknown address and '
        "never shows Firebase's message", (tester) async {
      final FakeAccount account = FakeAccount()
        ..respond = (_) async => throw _authError('user-not-found');
      await _pump(tester, account, const Authenticate());
      await _enter(tester, 'Email', _email);
      await _enter(tester, 'Password', 'wrong');
      await _tapText(tester, 'Sign in');

      expect(account.calls.single.fields, <String, Object?>{
        'email': _email,
        'password': 'wrong',
      });
      expect(
        find.text('That email and password do not match an account.'),
        findsOneWidget,
      );
      expect(find.textContaining('no user record'), findsNothing);
    });

    testWidgets('forgot password sends a reset link to the address typed '
        'and says the same whether or not it has an account', (tester) async {
      final FakeAccount account = FakeAccount()
        ..respond = (_) async => throw _authError('user-not-found');
      await _pump(tester, account, const Authenticate());
      await _enter(tester, 'Email', _email);
      await _tapText(tester, AccountCopy.forgotPassword);

      final Finder dialogEmail = find.descendant(
        of: find.byType(ResetPasswordDialog),
        matching: find.byType(TextFormField),
      );
      expect(
        tester.widget<TextFormField>(dialogEmail).controller!.text,
        _email,
      );
      await _tapText(tester, AccountCopy.resetSend);

      expect(
        account.calls.single,
        const Write('sendPasswordResetEmail', '', {'email': _email}),
      );
      expect(find.text(AccountCopy.resetSent(_email)), findsOneWidget);
    });

    testWidgets('a failed reset for another reason says so', (tester) async {
      final FakeAccount account = FakeAccount()
        ..respond = (_) async => throw _authError('network-request-failed');
      await _pump(tester, account, const Authenticate());
      await _tapText(tester, AccountCopy.forgotPassword);
      await tester.enterText(
        find.descendant(
          of: find.byType(ResetPasswordDialog),
          matching: find.byType(TextFormField),
        ),
        _email,
      );
      await _tapText(tester, AccountCopy.resetSend);
      expect(
        find.text('No connection. Check your internet and try again.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('a registration Firebase refuses says why', (tester) async {
    final FakeAccount account = FakeAccount()
      ..respond = (_) async => throw _authError('email-already-in-use');
    await _pump(tester, account, const Authenticate());
    await tester.tap(find.byKey(Authenticate.registerTab));
    await tester.pumpAndSettle();
    await _enter(tester, 'Email', _email);
    await _enter(tester, 'Password', 'Passw0rdTest');
    await _enter(tester, 'Confirm password', 'Passw0rdTest');
    await _tapText(tester, 'Create account');

    expect(account.ops, <String>['register']);
    expect(
      find.text(
        'That email already has an account. Sign in, or reset its password.',
      ),
      findsOneWidget,
    );
  });

  group('sign out', () {
    Future<void> openSettings(WidgetTester tester, FakeAccount account) async {
      await _pump(
        tester,
        account,
        _root('/settings'),
        routes: <String, WidgetBuilder>{'/settings': (_) => const Settings()},
      );
      await _tapText(tester, 'root');
    }

    testWidgets('waits for the sign-out, ignoring a second tap, then returns '
        'to the root', (tester) async {
      final Completer<void> signedOut = Completer<void>();
      final FakeAccount account = FakeAccount()
        ..respond = (_) => signedOut.future;
      await openSettings(tester, account);
      await tester.tap(find.text('Sign out'));
      await tester.pump();
      expect(find.byType(Settings), findsOneWidget);

      await tester.tap(find.text('Sign out'), warnIfMissed: false);
      await tester.pump();
      expect(account.calls, hasLength(1));

      signedOut.complete();
      await tester.pumpAndSettle();
      expect(account.calls.single.fields, <String, Object?>{
        'discardUnsynced': false,
      });
      expect(find.byType(Settings), findsNothing);
      expect(find.text('root'), findsOneWidget);
    });

    testWidgets('leaves alone what opened after MyApp popped Settings', (
      tester,
    ) async {
      final Completer<void> signedOut = Completer<void>();
      final FakeAccount account = FakeAccount()
        ..respond = (_) => signedOut.future;
      await openSettings(tester, account);
      await tester.tap(find.text('Sign out'));
      await tester.pump();

      // As MyApp does once the uid changes, before the cache is cleared.
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .popUntil((Route<dynamic> r) => r.isFirst);
      await tester.pumpAndSettle();
      unawaited(
        showDialog<void>(
          context: tester.element(find.text('root')),
          builder: (_) => const AlertDialog(title: Text('reset')),
        ),
      );
      await tester.pumpAndSettle();

      signedOut.complete();
      await tester.pumpAndSettle();
      expect(find.text('reset'), findsOneWidget);
    });

    testWidgets('asks before discarding entries that have not synced', (
      tester,
    ) async {
      final FakeAccount account = FakeAccount()
        ..respond = (call) async {
          if (call.fields['discardUnsynced'] == false) {
            throw const UnsyncedEntriesException();
          }
        };
      await openSettings(tester, account);
      await _tapText(tester, 'Sign out');
      expect(find.text(AccountCopy.signOutUnsyncedBody), findsOneWidget);

      await _tapText(tester, AccountCopy.signOutAnyway);
      expect(
        <Object?>[
          for (final Write call in account.calls)
            call.fields['discardUnsynced'],
        ],
        <bool>[false, true],
      );
      expect(find.text('root'), findsOneWidget);
    });

    testWidgets('a failed sign-out stays put and says so', (tester) async {
      final FakeAccount account = FakeAccount()
        ..respond = (_) async => throw StateError('platform channel');
      await openSettings(tester, account);
      await _tapText(tester, 'Sign out');
      expect(find.byType(Settings), findsOneWidget);
      expect(
        find.text(
          AccountCopy.signOutFailed('Something went wrong. Try again.'),
        ),
        findsOneWidget,
      );
    });
  });

  group('account settings', () {
    testWidgets('saving only a new display name changes only that and asks '
        'for no password', (tester) async {
      final FakeAccount account = FakeAccount();
      await _pump(tester, account, const AccountSettings());
      await _enter(tester, 'Display Name', 'Sam');
      await _tapText(tester, 'Update Profile');

      expect(account.calls, <Write>[
        const Write('updateDisplayName', '', {'displayName': 'Sam'}),
      ]);
      expect(find.text('Display name saved.'), findsOneWidget);
    });

    testWidgets('compares the form with the latest profile, not the one the '
        'screen opened with', (tester) async {
      final StreamController<User?> users = StreamController<User?>();
      addTearDown(users.close);
      final FakeAccount account = FakeAccount();
      await _pump(
        tester,
        account,
        const AccountSettings(),
        users: users.stream,
      );
      users.add(FakeUser(ownerID, email: _email));
      await tester.pump();
      await _enter(tester, 'Display Name', 'Sam');
      await _tapText(tester, 'Update Profile');
      users.add(FakeUser(ownerID, email: _email, displayName: 'Sam'));
      await tester.pump();

      await _enter(tester, 'Display Name', '');
      await _tapText(tester, 'Update Profile');
      expect(account.calls, <Write>[
        const Write('updateDisplayName', '', {'displayName': 'Sam'}),
        const Write('updateDisplayName', '', {'displayName': null}),
      ]);
      expect(find.text('Display name saved.'), findsOneWidget);
    });

    testWidgets('reloads the user on opening and on returning to the app, and '
        'shows the address as verified once it is', (tester) async {
      final StreamController<User?> users = StreamController<User?>();
      addTearDown(users.close);
      final FakeAccount account = FakeAccount();
      await _pump(
        tester,
        account,
        const AccountSettings(),
        users: users.stream,
      );
      users.add(FakeUser(ownerID, email: _email));
      await tester.pump();
      expect(account.reloads, 1);
      expect(find.text(AccountCopy.notVerified), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(account.reloads, 2);
      users.add(FakeUser(ownerID, email: _email, emailVerified: true));
      await tester.pump();
      expect(find.text(AccountCopy.verified), findsOneWidget);
      expect(find.text(AccountCopy.resendVerification), findsNothing);
    });

    testWidgets('a new email asks for the password first and then sends the '
        'confirmation link', (tester) async {
      final FakeAccount account = FakeAccount();
      await _pump(tester, account, const AccountSettings());
      await _enter(tester, 'Email', 'new@example.com');
      await _tapText(tester, 'Update Profile');
      expect(
        find.text(AccountCopy.emailChangePasswordPrompt(_email)),
        findsOneWidget,
      );
      expect(account.calls, isEmpty);

      await tester.enterText(find.byType(TextField).last, 'Passw0rd');
      await tester.pump();
      await _tapText(tester, 'Change email');
      expect(account.calls, <Write>[
        const Write('changeEmail', '', {
          'email': 'new@example.com',
          'password': 'Passw0rd',
        }),
      ]);
      expect(
        find.text(AccountCopy.emailChangeSent('new@example.com')),
        findsOneWidget,
      );
    });

    testWidgets('an unverified address offers to resend the link', (
      tester,
    ) async {
      final FakeAccount account = FakeAccount();
      await _pump(tester, account, const AccountSettings());
      expect(find.text(AccountCopy.notVerified), findsOneWidget);
      await _tapText(tester, AccountCopy.resendVerification);
      expect(account.ops, <String>['sendEmailVerification']);
      expect(find.text(AccountCopy.verificationSent(_email)), findsOneWidget);
    });

    testWidgets('export shares a CSV and a JSON of the fetched data', (
      tester,
    ) async {
      final FakeExportShare share = FakeExportShare();
      final FakeAccount account = FakeAccount()
        ..data = const AccountData(
          vices: <StoredDocument>[
            (id: 'v1', data: <String, dynamic>{'name': 'Tea', 'unit': 'drink'}),
          ],
          activities: <StoredDocument>[
            (id: 'a1', data: <String, dynamic>{'viceID': 'v1', 'quantity': 2}),
          ],
        );
      await _pump(tester, account, const AccountSettings(), share: share);
      await _tapText(tester, AccountCopy.exportTitle);

      expect(account.ops, <String>['fetchData']);
      final List<ExportFile> files = share.shared.single;
      expect(files.first.contents, contains(',Tea,2,,drink,v1,a1'));
      expect(files.last.contents, contains('"name": "Tea"'));
    });

    group('delete account', () {
      setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

      Future<void> startDeletion(WidgetTester tester, FakeAccount account) {
        return _pump(
          tester,
          account,
          _root('/settings/account'),
          routes: <String, WidgetBuilder>{
            '/settings/account': (_) => const AccountSettings(),
          },
        ).then((_) async {
          await _tapText(tester, 'root');
          await _tapText(tester, AccountCopy.deleteTitle);
        });
      }

      testWidgets('says what goes, asks for the password, deletes, and '
          'returns to the root', (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          FreeTextTriggers.key(ownerID): '{"Pitch review":3}',
          FreeTextTriggers.key('someone-else'): '{"Other":3}',
        });
        final FakeAccount account = FakeAccount();
        await startDeletion(tester, account);
        expect(find.text(AccountCopy.deleteConfirmBody), findsOneWidget);

        await _tapText(tester, AccountCopy.deleteConfirmContinue);
        expect(
          find.text(AccountCopy.deletePasswordPrompt(_email)),
          findsOneWidget,
        );
        await tester.enterText(find.byType(TextField).last, 'Passw0rd');
        await tester.pump();
        await _tapText(tester, AccountCopy.deleteConfirmAction);

        expect(account.calls, <Write>[
          const Write('deleteAccount', '', {'password': 'Passw0rd'}),
        ]);
        expect(find.byType(AccountSettings), findsNothing);
        expect(find.text(AccountCopy.deleted), findsOneWidget);
        // The user's own words don't outlive the account on this device.
        expect(await const FreeTextTriggers().uses(ownerID), isEmpty);
        expect(await const FreeTextTriggers().uses('someone-else'), {
          'Other': 3,
        });
      });

      testWidgets('cancelling at either step deletes nothing', (tester) async {
        final FakeAccount account = FakeAccount();
        await startDeletion(tester, account);
        await _tapText(tester, AccountCopy.cancel);
        await _tapText(tester, AccountCopy.deleteTitle);
        await _tapText(tester, AccountCopy.deleteConfirmContinue);
        await _tapText(tester, AccountCopy.cancel);
        expect(account.calls, isEmpty);
        expect(find.byType(AccountSettings), findsOneWidget);
      });

      testWidgets('"Export first" exports instead of deleting', (tester) async {
        final FakeAccount account = FakeAccount();
        await startDeletion(tester, account);
        await _tapText(tester, AccountCopy.deleteConfirmExportFirst);
        expect(account.ops, <String>['fetchData']);
      });

      testWidgets('a wrong password leaves the account and says nothing was '
          'removed', (tester) async {
        final FakeAccount account = FakeAccount()
          ..respond = (_) async => throw _authError('wrong-password');
        await startDeletion(tester, account);
        await _tapText(tester, AccountCopy.deleteConfirmContinue);
        await tester.enterText(find.byType(TextField).last, 'nope');
        await tester.pump();
        await _tapText(tester, AccountCopy.deleteConfirmAction);

        expect(find.byType(AccountSettings), findsOneWidget);
        expect(
          find.text(
            AccountCopy.deleteFailed(
              'That email and password do not match an account.',
            ),
          ),
          findsOneWidget,
        );
      });

      testWidgets('a failure after removal began says some entries may be '
          'gone', (tester) async {
        final FakeAccount account = FakeAccount()
          ..respond = (_) async => throw DeletionIncompleteException(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
          );
        await startDeletion(tester, account);
        await _tapText(tester, AccountCopy.deleteConfirmContinue);
        await tester.enterText(find.byType(TextField).last, 'Passw0rd');
        await tester.pump();
        await _tapText(tester, AccountCopy.deleteConfirmAction);

        expect(find.byType(AccountSettings), findsOneWidget);
        expect(
          find.text(
            AccountCopy.deleteIncomplete(
              'No connection. Check your internet and try again.',
            ),
          ),
          findsOneWidget,
        );
      });
    });
  });
}
