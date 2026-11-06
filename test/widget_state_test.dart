import 'dart:async';

import 'package:clock/clock.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
import 'package:tracker/usage_graph_view.dart';
import 'package:tracker/vice_activity_editor_page.dart';
import 'package:tracker/vice_activity_history_page.dart';
import 'package:tracker/widgets/day_dial.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/activity_date_field.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';

import 'fake_account.dart';
import 'fake_writes.dart';
import 'fakes.dart';

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
          viceListProvider.overrideWithValue(AsyncData([coffee])),
          viceActivityGraphProvider.overrideWith((
            ref,
            ViceActivityGraphQuery query,
          ) {
            queries.add(query);
            return AsyncData(<ViceActivity>[
              fakeActivity(coffee.id, 5, day.copyWith(hour: 23, minute: 30)),
              fakeActivity(coffee.id, 3, next.copyWith(minute: 30)),
            ]);
          }),
        ], const Scaffold(body: UsageGraphView()));
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
    testWidgets('is graphable, listed last and marked, and not the default', (
      WidgetTester tester,
    ) async {
      final List<String> graphed = <String>[];
      await _pump(tester, [
        viceListProvider.overrideWithValue(AsyncData([tea, coffee])),
        viceActivityGraphProvider.overrideWith((
          ref,
          ViceActivityGraphQuery query,
        ) {
          graphed.add(query.viceID);
          return AsyncData(<ViceActivity>[]);
        }),
      ], const Scaffold(body: UsageGraphView()));

      expect(graphed.last, coffee.id);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      final List<String> items = tester
          .widgetList<DropdownMenuItem<String>>(
            find.byType(DropdownMenuItem<String>),
          )
          .map((DropdownMenuItem<String> item) => (item.child as Text).data!)
          .toList();
      expect(items.toSet().toList(), <String>['coffee', 'tea (archived)']);

      await tester.tap(find.text('tea (archived)').last);
      await tester.pumpAndSettle();
      expect(graphed.last, tea.id);
    });

    testWidgets('still opens its history from Manage Data', (
      WidgetTester tester,
    ) async {
      await _pump(tester, [
        viceListProvider.overrideWithValue(AsyncData([coffee, tea])),
        viceActivityCountProvider.overrideWith(
          (ref, String viceID) =>
              const AsyncData((count: 2, source: CountSource.server)),
        ),
        viceActivityHistoryProvider.overrideWith(
          (ref, ViceActivityHistoryQuery query) => AsyncData(<ViceActivity>[]),
        ),
      ], const ManageData());

      expect(find.text('${ManageData.archivedLabel}, 2 activities'), findsOne);
      expect(find.text('2 activities'), findsOne);

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

  group('the home tabs', () {
    testWidgets('only the visible tab is built, and each keeps its '
        'selection across a switch', (WidgetTester tester) async {
      final Vice beer = fakeVice('beer');
      final List<String> graphed = <String>[];
      await _pump(tester, [
        viceListProvider.overrideWithValue(AsyncData([coffee, beer])),
        unarchivedViceListProvider.overrideWithValue(
          AsyncData([coffee, beer, fakeVice('wine')]),
        ),
        viceActivityDayProvider.overrideWith(
          (ref, DateTime day) => AsyncData(<ViceActivity>[]),
        ),
        viceActivityGraphProvider.overrideWith((
          ref,
          ViceActivityGraphQuery query,
        ) {
          graphed.add(query.viceID);
          return AsyncData(<ViceActivity>[]);
        }),
      ], const Homepage());

      expect(find.byType(UsageGraphView, skipOffstage: false), findsNothing);
      expect(graphed, isEmpty);

      await tester.tap(find.byTooltip('Previous day'));
      await tester.pump();
      expect(find.text('Yesterday'), findsOneWidget);

      await tester.tap(find.text('Graph'));
      await tester.pumpAndSettle();
      expect(find.byType(ViceTracker, skipOffstage: false), findsNothing);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('beer').last);
      await tester.pumpAndSettle();
      expect(graphed.last, beer.id);

      await tester.tap(find.byIcon(Icons.today_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Yesterday'), findsOneWidget);

      await tester.tap(find.text('Graph'));
      await tester.pumpAndSettle();
      expect(graphed.last, beer.id);
      expect(find.text('Smoothing: 1 bucket for beer'), findsOneWidget);
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
      expect(
        _fieldText(tester, ActivityDateField.label),
        ActivityDateField.format.format(moved),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Quantity'),
        '7',
      );
      activity.add(changed(4, DateTime(2026, 11, 2, 11)));
      await tester.pump();
      await tester.pump();

      expect(_fieldText(tester, 'Quantity'), '7');
      expect(
        _fieldText(tester, ActivityDateField.label),
        ActivityDateField.format.format(DateTime(2026, 11, 2, 11)),
      );
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

    testWidgets('leaves the date alone until asked for the current time, and '
        'returns to the stored one', (WidgetTester tester) async {
      await pumpEditor(tester);
      final String storedText = ActivityDateField.format.format(
        stored.createdAt.toDate(),
      );
      await tester.pump(const Duration(seconds: 3));
      expect(_fieldText(tester, ActivityDateField.label), storedText);

      await tester.tap(find.byTooltip('Use current date and time'));
      await tester.pump();
      expect(_fieldText(tester, ActivityDateField.label), isNot(storedText));

      await tester.tap(find.byTooltip('Manually enter date and time'));
      await tester.pump();
      expect(_fieldText(tester, ActivityDateField.label), storedText);
    });
  });

  testWidgets('the record dialog keeps its clock on the current time until '
      'unlocked', (WidgetTester tester) async {
    await _pump(tester, [
      unarchivedViceListProvider.overrideWithValue(AsyncData([coffee])),
    ], const Scaffold(body: RecordNewActivityDialog()));

    DateTime shown() => ActivityDateField.format.parse(
      _fieldText(tester, ActivityDateField.label),
    );
    expect(clock.now().difference(shown()).inSeconds, lessThan(2));

    final DateTime before = shown();
    await tester.pump(const Duration(seconds: 3));
    expect(shown().difference(before).inSeconds, 3);

    await tester.tap(find.byTooltip('Manually enter date and time'));
    await tester.pump();
    final String frozen = _fieldText(tester, ActivityDateField.label);
    await tester.pump(const Duration(seconds: 3));
    expect(_fieldText(tester, ActivityDateField.label), frozen);
  });
}
