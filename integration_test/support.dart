import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' hide Settings;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tracker/authenticate.dart';
import 'package:tracker/crypto/journal_field_sealer.dart';
import 'package:tracker/crypto/key_store.dart';
import 'package:tracker/crypto/native_aes.dart';
import 'package:tracker/crypto/plaintext_migration.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/main.dart';
import 'package:tracker/manage_data.dart';
import 'package:tracker/onboarding/onboarding.dart';
import 'package:tracker/onboarding/presets.dart';
import 'package:tracker/settings.dart';
import 'package:tracker/trends/trends_sheet.dart';
import 'package:tracker/vice_activity_history_page.dart';
import 'package:tracker/widgets/day_dial.dart';
import 'package:tracker/widgets/day_picker.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/dial_layout.dart';
import 'package:tracker/widgets/time_dial.dart';
import 'package:tracker/widgets/log_fan.dart';
import 'package:tracker/widgets/native_auth_field.dart';
import 'package:tracker/widgets/tally_row.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';
import 'package:tracker/widgets/trigger_picker.dart';

import '../test/fake_sealer.dart';

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
  // flutter_test cannot type into the AppKit fields the Mac build uses for sign-in.
  debugUseNativeAuthFields = false;
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

// Types [text] into the open amount sheet's Quantity field and reads the
// field back. On a slow hosted runner the text sometimes never reaches the
// field, and the sheet, which opens holding the default amount, would record
// that instead, so it types again until the field holds it.
Future<void> enterQuantity(WidgetTester tester, String text) async {
  final Finder editable = find.descendant(
    of: find.widgetWithText(TextFormField, 'Quantity'),
    matching: find.byType(EditableText),
  );
  for (int attempt = 0; attempt < 3; attempt++) {
    await enterText(tester, 'Quantity', text);
    await tester.pump(const Duration(milliseconds: 100));
    if (tester.widget<EditableText>(editable).controller.text == text) {
      return;
    }
  }
  throw TestFailure('The Quantity field did not keep "$text" after 3 tries');
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

// A new account starts on the onboarding, which this skips unless told not
// to: a test that drives it, or one whose habit list fails to load, which
// shows none.
Future<void> register(
  WidgetTester tester,
  String email, {
  bool skipOnboarding = true,
}) async {
  // Auth keeps the signed-in user in the iOS keychain, which survives both
  // reinstalls and the emulator wipe.
  // A persisted user arrives asynchronously after launch, on the Mac later
  // than a signOut sent straight away, which would find nobody to sign out.
  await FirebaseAuth.instance.authStateChanges().first;
  await FirebaseAuth.instance.signOut();
  await tap(tester, find.byKey(Authenticate.registerTab));
  // The confirmation fades in as the tab switches.
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
  if (skipOnboarding) {
    await skipTheOnboarding(tester);
  }
}

// Skip, then the disclaimer, to the empty Today.
Future<void> skipTheOnboarding(WidgetTester tester) async {
  await pumpUntil(tester, find.text(OnboardingCopy.introHeadline));
  await tap(tester, find.byKey(Onboarding.skipKey));
  await pumpUntil(tester, find.text(OnboardingCopy.acknowledge));
  await tap(tester, find.text(OnboardingCopy.acknowledge));
  await pumpUntil(tester, find.byType(Onboarding), present: false);
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
Finder historyEntry(num quantity) => find.descendant(
  of: historyRows,
  matching: find.byWidgetPredicate(
    (Widget w) =>
        w is Text && (w.data?.startsWith('${formatCount(quantity)} ') ?? false),
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

// Sets the open amount sheet's or editor's time to [at], on the 5-minute
// grid, as a user would: the day from the calendar under the time dial, then
// a tap on the dial at the minute's angle.
Future<void> setEntryTime(WidgetTester tester, DateTime at) async {
  assert(at.second == 0 && at.minute % TimeDial.step == 0);
  final Finder field = find.byType(EntryTimeField);
  EntryTimeController controller() =>
      tester.widget<EntryTimeField>(field).controller;
  final DateTime day = startOfDay(at);
  if (startOfDay(controller().value) != day) {
    final Finder dayButton = find
        .descendant(of: field, matching: find.byType(TextButton))
        .first;
    await scrollIntoView(tester, dayButton);
    await tap(tester, dayButton);
    final Finder sheet = find.byType(CalendarSheet);
    await pumpUntilRouteSettled(tester, sheet);
    while (find
        .descendant(of: sheet, matching: find.text(formatMonth(day)))
        .evaluate()
        .isEmpty) {
      final DateTime shown = startOfDay(controller().value);
      await tap(
        tester,
        find.byTooltip(day.isBefore(shown) ? 'Previous month' : 'Next month'),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tap(
      tester,
      find.descendant(of: sheet, matching: find.text(formatCount(day.day))),
    );
    await pumpUntil(tester, sheet, present: false);
  }
  final Finder dial = find.byType(TimeDial);
  await scrollIntoView(tester, dial);
  final Rect rect = tester.getRect(dial);
  await tester.tapAt(
    rect.center +
        dialPoint(dialAngle(at.hour * 60.0 + at.minute), rect.width * 0.35),
  );
  await pumpUntilTrue(
    tester,
    () => controller().at == at,
    () => 'the time dial to show $at, not ${controller().value}',
  );
}

// Records through Today's Log fan: a hold on the habit's wedge opens the
// amount sheet with it chosen, or More does when the fan has no room for it.
// With [at], picks its day and time on the sheet's time dial (setEntryTime).
Future<void> recordActivity(
  WidgetTester tester,
  String viceName,
  num quantity, {
  DateTime? at,
  List<String> triggerTaps = const <String>[],
}) async {
  // Frames draw only on a pump here, and the fan keeps the habits the button
  // held when it opened: a write made outside the tree since the last frame
  // would be missing from it.
  await tester.pump();
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
  final Finder dialog = find.byType(RecordNewActivityDialog);
  await pumpUntilRouteSettled(tester, dialog);
  final Finder chosen = find.descendant(
    of: find.byType(RecordNewActivityDialog),
    matching: find.byType(DropdownButtonFormField<String>),
  );
  // A held wedge titles the sheet with its habit and shows no dropdown; More
  // opens it with the dropdown and no habit chosen.
  if (chosen.evaluate().isNotEmpty &&
      find
          .descendant(of: chosen, matching: find.text(viceName))
          .evaluate()
          .isEmpty) {
    await tap(tester, chosen);
    await tap(tester, find.text(viceName).last);
  }
  if (at != null) {
    await setEntryTime(tester, at);
  }
  final String typed = formatAmount(quantity);
  await enterQuantity(tester, typed);
  if (triggerTaps.isNotEmpty) {
    // Each label in [triggerTaps] is tapped in the picker in turn.
    final Finder open = find.text('What was going on? (optional)');
    await scrollIntoView(tester, open);
    await tap(tester, open);
    final Finder sheet = find.byType(TriggerPickerSheet);
    await pumpUntilRouteSettled(tester, sheet);
    for (final String label in triggerTaps) {
      final Finder target = find.descendant(
        of: sheet,
        matching: find.text(label),
      );
      await scrollIntoView(tester, target);
      await tap(tester, target);
    }
    await tap(tester, find.descendant(of: sheet, matching: find.text('Done')));
    await pumpUntil(tester, sheet, present: false);
  }
  await enterQuantity(tester, typed);
  // A focused field scrolls itself back into view, away from the button.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  final Finder submit = find.byKey(RecordNewActivityDialog.submitKey);
  await tap(tester, submit);
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

// The rules refuse a create without its sealed field, so every app the tests
// pump seals. Those not launched through startApp, whose key service would
// put a journal key in the keychain and gate the first launch on it, seal
// with this fixed key instead.
final FakeSealer e2eSealer = FakeSealer();

// With a key the first-launch migrator would seal the legacy documents a test
// writes past the rules, partway through the test; sealing_migration_test
// runs it on purpose.
class _NoMigration extends PlaintextMigration {
  @override
  MigrationStatus build() => MigrationStatus.idle;
}

Widget e2eApp({Key? key, List<Override> overrides = const <Override>[]}) =>
    ProviderScope(
      key: key,
      overrides: <Override>[
        sealerProvider.overrideWithValue(e2eSealer),
        plaintextMigrationProvider.overrideWith(_NoMigration.new),
        ...overrides,
      ],
      child: const MyApp(),
    );

// A document's content fields, opened with the keychain's key (a launch
// through startApp) or [e2eSealer]; a plaintext document as it is.
Future<Map<String, Object?>> storedContent(
  DocumentSnapshot<Map<String, dynamic>> doc,
) async {
  final Map<String, dynamic> data = doc.data()!;
  final Object? envelope = data[sealedField];
  if (envelope is! Blob) {
    return data;
  }
  final StoredKey? stored = await KeyStore().read(
    FirebaseAuth.instance.currentUser!.uid,
  );
  for (final FieldSealer sealer in <FieldSealer>[
    if (stored != null)
      JournalFieldSealer(
        stored.journalKey.sealer(nativeAesGcm(secretKeyLength: 32)),
      ),
    e2eSealer,
  ]) {
    try {
      return await sealer.open(
        envelope.bytes,
        context: sealContext(doc.reference.parent.id, doc.id),
      );
    } on Object {
      continue;
    }
  }
  throw StateError('no key opens ${doc.reference.path}');
}

Future<String> storedViceID(String viceName) async {
  final String uid = FirebaseAuth.instance.currentUser!.uid;
  final QuerySnapshot<Map<String, dynamic>> vices = await FirebaseFirestore
      .instance
      .collection('vices')
      .where('ownerID', isEqualTo: uid)
      .get();
  final List<String> matches = <String>[
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in vices.docs)
      if ((await storedContent(doc))['name'] == viceName) doc.id,
  ];
  expect(matches, hasLength(1), reason: 'vice $viceName');
  return matches.single;
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

// [createBypassingRules] for many documents of one collection, a commit of
// up to 400 at a time.
Future<void> createAllBypassingRules(
  String collection,
  Map<String, Map<String, Object>> documents,
) async {
  const String root = 'projects/$emulatorProjectId/databases/(default)';
  final HttpClient client = HttpClient();
  try {
    final Uri uri = Uri.parse(
      'http://$emulatorHost:$firestoreEmulatorPort/v1/$root/documents:commit',
    );
    final List<MapEntry<String, Map<String, Object>>> all = documents.entries
        .toList();
    for (int start = 0; start < all.length; start += 400) {
      final HttpClientRequest request = await client.postUrl(uri);
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer owner')
        ..contentType = ContentType.json;
      request.write(
        jsonEncode(<String, Object>{
          'writes': <Object>[
            for (final MapEntry<String, Map<String, Object>>(:key, :value)
                in all.skip(start).take(400))
              <String, Object>{
                'update': <String, Object>{
                  'name': '$root/documents/$collection/$key',
                  'fields': value,
                },
                'currentDocument': <String, Object>{'exists': false},
              },
          ],
        }),
      );
      final HttpClientResponse response = await request.close();
      final String body = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('POST $uri returned ${response.statusCode}: $body');
      }
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

// Whether a document exists, read with the emulators' admin "owner" token so
// it works with nobody signed in.
Future<bool> existsBypassingRules(String collection, String documentID) async {
  final HttpClient client = HttpClient();
  try {
    final Uri uri = Uri.parse(
      'http://$emulatorHost:$firestoreEmulatorPort/v1/projects/'
      '$emulatorProjectId/databases/(default)/documents/$collection/'
      '$documentID',
    );
    final HttpClientRequest request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer owner');
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    switch (response.statusCode) {
      case HttpStatus.ok:
        return true;
      case HttpStatus.notFound:
        return false;
    }
    throw StateError('GET $uri returned ${response.statusCode}: $body');
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
  await expectSignInWithNothingAbove(tester);
}

// Settings hides Homepage offstage, so Homepage vanishing does not mean the
// sign-out has finished.
Future<void> expectSignInWithNothingAbove(WidgetTester tester) async {
  await pumpUntil(tester, find.byKey(Authenticate.registerTab).hitTestable());
  await pumpUntil(
    tester,
    find.byType(Settings, skipOffstage: false),
    present: false,
  );
  await pumpUntil(
    tester,
    find.byType(Homepage, skipOffstage: false),
    present: false,
  );
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

// Whether Trends is a pane beside Today (900 pt and up: the Mac window as it
// opens, or an iPad on its side) rather than a sheet over it.
bool splitLayout(WidgetTester tester) =>
    find.byType(TrendsSheet).evaluate().isNotEmpty &&
    find.byType(DraggableScrollableSheet).evaluate().isEmpty;

// Opens the Trends sheet with a tap on its peek, and waits for it to settle.
// The split view's pane is always open, so there it waits for the pane.
Future<void> openTrends(WidgetTester tester) async {
  await pumpUntil(tester, find.byType(TrendsSheet));
  if (splitLayout(tester)) {
    await pumpUntil(
      tester,
      find.descendant(
        of: find.byType(TrendsSheet),
        matching: find.text(TrendsSheet.title),
      ),
    );
    return;
  }
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

// The pane has no Close; there this only checks Log is still in reach.
Future<void> closeTrends(WidgetTester tester) async {
  if (splitLayout(tester)) {
    await pumpUntil(tester, find.byType(LogButton).hitTestable());
    return;
  }
  // Close sits at the top of the sheet, which may have scrolled.
  await scrollIntoView(tester, find.byTooltip(TrendsSheet.closeLabel));
  await tap(tester, find.byTooltip(TrendsSheet.closeLabel));
  await pumpUntil(tester, find.byType(LogButton).hitTestable());
  await pumpFor(tester, const Duration(milliseconds: 500));
}
