import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tracker/authenticate.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/manage_data.dart';
import 'package:tracker/trends/trends_sheet.dart';
import 'package:tracker/vice_activity_history_page.dart';
import 'package:tracker/widgets/activity_date_field.dart';
import 'package:tracker/widgets/day_dial.dart';
import 'package:tracker/widgets/log_fan.dart';
import 'package:tracker/widgets/tally_row.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';

const Duration timeout = Duration(seconds: 30);

// Set by tools/e2e-screenshots.sh; each screenshot() call then blocks until the
// host has captured the simulator screen.
const String _screenshotServer = String.fromEnvironment('E2E_SCREENSHOT_URL');

// macOS reports the app hidden whenever none of its window is on screen
// (covered by another window, on another Space, the app hidden), and a hidden
// app schedules no frames. Every pump of a live test waits for a frame, so a
// run would stall, with no timeout, until the window came back. Forcing frames
// leaves the lifecycle the app hears untouched. flutter test creates the
// binding before main runs, so it cannot be a subclass.
class _FramesWhileHidden with WidgetsBindingObserver {
  Timer? _forcing;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _forcing?.cancel();
    _forcing = null;
    if (!SchedulerBinding.instance.framesEnabled) {
      _forcing = Timer.periodic(
        const Duration(milliseconds: 16),
        (_) => SchedulerBinding.instance.scheduleForcedFrame(),
      );
    }
  }
}

bool _bindingReady = false;

// all_test.dart calls every file's main() in one process.
void ensureE2EBinding() {
  if (_bindingReady) {
    return;
  }
  _bindingReady = true;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().addObserver(
    _FramesWhileHidden(),
  );
  WidgetController.hitTestWarningShouldBeFatal = true;
}

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
// route transitions and overlays animating away. Only the hit-testable match is
// tapped: a page pushed over Today leaves Today's tally names in the tree. A
// target in a Scrollable is scrolled into view first: the keyboard can push a
// form's button below the fold, where it is on screen but not hit-testable,
// and may still be rising when the wait starts, so the scroll is retried.
Future<void> tap(WidgetTester tester, Finder finder) async {
  await pumpUntilTrue(tester, () {
    if (finder.hitTestable().evaluate().isNotEmpty) {
      return true;
    }
    for (final Element e in finder.evaluate()) {
      if (Scrollable.maybeOf(e) != null) {
        // With no duration the scroll jumps; the next pump lays it out.
        unawaited(Scrollable.ensureVisible(e));
        break;
      }
    }
    return false;
  }, () => '${finder.hitTestable()} to appear');
  await tester.tap(finder.hitTestable());
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
  await tap(tester, find.byKey(Authenticate.registerTab));
  // The tabs cross-fade, so both forms' Email fields are in the tree until
  // sign-in's has gone.
  final Finder emailField = find.widgetWithText(TextFormField, 'Email');
  await pumpUntilTrue(
    tester,
    () =>
        emailField.evaluate().length == 1 &&
        find
            .widgetWithText(TextFormField, 'Confirm password')
            .evaluate()
            .isNotEmpty,
    () => 'the register form alone',
  );
  await enterText(tester, 'Email', email);
  await enterText(tester, 'Password', 'Passw0rdE2E');
  await enterText(tester, 'Confirm password', 'Passw0rdE2E');
  // The keyboard and the password checklist can push the button below the
  // fold; tap scrolls it back.
  final Finder createAccount = find.widgetWithText(
    ElevatedButton,
    'Create account',
  );
  await tap(tester, createAccount);
  await pumpUntil(tester, find.byType(Homepage));
}

// Opens a page from the Penchant menu: Homepage.habitsItem or settingsItem.
// Waits out the push: until it ends, Today's habit names under the sliding
// page are hit-testable, so a tap on a name lands on Today instead.
Future<void> openFromMenu(WidgetTester tester, String item) async {
  await tap(tester, find.byKey(Homepage.menuKey));
  await pumpUntil(tester, find.text(item).hitTestable());
  await tap(tester, find.text(item));
  await pumpUntilRouteSettled(tester, find.byTooltip('Back'));
}

// Three vices by default.
Future<void> addVicesThroughManageData(
  WidgetTester tester, [
  List<String> names = const <String>['Coffee', 'Tea', 'Water'],
]) async {
  await openFromMenu(tester, Homepage.habitsItem);
  await pumpUntil(tester, find.byType(ManageData));
  for (final String name in names) {
    await tap(tester, find.byTooltip('Add habit'));
    await pumpUntil(tester, find.text('Add Habit'));
    await enterText(tester, 'Habit Name', name);
    await tap(tester, find.byType(DropdownButtonFormField<Unit>));
    await tap(tester, find.text(Unit.drink.plural).last);
    await tap(tester, find.widgetWithText(TextButton, 'Save'));
    await pumpUntil(tester, find.text('Add Habit'), present: false);
    await pumpUntil(tester, find.text(name));
  }
  await closeMenuPage(tester);
}

// The rows of the history page on top. A SnackBar is a Dismissible too, so
// rows are looked for inside the page's scroll view.
final Finder historyRows = find.descendant(
  of: find.byType(SingleChildScrollView),
  matching: find.byType(Dismissible),
);

// The history page's title, which is the habit's name.
Finder historyTitle(String viceName) => find.descendant(
  of: find.byType(ViceActivityHistoryPage),
  matching: find.text(viceName),
);

// The history row whose quantity is [quantity], as "3 drinks".
Finder historyEntry(int quantity) => find.descendant(
  of: historyRows,
  matching: find.byWidgetPredicate(
    (Widget w) => w is Text && (w.data?.startsWith('$quantity ') ?? false),
  ),
);

// The bar after a delete the server took; the queued one says "on this
// device" instead.
final Finder deletedBar = find.textContaining(RegExp(r'^Deleted \d'));

// A Habits row's count, such as "1 entry".
Finder habitsCount(String count) => find.textContaining(' · $count');

Future<void> swipeToDelete(WidgetTester tester, Finder entry) async {
  await tester.drag(
    find.ancestor(of: entry, matching: find.byType(Dismissible)).first,
    const Offset(-600, 0),
  );
  await tester.pump();
}

// Closes a page opened from the menu with its back button, back to Today.
Future<void> closeMenuPage(WidgetTester tester) async {
  await tap(tester, find.byTooltip('Back'));
  await pumpUntil(tester, find.byTooltip('Back'), present: false);
  await pumpUntil(tester, find.byKey(Homepage.menuKey).hitTestable());
}

// A Log-fan wedge, by its habit's name: the fan names each by a label.
Finder fanWedge(String viceName) => find
    .byWidgetPredicate(
      (Widget w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('fan-wedge-') &&
          w is! Positioned,
      description: 'a Log-fan wedge',
    )
    .withText(viceName);

extension on Finder {
  // The wedge whose label reads [text]; More stands for habits past eight.
  Finder withText(String text) =>
      find.descendant(of: this, matching: find.text(text));
}

// Records through Today's Log fan: a hold on the habit's wedge opens the
// record dialog with it chosen, or More does when the fan has no room for it.
// With [at], unlocks the date field and types the time, as a user correcting
// the clock would.
Future<void> recordActivity(
  WidgetTester tester,
  String viceName,
  int quantity, {
  DateTime? at,
}) async {
  await tap(tester, find.byType(LogButton));
  final Finder wedge = fanWedge(viceName);
  final Finder more = fanWedge('More');
  await pumpUntilTrue(
    tester,
    () =>
        wedge.hitTestable().evaluate().isNotEmpty ||
        more.hitTestable().evaluate().isNotEmpty,
    () => 'the Log fan to open',
  );
  // Let the wedges finish springing out before holding one.
  await pumpFor(tester, const Duration(milliseconds: 800));
  if (wedge.evaluate().isNotEmpty) {
    await tester.longPress(wedge);
  } else {
    await tester.tap(more);
  }
  await tester.pump();
  final Finder dialog = find.byType(AlertDialog);
  await pumpUntil(tester, dialog);
  final Finder chosen = find.descendant(
    of: find.byType(RecordNewActivityDialog),
    matching: find.byType(DropdownButtonFormField<String>),
  );
  if (find
      .descendant(of: chosen, matching: find.text(viceName))
      .evaluate()
      .isEmpty) {
    await tap(tester, chosen);
    await tap(tester, find.text(viceName).last);
  }
  if (at != null) {
    await tap(tester, find.byTooltip('Manually enter date and time'));
    await enterText(
      tester,
      'Date and Time',
      ActivityDateField.format.format(at),
    );
  }
  await enterText(tester, 'Quantity', '$quantity');
  await tap(tester, find.descendant(of: dialog, matching: find.text('Record')));
  await pumpUntil(tester, dialog, present: false);
}

// Logs one of [viceName] now with its tally's +.
Future<void> logOne(WidgetTester tester, String viceName) async {
  final Finder row = find.byWidgetPredicate(
    (Widget w) => w is TallyRow && w.vice.name == viceName,
    skipOffstage: false,
  );
  await pumpUntil(tester, row);
  final TallyRow tally = tester.widget<TallyRow>(row);
  final String label = 'Log ${tally.vice.unit.label(1)} of $viceName';
  await scrollIntoView(tester, find.byTooltip(label, skipOffstage: false));
  await tap(tester, find.byTooltip(label));
}

// Scrolls Today, or the open Trends sheet, until [finder] is in the middle of
// its view, clear of the Log button.
Future<void> scrollIntoView(WidgetTester tester, Finder finder) async {
  await pumpUntilTrue(
    tester,
    () => finder.evaluate().isNotEmpty,
    () => '$finder to be built',
  );
  await Scrollable.ensureVisible(tester.element(finder.first), alignment: 0.5);
  await tester.pump();
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

// Deletes a document as another client would, with the emulators' admin
// "owner" token so the signed-in user's rules do not apply.
Future<void> deleteBypassingRules(String collection, String documentID) async {
  final HttpClient client = HttpClient();
  try {
    final Uri uri = Uri.parse(
      'http://$emulatorHost:$firestoreEmulatorPort/v1/projects/'
      '$emulatorProjectId/databases/(default)/documents/$collection/'
      '$documentID',
    );
    final HttpClientRequest request = await client.deleteUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer owner');
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('DELETE $uri returned ${response.statusCode}: $body');
    }
  } finally {
    client.close();
  }
}

// Today's tallies, each as "Name (2 drinks)", or null while the day loads.
Set<String>? todayTallies(WidgetTester tester) {
  final List<TallyRow> rows = tester
      .widgetList<TallyRow>(
        find.byWidgetPredicate(
          // A day opened from Trends draws its tallies without a +.
          (Widget w) => w is TallyRow && w.onLog != null,
          skipOffstage: false,
        ),
      )
      .toList();
  if (rows.isEmpty || rows.any((TallyRow row) => row.total == null)) {
    return null;
  }
  return <String>{
    for (final TallyRow row in rows)
      '${row.vice.name} (${row.vice.unit.label(row.total!)})',
  };
}

// Waits for Today to show exactly [tallies]: the dial's summary, which names
// every habit's total, and every tally row built so far (the list builds rows
// only as they near the screen).
Future<void> expectTallies(WidgetTester tester, Set<String> tallies) {
  bool matches() {
    final String? summary = dialSummary(tester);
    final Set<String>? built = todayTallies(tester);
    if (summary == null || built == null || !tallies.containsAll(built)) {
      return false;
    }
    final String totals = summary.substring(
      summary.indexOf('. ') + 2,
      summary.contains(' First entry ') || summary.contains(' One entry')
          ? summary.lastIndexOf(RegExp(r'\. (First|One) entry'))
          : summary.lastIndexOf('. Nothing recorded.'),
    );
    final Set<String> spoken = <String>{
      for (final String t in tallies)
        '${t.substring(0, t.lastIndexOf(' ('))} '
            '${t.substring(t.lastIndexOf(' (') + 2, t.length - 1)}',
    };
    return setEquals(totals.split(', ').toSet(), spoken);
  }

  return pumpUntilTrue(
    tester,
    matches,
    () =>
        'Today to show $tallies (rows: ${todayTallies(tester)}; '
        'dial: ${dialSummary(tester)})',
  );
}

String? dialSummary(WidgetTester tester) {
  final Finder dial = find.byType(DayDial, skipOffstage: false);
  return dial.evaluate().isEmpty
      ? null
      // Today's comes first; a day opened from Trends adds another.
      : tester.widget<DayDial>(dial.first).semanticsLabel;
}

Future<void> signOutThroughSettings(WidgetTester tester) async {
  await openFromMenu(tester, Homepage.settingsItem);
  // Sign out pops Settings; popping while its push is still animating trips
  // a framework Hero assertion (heroes.dart, manifest.fromHero == toHero).
  await pumpFor(tester, const Duration(seconds: 1));
  await tap(tester, find.text('Sign out'));
  await pumpUntil(tester, find.byType(Homepage), present: false);
}

Future<void> signIn(WidgetTester tester, String email) async {
  await pumpUntil(tester, find.byKey(Authenticate.signInTab));
  await enterText(tester, 'Email', email);
  await enterText(tester, 'Password', 'Passw0rdE2E');
  await tap(tester, find.widgetWithText(ElevatedButton, 'Sign in'));
}

// Every string the app shows, offstage tabs, Today's tallies and the dial's
// spoken summary included.
Set<String> shownStrings(WidgetTester tester) => <String>{
  for (final Element e in find.byType(Text, skipOffstage: false).evaluate())
    ?((e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText()),
  ...?todayTallies(tester),
  ?dialSummary(tester),
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

// Opens the Trends sheet with a tap on its peek, and waits for it to settle.
Future<void> openTrends(WidgetTester tester) async {
  await tap(
    tester,
    find.descendant(
      of: find.byType(TrendsSheet),
      matching: find.text(TrendsSheet.title),
    ),
  );
  await pumpUntil(tester, find.byTooltip(TrendsSheet.closeLabel).hitTestable());
  await pumpFor(tester, const Duration(milliseconds: 500));
}

Future<void> closeTrends(WidgetTester tester) async {
  // Close sits at the top of the sheet, which may have scrolled.
  await scrollIntoView(tester, find.byTooltip(TrendsSheet.closeLabel));
  await tap(tester, find.byTooltip(TrendsSheet.closeLabel));
  await pumpUntil(tester, find.byType(LogButton).hitTestable());
  await pumpFor(tester, const Duration(milliseconds: 500));
}
