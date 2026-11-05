import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/json_fields.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/main.dart';
import 'package:tracker/vice_activity_editor_page.dart';
import 'package:tracker/widgets/activity_date_field.dart';
import 'package:tracker/widgets/clean_day.dart';

import 'support.dart';

final Finder _back = find.widgetWithIcon(IconButton, Icons.arrow_back);
final Finder _forward = find.widgetWithIcon(IconButton, Icons.arrow_forward);
final Finder _dayMenu = find.byType(DropdownButton<DateTime>);

DateTime _shownDay(WidgetTester tester) =>
    tester.widget<DropdownButton<DateTime>>(_dayMenu).value!;

// The forward arrow is meant to be disabled on today only; the bug greyed out
// every control after the first navigation.
void _expectControlsEnabled(WidgetTester tester, {required bool onToday}) {
  expect(tester.widget<IconButton>(_back).onPressed, isNotNull, reason: 'back');
  expect(
    tester.widget<IconButton>(_forward).onPressed,
    onToday ? isNull : isNotNull,
    reason: 'forward',
  );
  expect(
    tester.widget<DropdownButton<DateTime>>(_dayMenu).onChanged,
    isNotNull,
    reason: 'date menu',
  );
}

Future<void> _pickDay(WidgetTester tester, DateTime day) async {
  await tap(tester, _dayMenu);
  // The menu fades in; taps during the animation miss.
  await pumpFor(tester, const Duration(milliseconds: 500));
  // The menu scrolls to line the selected day up with the button. In macOS's
  // window the button sits too close to the top for the newer days above it,
  // which stay scrolled out of view until the user scrolls back.
  await tester.ensureVisible(
    find.descendant(
      of: find.byType(ListView),
      matching: find.text(formatDay(day), skipOffstage: false),
      skipOffstage: false,
    ),
  );
  await pumpFor(tester, const Duration(milliseconds: 500));
  await tap(tester, find.text(formatDay(day)).last);
  await pumpFor(tester, const Duration(milliseconds: 500));
}

Future<void> _startApp(WidgetTester tester, String email) async {
  await tester.pumpWidget(const ProviderScope(child: MyApp()));
  await register(tester, email);
  await addVicesThroughManageData(tester);
}

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('arrows and the date menu change the charted day and stay '
      'enabled', (WidgetTester tester) async {
    await _startApp(tester, 'e2e-days@example.com');

    final DateTime today = startOfDay(DateTime.now());
    final DateTime yesterday = addDays(today, -1);
    final DateTime twoDaysAgo = addDays(today, -2);
    const Set<String> todayChart = <String>{
      'Coffee (2 drinks)',
      'Tea (0 drinks)',
      'Water (0 drinks)',
    };
    const Set<String> yesterdayChart = <String>{
      'Coffee (0 drinks)',
      'Tea (3 drinks)',
      'Water (1 drink)',
    };
    final Finder emptyDay = find.text('A clear day');

    await recordActivity(tester, 'Coffee', 2);
    await recordActivity(
      tester,
      'Tea',
      3,
      at: yesterday.add(const Duration(hours: 12)),
    );
    await recordActivity(
      tester,
      'Water',
      1,
      at: yesterday.add(const Duration(hours: 20, minutes: 30)),
    );

    await expectChart(tester, todayChart);
    expect(_shownDay(tester), today);
    _expectControlsEnabled(tester, onToday: true);

    await tap(tester, _back);
    expect(_shownDay(tester), yesterday);
    expect(find.text('Yesterday'), findsOneWidget);
    await expectChart(tester, yesterdayChart);
    _expectControlsEnabled(tester, onToday: false);
    await screenshot(tester, 'today-view-on-yesterday');

    await tap(tester, _back);
    expect(_shownDay(tester), twoDaysAgo);
    await pumpUntil(tester, emptyDay);
    _expectControlsEnabled(tester, onToday: false);

    await tap(tester, _forward);
    expect(_shownDay(tester), yesterday);
    await expectChart(tester, yesterdayChart);
    _expectControlsEnabled(tester, onToday: false);

    await tap(tester, _forward);
    expect(_shownDay(tester), today);
    await expectChart(tester, todayChart);
    _expectControlsEnabled(tester, onToday: true);

    await _pickDay(tester, yesterday);
    expect(_shownDay(tester), yesterday);
    await expectChart(tester, yesterdayChart);
    _expectControlsEnabled(tester, onToday: false);

    await _pickDay(tester, twoDaysAgo);
    expect(_shownDay(tester), twoDaysAgo);
    await pumpUntil(tester, emptyDay);
    _expectControlsEnabled(tester, onToday: false);

    await _pickDay(tester, today);
    expect(_shownDay(tester), today);
    await expectChart(tester, todayChart);
    _expectControlsEnabled(tester, onToday: true);

    await tap(tester, find.text('Graph'));
    await pumpUntil(tester, find.text('Usage Graph'));
    await screenshot(tester, 'usage-graph-tab');
  });

  testWidgets('Undo on the record snackbar deletes the activity just recorded', (
    WidgetTester tester,
  ) async {
    await _startApp(tester, 'e2e-undo@example.com');

    await recordActivity(tester, 'Coffee', 2);
    await pumpUntil(tester, find.text('Activity recorded'));
    await recordActivity(tester, 'Water', 1);
    // Only the latest recording's snackbar may be showing, or Undo would reach
    // an older activity.
    await pumpUntil(tester, find.text('Activity recorded'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('Activity recorded'), findsOneWidget);
    expect(await storedActivities('Water'), hasLength(1));
    // Past the old four-second duration, inside the eight-second one.
    await pumpFor(tester, const Duration(seconds: 6));
    expect(find.text('Undo').hitTestable(), findsOneWidget);
    await tap(tester, find.text('Undo'));
    await pumpUntil(tester, find.text('Activity removed'));

    expect(await storedActivities('Water'), isEmpty);
    expect(await storedActivities('Coffee'), hasLength(1));
    await expectChart(tester, const <String>{
      'Coffee (2 drinks)',
      'Tea (0 drinks)',
      'Water (0 drinks)',
    });
  });

  testWidgets('one or two vices chart as bars, three as a radar, and an empty '
      'day reads as a clear day', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, 'e2e-bars@example.com');
    await addVicesThroughManageData(tester, const <String>['Coffee']);

    final DateTime today = startOfDay(DateTime.now());
    await pumpUntil(tester, find.byType(CleanDay));
    expect(find.text('A clear day so far'), findsOneWidget);
    await screenshot(tester, 'today-clean-day');

    await recordActivity(tester, 'Coffee', 2);
    await expectBars(tester, const <String>{'Coffee (2 drinks)'});
    await screenshot(tester, 'today-bars-one-vice');

    await addVicesThroughManageData(tester, const <String>['Tea']);
    await recordActivity(tester, 'Tea', 1);
    await recordActivity(
      tester,
      'Tea',
      3,
      at: addDays(today, -1).add(const Duration(hours: 12)),
    );
    await expectBars(tester, const <String>{
      'Coffee (2 drinks)',
      'Tea (1 drink)',
    });
    await screenshot(tester, 'today-bars-two-vices');

    await tap(tester, _back);
    expect(_shownDay(tester), addDays(today, -1));
    await expectBars(tester, const <String>{
      'Coffee (0 drinks)',
      'Tea (3 drinks)',
    });
    await tap(tester, _back);
    await pumpUntil(tester, find.text('A clear day'));
    await tap(tester, find.text('Jump to Today'));
    await expectBars(tester, const <String>{
      'Coffee (2 drinks)',
      'Tea (1 drink)',
    });

    await addVicesThroughManageData(tester, const <String>['Water']);
    await expectRadar(tester, const <String>{
      'Coffee (2 drinks)',
      'Tea (1 drink)',
      'Water (0 drinks)',
    });
    await screenshot(tester, 'today-radar-three-vices');
  });

  testWidgets('an activity can be deleted from the history page and from the '
      'editor', (WidgetTester tester) async {
    await _startApp(tester, 'e2e-delete@example.com');

    final DateTime today = startOfDay(DateTime.now());
    await recordActivity(tester, 'Coffee', 1);
    await recordActivity(
      tester,
      'Coffee',
      2,
      at: addDays(today, -1).add(const Duration(hours: 9)),
    );
    await recordActivity(
      tester,
      'Coffee',
      3,
      at: addDays(today, -3).add(const Duration(hours: 18)),
    );
    expect(await storedActivities('Coffee'), hasLength(3));

    await openFromDrawer(tester, 'Manage Data');
    await pumpUntil(tester, find.text('3 activities'));
    await tap(tester, find.text('Coffee'));
    await pumpUntil(tester, find.text('Coffee history'));
    final Finder rows = find.byType(Card);
    await pumpUntil(tester, rows);
    expect(rows, findsNWidgets(3));
    expect(
      find.descendant(of: rows, matching: find.byTooltip('Edit')),
      findsNothing,
    );
    await screenshot(tester, 'history-page');

    final Finder threeDrinksRow = find.ancestor(
      of: find.text('Quantity: 3'),
      matching: find.byType(Card),
    );
    await tap(
      tester,
      find.descendant(of: threeDrinksRow, matching: find.byTooltip('Delete')),
    );
    await pumpUntil(tester, find.text('Activity deleted'));
    await pumpUntil(tester, find.text('Quantity: 3'), present: false);
    expect(rows, findsNWidgets(2));
    expect(
      (await storedActivities(
        'Coffee',
      )).map((doc) => doc.data()['quantity']).toSet(),
      <int>{1, 2},
    );

    await tap(tester, find.text('Quantity: 2'));
    await pumpUntilRouteSettled(tester, find.text('Edit Coffee activity'));
    await tap(
      tester,
      find.descendant(
        of: find.byType(ViceActivityEditorPage),
        matching: find.byTooltip('Delete'),
      ),
    );
    // The history page is off stage until the editor has popped.
    await pumpUntil(tester, find.text('Coffee history').hitTestable());
    await pumpUntil(
      tester,
      find.byType(ViceActivityEditorPage),
      present: false,
    );
    await pumpUntil(tester, find.text('Quantity: 2'), present: false);
    expect(rows, findsOneWidget);
    expect(find.text('Quantity: 1'), findsOneWidget);
    expect(
      (await storedActivities(
        'Coffee',
      )).map((doc) => doc.data()['quantity']).toList(),
      <int>[1],
    );
  });
  testWidgets('editing a legacy activity writes only the field the user '
      'changed, never a parser default', (WidgetTester tester) async {
    await _startApp(tester, 'e2e-legacy@example.com');

    final String viceID = await storedViceID('Coffee');
    final String uid = FirebaseAuth.instance.currentUser!.uid;
    final DateTime today = startOfDay(DateTime.now());
    await createBypassingRules('activities', 'legacy-date', <String, Object>{
      'viceID': <String, Object>{'stringValue': viceID},
      'ownerID': <String, Object>{'stringValue': uid},
      'quantity': <String, Object>{'integerValue': '4'},
      'createdAt': <String, Object>{'stringValue': '2024-01-01'},
    });
    await createBypassingRules(
      'activities',
      'legacy-quantity',
      <String, Object>{
        'viceID': <String, Object>{'stringValue': viceID},
        'ownerID': <String, Object>{'stringValue': uid},
        'quantity': <String, Object>{'doubleValue': 2.5},
        'createdAt': <String, Object>{
          'timestampValue': addDays(
            today,
            -2,
          ).add(const Duration(hours: 12)).toUtc().toIso8601String(),
        },
      },
    );

    Future<Map<String, dynamic>> stored(String id) async =>
        (await FirebaseFirestore.instance
                .collection('activities')
                .doc(id)
                .get(const GetOptions(source: Source.server)))
            .data()!;

    Future<void> saveEditor() async {
      await tap(tester, find.widgetWithText(TextButton, 'Save'));
      await pumpUntil(
        tester,
        find.byType(ViceActivityEditorPage),
        present: false,
      );
    }

    await openFromDrawer(tester, 'Manage Data');
    await tap(tester, find.text('Coffee'));
    await pumpUntil(tester, find.text('Coffee history'));

    await tap(tester, find.text('Quantity: 4'));
    await pumpUntilRouteSettled(tester, find.text('Edit Coffee activity'));
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Date and Time'),
          )
          .controller!
          .text,
      ActivityDateField.format.format(epoch.toDate()),
    );
    await enterText(tester, 'Quantity', '5');
    await saveEditor();
    expect(await stored('legacy-date'), <String, dynamic>{
      'viceID': viceID,
      'ownerID': uid,
      'quantity': 5,
      'createdAt': '2024-01-01',
    });

    // 2.5 reads as 3.
    await pumpUntil(tester, find.text('Quantity: 3').hitTestable());
    await tap(tester, find.text('Quantity: 3'));
    await pumpUntilRouteSettled(tester, find.text('Edit Coffee activity'));
    final DateTime moved = addDays(today, -1).add(const Duration(hours: 9));
    await enterText(
      tester,
      'Date and Time',
      ActivityDateField.format.format(moved),
    );
    await saveEditor();
    final Map<String, dynamic> requantified = await stored('legacy-quantity');
    expect(requantified['quantity'], 2.5);
    expect((requantified['createdAt'] as Timestamp).toDate(), moved);
    await pumpUntil(
      tester,
      find
          .textContaining(
            'on ${formatDayAndTime(moved, alwaysUse24HourFormat: tester.platformDispatcher.alwaysUse24HourFormat)}',
          )
          .hitTestable(),
    );
  });
}
