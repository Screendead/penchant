import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';

const Duration timeout = Duration(seconds: 30);

// Set by tools/e2e-screenshots.sh; each screenshot() call then blocks until the
// host has captured the simulator screen.
const String _screenshotServer = String.fromEnvironment('E2E_SCREENSHOT_URL');

void requireEmulators() {
  if (!useFirebaseEmulators) {
    fail(
      'Run with --dart-define=USE_FIREBASE_EMULATORS=true '
      '(tools/e2e.sh does this); without it the app talks to production.',
    );
  }
}

Future<void> clearEmulators() async {
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

String _textOnScreen() => find
    .byType(Text)
    .evaluate()
    .map((Element e) => (e.widget as Text).data)
    .whereType<String>()
    .join(' | ');

// pumpAndSettle never settles here: spinners animate indefinitely and the
// record dialog rewrites its clock field every second.
Future<void> pumpUntilTrue(
  WidgetTester tester,
  bool Function() condition,
  // Built only on failure: a finder's description reads its cached result,
  // whose elements may have unmounted since.
  String Function() description,
) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure(
        'Timed out waiting for ${description()}. '
        'Text on screen: ${_textOnScreen()}',
      );
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  bool present = true,
}) => pumpUntilTrue(
  tester,
  () => finder.evaluate().isNotEmpty == present,
  () => '$finder to ${present ? 'appear' : 'vanish'}',
);

// Popping a route while its push is still animating diverts any snackbar
// hero mid-flight, which trips a framework assertion in debug builds.
Future<void> pumpUntilRouteSettled(WidgetTester tester, Finder onRoute) async {
  await pumpUntil(tester, onRoute);
  await pumpUntilTrue(
    tester,
    () => ModalRoute.of(tester.element(onRoute))!.animation!.isCompleted,
    () => 'the route holding $onRoute to finish its transition',
  );
}

Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  final DateTime end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

// Waits for the target to be hit-testable as well as present, so taps wait out
// route transitions and overlays animating away.
Future<void> tap(WidgetTester tester, Finder finder) async {
  await pumpUntil(tester, finder.hitTestable());
  await tester.tap(finder);
  await tester.pump();
}

// enterText does not pump, so a button enabled by onChanged would still be
// disabled for the next tap.
Future<void> enterText(WidgetTester tester, String label, String text) async {
  final Finder field = find.widgetWithText(TextFormField, label);
  await pumpUntil(tester, field);
  await tester.enterText(field, text);
  await tester.pump();
}

Future<void> screenshot(WidgetTester tester, String name) async {
  if (_screenshotServer.isEmpty) {
    return;
  }
  // Let charts finish animating; the host captures whatever frame is showing.
  await pumpFor(tester, const Duration(seconds: 2));
  final HttpClient client = HttpClient();
  try {
    final HttpClientResponse response = await (await client.getUrl(
      Uri.parse('$_screenshotServer/$name'),
    )).close();
    await response.drain<void>();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('Screenshot $name returned ${response.statusCode}');
    }
  } finally {
    client.close();
  }
}

Future<void> register(WidgetTester tester, String email) async {
  // Auth keeps the signed-in user in the iOS keychain, which survives both
  // reinstalls and the emulator wipe.
  await FirebaseAuth.instance.signOut();
  await tap(tester, find.text('Register'));
  await enterText(tester, 'Email', email);
  await enterText(tester, 'Password', 'Passw0rdE2E');
  await enterText(tester, 'Confirm Password', 'Passw0rdE2E');
  await tap(tester, find.widgetWithText(ElevatedButton, 'Register'));
  await pumpUntil(tester, find.byType(Homepage));
}

Future<void> openFromDrawer(WidgetTester tester, String title) async {
  await tap(tester, find.byTooltip('Open navigation menu'));
  // Let the drawer finish sliding in; its tiles are off-screen until then.
  await pumpFor(tester, const Duration(seconds: 1));
  await tap(tester, find.text(title));
}

// Three vices by default, the fewest the home chart draws as a radar.
Future<void> addVicesThroughManageData(
  WidgetTester tester, [
  List<String> names = const <String>['Coffee', 'Tea', 'Water'],
]) async {
  await openFromDrawer(tester, 'Manage Data');
  await pumpUntil(tester, find.text('Your Vices'));
  for (final String name in names) {
    await tap(tester, find.byTooltip('Add vice'));
    await pumpUntil(tester, find.text('Add Vice'));
    await enterText(tester, 'Vice Name', name);
    await tap(tester, find.byType(DropdownButtonFormField<Unit>));
    await tap(tester, find.text(Unit.drink.plural).last);
    await tap(tester, find.widgetWithText(TextButton, 'Save'));
    await pumpUntil(tester, find.text('Add Vice'), present: false);
    await pumpUntil(tester, find.text(name));
  }
  await closeDrawerPage(tester);
}

// Closes a page opened from the drawer with its back button. The drawer was
// told to close when the page opened, but its animation is paused while the
// page covers it, so it may still be finishing.
Future<void> closeDrawerPage(WidgetTester tester) async {
  await tap(tester, find.byType(BackButton));
  await pumpUntil(tester, find.byType(BackButton), present: false);
  await pumpUntil(tester, find.byType(Drawer), present: false);
  await pumpUntil(tester, find.byTooltip('Open navigation menu').hitTestable());
}

// Records through the app's dialog. With [at], unlocks the date field and
// types the time, as a user correcting the clock would.
Future<void> recordActivity(
  WidgetTester tester,
  String viceName,
  int quantity, {
  DateTime? at,
}) async {
  await tap(tester, find.widgetWithText(TextButton, 'Record'));
  final Finder dialog = find.byType(AlertDialog);
  await pumpUntil(tester, dialog);
  await tap(tester, find.byType(DropdownButtonFormField<String>));
  await tap(tester, find.text(viceName).last);
  if (at != null) {
    await tap(tester, find.byTooltip('Manually enter date and time'));
    await enterText(
      tester,
      'Date and Time',
      RecordNewActivityDialog.dateFormat.format(at),
    );
  }
  await enterText(tester, 'Quantity', '$quantity');
  await tap(tester, find.descendant(of: dialog, matching: find.text('Record')));
  await pumpUntil(tester, dialog, present: false);
}

Future<String> storedViceID(String viceName) async {
  final QuerySnapshot<Map<String, dynamic>> vices = await FirebaseFirestore
      .instance
      .collection('vices')
      .where('ownerID', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
      .where('name', isEqualTo: viceName)
      .get();
  expect(vices.docs, hasLength(1), reason: 'vice $viceName');
  return vices.docs.single.id;
}

// What the signed-in user's account holds in Firestore for one vice.
Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> storedActivities(
  String viceName,
) async {
  final String viceID = await storedViceID(viceName);
  final QuerySnapshot<Map<String, dynamic>> activities = await FirebaseFirestore
      .instance
      .collection('activities')
      .where('ownerID', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
      .where('viceID', isEqualTo: viceID)
      .get();
  return activities.docs;
}

// Writes a document the rules would refuse, as a legacy client could have
// before they existed. The emulators treat the "owner" bearer token as an
// admin that skips Security Rules; [fields] are Firestore REST Values.
Future<void> createBypassingRules(
  String collection,
  String documentID,
  Map<String, Object> fields,
) async {
  final HttpClient client = HttpClient();
  try {
    final Uri uri = Uri.parse(
      'http://$emulatorHost:$firestoreEmulatorPort/v1/projects/'
      '$emulatorProjectId/databases/(default)/documents/$collection'
      '?documentId=$documentID',
    );
    final HttpClientRequest request = await client.postUrl(uri);
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer owner')
      ..contentType = ContentType.json;
    request.write(jsonEncode(<String, Object>{'fields': fields}));
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('POST $uri returned ${response.statusCode}: $body');
    }
  } finally {
    client.close();
  }
}

// The radar chart paints its labels, so they are not Text widgets; read them
// from the chart's data instead. The bar chart's labels are Text widgets.
Set<String>? chartTitles(WidgetTester tester) {
  final Finder bars = find.byType(BarChart);
  if (bars.evaluate().isNotEmpty) {
    return <String>{
      for (final Element e
          in find.descendant(of: bars, matching: find.byType(Text)).evaluate())
        (e.widget as Text).data!,
    };
  }
  final Finder chart = find.byType(RadarChart);
  if (chart.evaluate().isEmpty) {
    return null;
  }
  final RadarChartData data = tester.widget<RadarChart>(chart).data;
  return <String>{
    for (int i = 0; i < data.dataSets.first.dataEntries.length; i++)
      data.getTitle!(i, 0).text,
  };
}

Future<void> expectChart(WidgetTester tester, Set<String> titles) =>
    pumpUntilTrue(
      tester,
      () => setEquals(chartTitles(tester), titles),
      () => 'the chart to show $titles (showing ${chartTitles(tester)})',
    );

Future<void> expectBars(WidgetTester tester, Set<String> titles) async {
  await expectChart(tester, titles);
  expect(find.byType(RadarChart), findsNothing);
}

Future<void> expectRadar(WidgetTester tester, Set<String> titles) async {
  await expectChart(tester, titles);
  expect(find.byType(BarChart), findsNothing);
}

final DateFormat dayMenuFormat = DateFormat('EEEE, MMMM d, yyyy');

Future<void> signOutThroughSettings(WidgetTester tester) async {
  await openFromDrawer(tester, 'Settings');
  // Sign out pops Settings; popping while its push is still animating trips
  // a framework Hero assertion (heroes.dart, manifest.fromHero == toHero).
  await pumpFor(tester, const Duration(seconds: 1));
  await tap(tester, find.text('Sign out'));
  await pumpUntil(tester, find.byType(Homepage), present: false);
}

Future<void> signIn(WidgetTester tester, String email) async {
  await pumpUntil(tester, find.text('Sign In to Your Account'));
  await enterText(tester, 'Email', email);
  await enterText(tester, 'Password', 'Passw0rdE2E');
  await tap(tester, find.widgetWithText(ElevatedButton, 'Sign In'));
}

// Every string the app shows, offstage tabs and painted chart labels included.
Set<String> shownStrings(WidgetTester tester) => <String>{
  for (final Element e in find.byType(Text, skipOffstage: false).evaluate())
    ?((e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText()),
  ...?chartTitles(tester),
};

// Pumps frame by frame until [until] appears, failing on the first frame that
// shows any of [forbidden]: one look after the screen settles would miss a
// flash of stale data.
Future<void> pumpUntilNeverShowing(
  WidgetTester tester,
  Finder until,
  Iterable<String> forbidden,
) async {
  void check() {
    final Set<String> shown = shownStrings(tester);
    for (final String text in forbidden) {
      final Iterable<String> hits = shown.where((s) => s.contains(text));
      if (hits.isNotEmpty) {
        throw TestFailure('"$text" was on screen: $hits');
      }
    }
  }

  check();
  await pumpUntilTrue(tester, () {
    check();
    return until.evaluate().isNotEmpty;
  }, () => '$until to appear');
}
