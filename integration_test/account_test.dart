import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tracker/account/account_copy.dart';
import 'package:tracker/account/export.dart';
import 'package:tracker/account_settings.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/main.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/sign_in.dart';

import 'support.dart';

const String _password = 'Passw0rdE2E';

// Captures the files instead of opening the share sheet, which a test cannot
// dismiss.
class _CapturedShare implements ExportShare {
  final List<List<ExportFile>> shared = <List<ExportFile>>[];

  @override
  Future<void> share(List<ExportFile> files, {Rect? origin}) async {
    shared.add(files);
  }
}

Future<String> _get(Uri uri, {bool admin = false}) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.getUrl(uri);
    if (admin) {
      // The emulators treat the "owner" bearer token as an admin that skips
      // Security Rules.
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer owner');
    }
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('GET $uri returned ${response.statusCode}: $body');
    }
    return body;
  } finally {
    client.close();
  }
}

// The Auth emulator's record of the emails it would have sent:
// https://firebase.google.com/docs/reference/rest/auth#section-auth-emulator-oob
Future<List<Map<String, dynamic>>> _oobCodes(
  String email,
  String requestType,
) async {
  final Map<String, dynamic> body =
      jsonDecode(
            await _get(
              Uri.parse(
                'http://$emulatorHost:$authEmulatorPort/emulator/v1/projects/'
                '$emulatorProjectId/oobCodes',
              ),
            ),
          )
          as Map<String, dynamic>;
  return <Map<String, dynamic>>[
    for (final dynamic code
        in body['oobCodes'] as List<dynamic>? ?? <dynamic>[])
      if (code['email'] == email && code['requestType'] == requestType)
        code as Map<String, dynamic>,
  ];
}

// Every stored document's ownerID, read past the rules.
// Waits for the app's writes to reach the emulator first.
Future<List<String>> _ownerIDs(String collection) async {
  await FirebaseFirestore.instance.waitForPendingWrites().timeout(timeout);
  final Map<String, dynamic> body =
      jsonDecode(
            await _get(
              Uri.parse(
                'http://$emulatorHost:$firestoreEmulatorPort/v1/projects/'
                '$emulatorProjectId/databases/(default)/documents/$collection'
                '?pageSize=1000',
              ),
              admin: true,
            ),
          )
          as Map<String, dynamic>;
  return <String>[
    for (final dynamic doc
        in body['documents'] as List<dynamic>? ?? <dynamic>[])
      doc['fields']['ownerID']['stringValue'] as String,
  ];
}

Future<void> _openAccountSettings(WidgetTester tester) async {
  await openFromDrawer(tester, 'Settings');
  await tap(tester, find.text('Account'));
  await pumpUntilRouteSettled(tester, find.text(AccountCopy.dataSection));
}

Future<void> _signOutThroughSettings(WidgetTester tester) async {
  await openFromDrawer(tester, 'Settings');
  await tap(tester, find.text('Sign out'));
  await pumpUntil(tester, find.byType(SignIn));
}

Future<void> _signInThroughForm(
  WidgetTester tester,
  String email,
  String password,
) async {
  await enterText(tester, 'Email', email);
  await enterText(tester, 'Password', password);
  await tap(tester, find.widgetWithText(ElevatedButton, 'Sign In'));
  await pumpUntil(tester, find.byType(Homepage));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('registering sends a verification email; a reset link from '
      'sign-in sets a new password that signs in', (tester) async {
    const String email = 'e2e-reset@example.com';
    const String newPassword = 'N3wPassw0rdE2E';
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, email);
    expect(await _oobCodes(email, 'VERIFY_EMAIL'), isNotEmpty);

    // Sign-out terminates Firestore; signing back in below shows it recovers.
    await _signOutThroughSettings(tester);
    await enterText(tester, 'Email', email);
    await tap(tester, find.text(AccountCopy.forgotPassword));
    final Finder dialog = find.byType(ResetPasswordDialog);
    await pumpUntil(tester, dialog);
    expect(
      tester
          .widget<TextFormField>(
            find.descendant(of: dialog, matching: find.byType(TextFormField)),
          )
          .controller!
          .text,
      email,
    );
    await tap(
      tester,
      find.descendant(of: dialog, matching: find.text(AccountCopy.resetSend)),
    );
    await pumpUntil(tester, find.text(AccountCopy.resetSent(email)));

    final List<Map<String, dynamic>> resets = await _oobCodes(
      email,
      'PASSWORD_RESET',
    );
    expect(resets, isNotEmpty);
    // The listed link leaves out newPassword; the emulator takes it as a
    // query parameter.
    final Uri link = Uri.parse(resets.last['oobLink'] as String);
    await _get(
      link.replace(
        queryParameters: <String, String>{
          ...link.queryParameters,
          'newPassword': newPassword,
        },
      ),
    );

    await _signInThroughForm(tester, email, newPassword);
    await addVicesThroughManageData(tester, const <String>['Coffee']);
    expect(await _ownerIDs('vices'), <String>[
      FirebaseAuth.instance.currentUser!.uid,
    ]);
  });

  testWidgets('Account Settings shows the profile as saved and a verification '
      'made outside the app', (tester) async {
    await clearEmulators();
    const String email = 'e2e-profile@example.com';
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, email);

    await _openAccountSettings(tester);
    expect(find.text(AccountCopy.notVerified), findsOneWidget);
    await enterText(tester, 'Display Name', 'Sam');
    await tap(tester, find.text('Update Profile'));
    await pumpUntil(tester, find.text('Display name saved.'));

    // Following the emailed link is what the user does in their mail app.
    final List<Map<String, dynamic>> links = await _oobCodes(
      email,
      'VERIFY_EMAIL',
    );
    await _get(Uri.parse(links.last['oobLink'] as String));

    await tap(tester, find.byTooltip('Close'));
    await pumpUntil(tester, find.text(AccountCopy.dataSection), present: false);
    await tap(tester, find.text('Account'));
    await pumpUntilRouteSettled(tester, find.text(AccountCopy.dataSection));
    await pumpUntil(tester, find.text(AccountCopy.verified));
    expect(find.text(AccountCopy.resendVerification), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Sam'), findsOneWidget);

    // The first save's snackbar outlives the route it was shown on.
    await pumpUntil(tester, find.text('Display name saved.'), present: false);
    await enterText(tester, 'Display Name', '');
    await tap(tester, find.text('Update Profile'));
    await pumpUntil(tester, find.text('Display name saved.'));
    // iOS clears a name by setting it empty.
    expect(FirebaseAuth.instance.currentUser!.displayName ?? '', isEmpty);
  });

  testWidgets('export shares a CSV row per entry and a JSON of the account, '
      'and offline fails instead of sharing the cache', (tester) async {
    await clearEmulators();
    final _CapturedShare share = _CapturedShare();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [exportShareProvider.overrideWithValue(share)],
        child: const MyApp(),
      ),
    );
    await register(tester, 'e2e-export@example.com');
    await addVicesThroughManageData(tester);
    await recordActivity(tester, 'Coffee', 2);
    await recordActivity(tester, 'Tea', 1);

    await _openAccountSettings(tester);
    await tester.ensureVisible(find.text(AccountCopy.exportTitle));
    await tap(tester, find.text(AccountCopy.exportTitle));
    await pumpUntilTrue(
      tester,
      () => share.shared.isNotEmpty,
      () => 'the export to reach the share sheet',
    );

    final List<ExportFile> files = share.shared.single;
    final List<String> rows = files.first.contents.trim().split('\r\n');
    expect(rows.first, 'time,vice,quantity,unit,vice_id,entry_id');
    expect(rows, hasLength(3));
    expect(
      rows.where((String row) => row.contains(',Coffee,2,drink,')),
      hasLength(1),
    );
    expect(
      rows.where((String row) => row.contains(',Tea,1,drink,')),
      hasLength(1),
    );

    final Map<String, dynamic> json =
        jsonDecode(files.last.contents) as Map<String, dynamic>;
    expect(
      <Object?>{for (final dynamic vice in json['vices']) vice['name']},
      <String>{'Coffee', 'Tea', 'Water'},
    );
    expect(json['activities'], hasLength(2));

    await FirebaseFirestore.instance.disableNetwork();
    addTearDown(FirebaseFirestore.instance.enableNetwork);
    await pumpUntil(tester, find.text(AccountCopy.exportTitle));
    await tester.ensureVisible(find.text(AccountCopy.exportTitle));
    await tap(tester, find.text(AccountCopy.exportTitle));
    await pumpUntil(
      tester,
      find.textContaining(AccountCopy.exportFailed('No connection')),
    );
    expect(share.shared, hasLength(1));
  });

  testWidgets('deleting an account removes its documents and its sign-in and '
      "leaves another account's data alone", (tester) async {
    await clearEmulators();
    const String email = 'e2e-delete@example.com';
    await tester.pumpWidget(const ProviderScope(child: MyApp()));

    await register(tester, 'e2e-bystander@example.com');
    await addVicesThroughManageData(tester, const <String>['Kept']);
    final String bystander = FirebaseAuth.instance.currentUser!.uid;

    await register(tester, email);
    await addVicesThroughManageData(tester);
    await recordActivity(tester, 'Coffee', 2);
    await recordActivity(tester, 'Water', 3);
    final String deleted = FirebaseAuth.instance.currentUser!.uid;
    expect(await _ownerIDs('activities'), <String>[deleted, deleted]);

    await _openAccountSettings(tester);
    await tester.ensureVisible(find.text(AccountCopy.deleteTitle));
    await tap(tester, find.text(AccountCopy.deleteTitle));
    await pumpUntil(tester, find.text(AccountCopy.deleteConfirmBody));
    await tap(tester, find.text(AccountCopy.deleteConfirmContinue));
    await pumpUntil(tester, find.text(AccountCopy.deletePasswordPrompt(email)));
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      _password,
    );
    await tester.pump();
    await tap(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(AccountCopy.deleteConfirmAction),
      ),
    );
    await pumpUntil(tester, find.text(AccountCopy.deleted));
    await pumpUntil(tester, find.byType(SignIn));
    expect(find.byType(AccountSettings), findsNothing);

    expect(await _ownerIDs('vices'), <String>[bystander]);
    expect(await _ownerIDs('activities'), isEmpty);
    await expectLater(
      FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _password,
      ),
      throwsA(isA<FirebaseAuthException>()),
    );

    // Deletion terminated Firestore; a new account must still read and write.
    await register(tester, 'e2e-after-delete@example.com');
    await addVicesThroughManageData(tester, const <String>['Fresh']);
    expect((await _ownerIDs('vices')).toSet(), <String>{
      bystander,
      FirebaseAuth.instance.currentUser!.uid,
    });
  });
}
