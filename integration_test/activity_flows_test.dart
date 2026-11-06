import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/json_fields.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/main.dart';
import 'package:tracker/vice_activity_editor_page.dart';
import 'package:tracker/widgets/activity_date_field.dart';
import 'package:tracker/widgets/day_dial.dart';
import 'package:tracker/widgets/day_picker.dart';
import 'package:tracker/widgets/log_fan.dart';
import 'package:tracker/writes/log_one.dart' show removedMessage;

import 'support.dart';

final Finder _back = find.byTooltip('Previous day');
final Finder _forward = find.byTooltip('Next day');
final Finder _pill = find.byTooltip(DayPicker.chooseDay);

DateTime _shownDay(WidgetTester tester) =>
    tester.widget<DayDial>(find.byType(DayDial)).day;

bool _arrowEnabled(WidgetTester tester, Finder arrow) =>
    tester
        .widget<IconButton>(
          find.ancestor(of: arrow, matching: find.byType(IconButton)),
        )
        .onPressed !=
    null;

// The forward arrow is meant to be disabled on today only; the bug greyed out
// every control after the first navigation.
void _expectControlsEnabled(WidgetTester tester, {required bool onToday}) {
  expect(_arrowEnabled(tester, _back), isTrue, reason: 'back');
  expect(_arrowEnabled(tester, _forward), !onToday, reason: 'forward');
  expect(
    tester
        .widget<InkWell>(
          find.descendant(of: _pill, matching: find.byType(InkWell)),
        )
        .onTap,
    isNotNull,
    reason: 'date pill',
  );
}

// Picks [day] from the calendar the date pill opens.
Future<void> _pickDay(WidgetTester tester, DateTime day) async {
  await tap(tester, _pill);
  final Finder sheet = find.byType(CalendarSheet);
  await pumpUntilRouteSettled(tester, sheet);
  final DateTime shown = _shownDay(tester);
  if (shown.year != day.year || shown.month != day.month) {
    await tap(tester, find.byTooltip('Previous month'));
    await pumpUntil(tester, find.text(formatMonth(day)));
  }
  await tap(
    tester,
    find.descendant(of: sheet, matching: find.text(formatCount(day.day))),
  );
  await pumpUntil(tester, sheet, present: false);
  await pumpUntilTrue(
    tester,
    () => _shownDay(tester) == day,
    () => 'the dial to show $day',
  );
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

  testWidgets('arrows and the calendar change the shown day and stay '
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

    await expectTallies(tester, todayChart);
    expect(_shownDay(tester), today);
    _expectControlsEnabled(tester, onToday: true);

    await tap(tester, _back);
    expect(_shownDay(tester), yesterday);
    expect(find.text('Yesterday'), findsOneWidget);
    await expectTallies(tester, yesterdayChart);
    _expectControlsEnabled(tester, onToday: false);
    await screenshot(tester, 'today-view-on-yesterday');

    await tap(tester, _back);
    expect(_shownDay(tester), twoDaysAgo);
    await pumpUntil(tester, emptyDay);
    _expectControlsEnabled(tester, onToday: false);

    await tap(tester, _forward);
    expect(_shownDay(tester), yesterday);
    await expectTallies(tester, yesterdayChart);
    _expectControlsEnabled(tester, onToday: false);

    await tap(tester, _forward);
    expect(_shownDay(tester), today);
    await expectTallies(tester, todayChart);
    _expectControlsEnabled(tester, onToday: true);

    await _pickDay(tester, yesterday);
    expect(_shownDay(tester), yesterday);
    await expectTallies(tester, yesterdayChart);
    _expectControlsEnabled(tester, onToday: false);

    await _pickDay(tester, twoDaysAgo);
    expect(_shownDay(tester), twoDaysAgo);
    await pumpUntil(tester, emptyDay);
    _expectControlsEnabled(tester, onToday: false);

    await _pickDay(tester, today);
    expect(_shownDay(tester), today);
    await expectTallies(tester, todayChart);
    _expectControlsEnabled(tester, onToday: true);

    await openTrends(tester);
    await screenshot(tester, 'trends-sheet');
    await closeTrends(tester);
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
    await expectTallies(tester, const <String>{
      'Coffee (2 drinks)',
      'Tea (0 drinks)',
      'Water (0 drinks)',
    });
  });

  testWidgets("a tally's + logs one now, a wedge of the Log fan logs one, "
      'and Undo removes the latest', (WidgetTester tester) async {
    await _startApp(tester, 'e2e-one-tap@example.com');

    await logOne(tester, 'Tea');
    await pumpUntil(tester, find.textContaining('Logged 1 drink of Tea at'));
    await expectTallies(tester, const <String>{
      'Coffee (0 drinks)',
      'Tea (1 drink)',
      'Water (0 drinks)',
    });
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> tea =
        await storedActivities('Tea');
    expect(tea, hasLength(1));
    expect(tea.single.data()['quantity'], 1);
    final DateTime at = (tea.single.data()['createdAt'] as Timestamp).toDate();
    expect(DateTime.now().difference(at).inMinutes, lessThan(2));

    await tap(tester, find.byType(LogButton));
    await pumpFor(tester, const Duration(milliseconds: 800));
    await tap(tester, fanWedge('Coffee'));
    await pumpUntil(tester, find.textContaining('Logged 1 drink of Coffee at'));
    await expectTallies(tester, const <String>{
      'Coffee (1 drink)',
      'Tea (1 drink)',
      'Water (0 drinks)',
    });
    await screenshot(tester, 'today-after-one-tap');

    await tap(tester, find.text('Undo'));
    await pumpUntil(tester, find.text(removedMessage));
    expect(await storedActivities('Coffee'), isEmpty);
    expect(await storedActivities('Tea'), hasLength(1));
    await expectTallies(tester, const <String>{
      'Coffee (0 drinks)',
      'Tea (1 drink)',
      'Water (0 drinks)',
    });
  });

  testWidgets('the tallies follow each habit added and the day shown, and an '
      'empty day reads as a clear day', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, 'e2e-bars@example.com');
    await addVicesThroughManageData(tester, const <String>['Coffee']);

    final DateTime today = startOfDay(DateTime.now());
    await pumpUntil(tester, find.text(ClearDay.headline));
    expect(find.text(ClearDay.subline(isToday: true)), findsOneWidget);
    await screenshot(tester, 'today-clean-day');

    await recordActivity(tester, 'Coffee', 2);
    await expectTallies(tester, const <String>{'Coffee (2 drinks)'});
    await screenshot(tester, 'today-one-habit');

    await addVicesThroughManageData(tester, const <String>['Tea']);
    await recordActivity(tester, 'Tea', 1);
    await recordActivity(
      tester,
      'Tea',
      3,
      at: addDays(today, -1).add(const Duration(hours: 12)),
    );
    await expectTallies(tester, const <String>{
      'Coffee (2 drinks)',
      'Tea (1 drink)',
    });
    await screenshot(tester, 'today-two-habits');

    await tap(tester, _back);
    expect(_shownDay(tester), addDays(today, -1));
    await expectTallies(tester, const <String>{
      'Coffee (0 drinks)',
      'Tea (3 drinks)',
    });
    await tap(tester, _back);
    await pumpUntil(tester, find.text('A clear day'));
    await tap(tester, _forward);
    await tap(tester, _forward);
    await expectTallies(tester, const <String>{
      'Coffee (2 drinks)',
      'Tea (1 drink)',
    });

    await addVicesThroughManageData(tester, const <String>['Water']);
    await expectTallies(tester, const <String>{
      'Coffee (2 drinks)',
      'Tea (1 drink)',
      'Water (0 drinks)',
    });
    await screenshot(tester, 'today-three-habits');
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

    await openFromMenu(tester, Homepage.habitsItem);
    await pumpUntil(tester, habitsCount('3 entries'));
    await tap(tester, find.text('Coffee'));
    await pumpUntil(tester, historyTitle('Coffee'));
    final Finder rows = historyRows;
    await pumpUntil(tester, rows);
    expect(rows, findsNWidgets(3));
    expect(
      find.descendant(of: rows, matching: find.byTooltip('Edit')),
      findsNothing,
    );
    await screenshot(tester, 'history-page');

    await swipeToDelete(tester, historyEntry(3));
    await pumpUntil(tester, deletedBar);
    await pumpUntil(tester, historyEntry(3), present: false);
    expect(rows, findsNWidgets(2));
    expect(
      (await storedActivities(
        'Coffee',
      )).map((doc) => doc.data()['quantity']).toSet(),
      <int>{1, 2},
    );

    await tap(tester, historyEntry(2));
    await pumpUntilRouteSettled(tester, find.text('Edit Coffee activity'));
    await tap(
      tester,
      find.descendant(
        of: find.byType(ViceActivityEditorPage),
        matching: find.byTooltip('Delete'),
      ),
    );
    // The history page is off stage until the editor has popped.
    await pumpUntil(tester, historyTitle('Coffee').hitTestable());
    await pumpUntil(
      tester,
      find.byType(ViceActivityEditorPage),
      present: false,
    );
    await pumpUntil(tester, historyEntry(2), present: false);
    expect(rows, findsOneWidget);
    expect(historyEntry(1), findsOneWidget);
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

    await openFromMenu(tester, Homepage.habitsItem);
    await tap(tester, find.text('Coffee'));
    await pumpUntil(tester, historyTitle('Coffee'));

    await tap(tester, historyEntry(4));
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
    await pumpUntil(tester, historyEntry(3).hitTestable());
    await tap(tester, historyEntry(3));
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
