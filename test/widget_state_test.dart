import 'dart:async';

import 'package:clock/clock.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/authenticate.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/main.dart';
import 'package:tracker/manage_data.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/vice_activity_editor_page.dart';
import 'package:tracker/vice_activity_history_page.dart';
import 'package:tracker/trends/trends_sheet.dart';
import 'package:tracker/widgets/day_dial.dart';
import 'package:tracker/widgets/log_fan.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';
import 'package:tracker/widgets/time_dial.dart';
import 'package:tracker/widgets/undo_bar.dart';

import 'fake_account.dart';
import 'fake_writes.dart';
import 'fakes.dart';
import 'trends_harness.dart';

class _FakeToday extends Today {
  _FakeToday(this._start);

  final DateTime _start;

  @override
  DateTime build() => _start;

  void moveTo(DateTime day) => state = day;
}

Vice _archivedVice(String id) => Vice(
  id: id,
  name: id,
  unit: Unit.values.first,
  ownerID: ownerID,
  createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
  archived: true,
);

String _fieldText(WidgetTester tester, String label) => tester
    .widget<TextFormField>(find.widgetWithText(TextFormField, label))
    .controller!
    .text;

EntryTimeController _time(WidgetTester tester) =>
    tester.widget<EntryTimeField>(find.byType(EntryTimeField)).controller;

Future<void> _pump(
  WidgetTester tester,
  List<Override> overrides,
  Widget home,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
        offlineProvider.overrideWithValue(const AsyncData(false)),
        ...overrides,
      ],
      child: MaterialApp(home: home, onGenerateRoute: generateRoute),
    ),
  );
  await tester.pump();
}

void main() {
  final DateTime today = startOfDay(DateTime.now());
  final Vice coffee = fakeVice('coffee');
  final Vice tea = _archivedVice('tea');

  group('the app root', () {
    testWidgets('waits for the restored session instead of showing sign-in', (
      WidgetTester tester,
    ) async {
      final StreamController<User?> auth = StreamController<User?>();
      addTearDown(auth.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProvider.overrideWith((ref) => auth.stream),
            accountProvider.overrideWithValue(FakeAccount()),
            memoryJournal(),
          ],
          child: const MyApp(),
        ),
      );
      await tester.pump();

      expect(find.byType(AuthStateLoading), findsOneWidget);
      expect(find.byType(Authenticate), findsNothing);

      auth.add(null);
      await tester.pump();

      expect(find.byType(AuthStateLoading), findsNothing);
      expect(find.byType(Authenticate), findsOneWidget);
    });

    testWidgets("signing out takes the session's Undo bar with it", (
      WidgetTester tester,
    ) async {
      final StreamController<User?> auth = StreamController<User?>();
      addTearDown(auth.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProvider.overrideWith((ref) => auth.stream),
            accountProvider.overrideWithValue(FakeAccount()),
            offlineProvider.overrideWithValue(const AsyncData(false)),
            memoryJournal(),
            ...habitOverrides(<Vice>[]),
            viceActivityDayProvider.overrideWith(
              (ref, DateTime day) => const AsyncData(<ViceActivity>[]),
            ),
          ],
          child: const MyApp(),
        ),
      );
      auth.add(FakeUser(ownerID));
      await tester.pump();
      expect(find.byType(Homepage), findsOneWidget);

      bool undone = false;
      showUndoBar(
        tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)),
        const TextSpan(text: 'Logged 1 drink'),
        onUndo: () => undone = true,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Undo'), findsOneWidget);

      auth.add(null);
      await tester.pump();

      expect(find.byType(Authenticate), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(SnackBar), findsNothing);
      expect(undone, isFalse);
    });
  });

  group('past midnight', () {
    late List<DateTime> requestedDays;

    List<Override> todayOverrides(_FakeToday clock) => [
      todayProvider.overrideWith(() => clock),
      ...habitOverrides([coffee, fakeVice('beer'), fakeVice('wine')]),
      viceActivityDayProvider.overrideWith((ref, DateTime day) {
        requestedDays.add(day);
        return AsyncData(<ViceActivity>[]);
      }),
    ];

    setUp(() {
      requestedDays = <DateTime>[];
    });

    testWidgets('Today moves on to the new day', (WidgetTester tester) async {
      final DateTime yesterday = addDays(today, -1);
      final _FakeToday clock = _FakeToday(yesterday);
      await _pump(
        tester,
        todayOverrides(clock),
        const Scaffold(body: ViceTracker()),
      );
      expect(find.text('Today'), findsOneWidget);

      clock.moveTo(today);
      await tester.pump();

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsNothing);
      expect(tester.widget<DayDial>(find.byType(DayDial)).day, today);
      expect(requestedDays.last, today);
    });

    testWidgets('a day the user picked stays picked', (
      WidgetTester tester,
    ) async {
      final _FakeToday clock = _FakeToday(today);
      await _pump(
        tester,
        todayOverrides(clock),
        const Scaffold(body: ViceTracker()),
      );
      await tester.tap(find.byTooltip('Previous day'));
      await tester.pump();
      expect(find.text('Yesterday'), findsOneWidget);

      clock.moveTo(addDays(today, 1));
      await tester.pump();

      expect(
        find.text(dayWord(addDays(today, -1), addDays(today, 1))),
        findsOneWidget,
      );
      expect(
        tester.widget<DayDial>(find.byType(DayDial)).day,
        addDays(today, -1),
      );
    });

    // The days New York and London move their clocks, which last 23 or 25
    // hours under TZ=America/New_York or TZ=Europe/London.
    for (final DateTime day in <DateTime>[
      DateTime(2026, 3, 8),
      DateTime(2026, 3, 29),
      DateTime(2026, 10, 25),
      DateTime(2026, 11, 1),
    ]) {
      testWidgets("the graph's range ends on the new day (${day.month}/"
          '${day.day})', (WidgetTester tester) async {
        final DateTime next = addDays(day, 1);
        final List<ViceActivityGraphQuery> queries = <ViceActivityGraphQuery>[];
        final _FakeToday clock = _FakeToday(day);
        await _pump(tester, [
          todayProvider.overrideWith(() => clock),
          ...trendsOverrides([coffee], (ViceActivityGraphQuery query) {
            queries.add(query);
            return AsyncData(<ViceActivity>[
              fakeActivity(coffee.id, 5, day.copyWith(hour: 23, minute: 30)),
              fakeActivity(coffee.id, 3, next.copyWith(minute: 30)),
            ]);
          }),
        ], const Scaffold(body: ViceTracker()));
        await openTrends(tester);
        expect(queries.last.end, next);

        clock.moveTo(next);
        await tester.pump();

        expect(queries.last.start, addDays(next, -29));
        expect(queries.last.end, addDays(next, 1));
        final String dayLabel = formatShortDay(day);
        expect(
          find.bySemanticsLabel(RegExp('The most was 5 items on $dayLabel\\.')),
          findsOneWidget,
        );
      });
    }
  });

  group('an archived vice', () {
    testWidgets('opens in Trends, listed last and marked, and not the '
        'default', (WidgetTester tester) async {
      final List<String> graphed = <String>[];
      await _pump(tester, [
        ...trendsOverrides([tea, coffee], (ViceActivityGraphQuery query) {
          graphed.add(query.viceID);
          return const AsyncData(<ViceActivity>[]);
        }),
      ], const Scaffold(body: ViceTracker()));
      await openTrends(tester);

      expect(graphed.last, coffee.id);
      expect(
        tester.getTopLeft(inTrends(find.text('tea'))).dx,
        greaterThan(tester.getTopLeft(inTrends(find.text('coffee'))).dx),
      );
      expect(inTrends(find.text(' · archived')), findsOneWidget);

      await tester.tap(inTrends(find.text('tea')));
      await tester.pumpAndSettle();
      expect(graphed.last, tea.id);
    });

    testWidgets('with every habit archived, Trends still opens them', (
      WidgetTester tester,
    ) async {
      await _pump(tester, [
        ...trendsOverrides([tea], inRange(const <ViceActivity>[])),
      ], const Scaffold(body: ViceTracker()));

      expect(find.text(ViceTracker.noHabits), findsOneWidget);
      expect(find.byType(LogButton), findsNothing);
      await openTrends(tester);
      expect(inTrends(find.text('tea')), findsOneWidget);
    });

    testWidgets('still opens its history from Manage Data', (
      WidgetTester tester,
    ) async {
      await _pump(tester, [
        viceListProvider.overrideWithValue(AsyncData([coffee, tea])),
        activityTotalCountProvider.overrideWithValue(const AsyncLoading()),
        viceActivityCountProvider.overrideWith(
          (ref, String viceID) =>
              const AsyncData((count: 2, source: CountSource.server)),
        ),
        viceActivityHistoryProvider.overrideWith(
          (ref, ViceActivityHistoryQuery query) => AsyncData(<ViceActivity>[]),
        ),
      ], const ManageData());

      expect(find.text('1 active · 1 archived'), findsOne);
      // Active habits come first, then the archived section.
      expect(
        tester.getTopLeft(find.text('coffee')).dy,
        lessThan(tester.getTopLeft(find.text(ManageData.archivedLabel)).dy),
      );
      expect(
        tester.getTopLeft(find.text(ManageData.archivedLabel)).dy,
        lessThan(tester.getTopLeft(find.text('tea')).dy),
      );
      expect(find.text(ManageData.archivedLabel), findsOne);
      expect(find.textContaining(' · 2 entries'), findsNWidgets(2));

      await tester.tap(find.text('tea'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<ViceActivityHistoryPage>(
              find.byType(ViceActivityHistoryPage),
            )
            .viceID,
        tea.id,
      );
    });
  });

  group('the home screen', () {
    testWidgets("keeps Today's day and the Trends selection while a page is "
        'pushed over it', (WidgetTester tester) async {
      final Vice beer = fakeVice('beer');
      final List<String> graphed = <String>[];
      await _pump(tester, [
        ...trendsOverrides([coffee, beer], (ViceActivityGraphQuery query) {
          graphed.add(query.viceID);
          return const AsyncData(<ViceActivity>[]);
        }),
      ], const Homepage());

      // The peek is all there is until the sheet moves.
      expect(find.byType(LineChart), findsNothing);
      // Equal creation times order by id, so beer comes first.
      expect(graphed, <String>[beer.id]);

      await tester.tap(find.byTooltip('Previous day'));
      await tester.pump();
      expect(find.text('Yesterday'), findsOneWidget);

      await openTrends(tester);
      await tester.tap(inTrends(find.text('coffee')));
      await tester.pumpAndSettle();
      expect(graphed.last, coffee.id);

      await tester.tap(find.byKey(Homepage.menuKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Homepage.settingsItem));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(graphed.last, coffee.id);
      expect(find.text('coffee · last 30 days'), findsOneWidget);
      await tester.tap(find.byTooltip(TrendsSheet.closeLabel));
      await tester.pumpAndSettle();
      expect(find.text('Yesterday'), findsOneWidget);
    });
  });

  group('the activity editor', () {
    final ViceActivity stored = fakeActivity(
      coffee.id,
      2,
      DateTime(2026, 11, 2, 9, 30),
    );

    Future<StreamController<ViceActivity?>> pumpEditor(
      WidgetTester tester, {
      FakeTrackerWrites? writes,
    }) async {
      final StreamController<ViceActivity?> activity =
          StreamController<ViceActivity?>.broadcast();
      addTearDown(activity.close);
      await _pump(tester, [
        viceListProvider.overrideWithValue(AsyncData([coffee])),
        viceActivityForUserProvider.overrideWith((ref, key) => activity.stream),
        if (writes != null) trackerWritesProvider.overrideWithValue(writes),
        memoryJournal(),
      ], ViceActivityEditorPage(viceID: coffee.id, activityID: stored.id));
      activity.add(stored);
      await tester.pump();
      await tester.pump();
      return activity;
    }

    ViceActivity changed(int quantity, DateTime at, {bool pending = false}) =>
        ViceActivity(
          id: stored.id,
          viceID: coffee.id,
          quantity: quantity,
          ownerID: ownerID,
          createdAt: Timestamp.fromDate(at),
          pending: pending,
        );

    testWidgets('shows a change made elsewhere until the user edits a field, '
        'then keeps theirs', (WidgetTester tester) async {
      final StreamController<ViceActivity?> activity = await pumpEditor(tester);
      expect(_fieldText(tester, 'Quantity'), '2');

      final DateTime moved = DateTime(2026, 11, 2, 10);
      activity.add(changed(3, moved));
      await tester.pump();
      await tester.pump();
      expect(_fieldText(tester, 'Quantity'), '3');
      expect(_time(tester).at, moved);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Quantity'),
        '7',
      );
      activity.add(changed(4, DateTime(2026, 11, 2, 11)));
      await tester.pump();
      await tester.pump();

      expect(_fieldText(tester, 'Quantity'), '7');
      expect(_time(tester).at, DateTime(2026, 11, 2, 11));
    });

    for (final bool rollbackFirst in <bool>[true, false]) {
      testWidgets('keeps a refused edit as unsaved against the stored value '
          '(rollback ${rollbackFirst ? 'before' : 'after'} the refusal)', (
        WidgetTester tester,
      ) async {
        final Completer<void> refusal = Completer<void>();
        final FakeTrackerWrites writes = FakeTrackerWrites()
          ..respond = (_) => refusal.future;
        final StreamController<ViceActivity?> activity = await pumpEditor(
          tester,
          writes: writes,
        );

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Quantity'),
          '7',
        );
        await tester.tap(find.text('Save'));
        await tester.pump();
        activity.add(changed(7, stored.createdAt.toDate(), pending: true));
        await tester.pump();

        Future<void> rollBack() async {
          activity.add(stored);
          await tester.pump();
        }

        if (rollbackFirst) {
          await rollBack();
        }
        refusal.completeError(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          ),
        );
        await tester.pump();
        await tester.pump();
        if (!rollbackFirst) {
          await rollBack();
        }

        expect(find.textContaining('Could not save'), findsOneWidget);
        expect(_fieldText(tester, 'Quantity'), '7');

        writes.respond = null;
        await tester.tap(find.text('Save'));
        await tester.pump();
        expect(writes.writes, <Write>[
          Write('updateActivity', stored.id, <String, Object?>{'quantity': 7}),
          Write('updateActivity', stored.id, <String, Object?>{'quantity': 7}),
        ]);
      });
    }

    testWidgets('keeps the stored time as the clock moves, and Now sets the '
        'current one', (WidgetTester tester) async {
      final DateTime now = DateTime(2026, 11, 2, 12, 7, 30);
      await withClock(Clock.fixed(now), () async {
        await pumpEditor(tester);
        await tester.pump(const Duration(seconds: 3));
        expect(_time(tester).at, stored.createdAt.toDate());
        expect(find.text('2 h 37 min ago'), findsOneWidget);

        await tester.tap(find.text(EntryTimeField.nowLabel));
        await tester.pump();
        expect(_time(tester).followsClock, isTrue);
        expect(_time(tester).value, now);
      });
    });
  });

  testWidgets('the record sheet follows the clock until the dial is moved', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime(2026, 11, 2, 12, 7, 30);
    await withClock(Clock.fixed(now), () async {
      await _pump(tester, [
        unarchivedViceListProvider.overrideWithValue(AsyncData([coffee])),
      ], const Scaffold(body: RecordNewActivityDialog()));

      expect(_time(tester).followsClock, isTrue);
      expect(
        find.text('${EntryTimeField.nowLabel} · ${EntryTimeField.dragHint}'),
        findsOneWidget,
      );

      // The 06 numeral sits at the dial's right.
      final Rect dial = tester.getRect(find.byType(TimeDial));
      await tester.tapAt(dial.centerRight - const Offset(30, 0));
      await tester.pump();
      expect(_time(tester).at, DateTime(2026, 11, 2, 6));
      expect(find.text('6 h 7 min ago'), findsOneWidget);
    });
  });
}
