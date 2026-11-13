import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/main.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/trends/trends_chart.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/day_dial.dart';
import 'package:tracker/widgets/log_fan.dart';
import 'package:tracker/widgets/tally_row.dart';
import 'package:tracker/writes/log_one.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';

import 'fake_writes.dart';
import 'fakes.dart';
import 'trends_harness.dart';

final DateTime _today = startOfDay(DateTime.now());

Future<void> _pump(
  WidgetTester tester,
  List<Override> overrides,
  Widget home,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: Scaffold(body: home)),
    ),
  );
  await tester.pumpAndSettle();
}

// An iPhone SE-sized screen, the smallest the app runs on.
void _usePhone(WidgetTester tester, {double textScale = 1}) {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = const Size(375 * 2, 667 * 2);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

List<Override> _day(List<Vice> vices, List<int> quantities) => [
  ...habitOverrides(vices),
  viceActivityDayProvider.overrideWith(
    (ref, DateTime day) => AsyncData([
      for (int i = 0; i < vices.length; i++)
        if (quantities[i] > 0)
          fakeActivity(
            vices[i].id,
            quantities[i],
            day.add(Duration(hours: 8 + i)),
          ),
    ]),
  ),
];

final List<Vice> _three = [
  fakeVice('coffee'),
  fakeVice('beer'),
  fakeVice('tea'),
];

final List<Vice> _longNamed = [
  fakeVice('elderflower', name: 'Sparkling elderflower water'),
  fakeVice('coffee'),
  fakeVice('tea'),
];

// Scrolls [finder] to the middle of the screen, clear of the Log button.
Future<void> _centre(WidgetTester tester, Finder finder) async {
  // Today's list builds its rows only as they near the screen.
  for (int i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView).first, const Offset(0, -150));
    await tester.pump();
  }
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
}

void main() {
  group('screen readers', () {
    testWidgets('hear the dial as the day, each total and when', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await _pump(tester, _day(_three, [2, 0, 1]), const ViceTracker());

      final String summary = tester
          .widget<DayDial>(find.byType(DayDial))
          .semanticsLabel!;
      expect(
        summary,
        startsWith(
          'Today, ${dayPillDate(_today, _today)}. beer 0 items, '
          'coffee 2 items, tea 1 item. First entry ',
        ),
      );
      expect(find.bySemanticsLabel(summary), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('hear each tally once, and a + named for what it logs', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await _pump(tester, _day(_three, [2, 0, 1]), const ViceTracker());

      expect(find.bySemanticsLabel('coffee, 2 items'), findsOneWidget);
      expect(find.bySemanticsLabel('beer, 0 items'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^2\$')), findsNothing);
      // The last row can sit below the fold, above the Trends peek.
      for (final Vice vice in _three) {
        expect(
          find.byTooltip(logOneLabel(vice), skipOffstage: false),
          findsOneWidget,
        );
      }
      expect(find.bySemanticsLabel(LogButton.label), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('every tap target on Today is at least 44 points', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      _usePhone(tester);
      await _pump(tester, _day(_three, [2, 0, 1]), const ViceTracker());

      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      semantics.dispose();
    });

    testWidgets('hear the graph as its range, total and peak', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      final DateTime peakDay = addDays(_today, -3);
      await _pump(
        tester,
        trendsOverrides(
          [_three.first],
          inRange(<ViceActivity>[
            fakeActivity('coffee', 4, peakDay.add(const Duration(hours: 9))),
            fakeActivity('coffee', 1, _today.add(const Duration(hours: 9))),
          ]),
        ),
        const ViceTracker(),
      );
      await openTrends(tester);

      expect(
        find.bySemanticsLabel(
          'Daily totals of coffee over the last 30 days: 5 items in all. '
          'The most was 4 items on ${formatShortDay(peakDay)}. '
          'Shown with a 7-day average.',
        ),
        findsOneWidget,
      );
      expect(find.text('Average over 7 days'), findsOneWidget);
      semantics.dispose();
    });
  });

  test('the graph says which series is which in words', () {
    expect(TrendsChart.seriesName(1), 'Daily total');
    expect(TrendsChart.averageName(1, 3), '3-day average');
    expect(TrendsChart.averageName(7, 2), '2-week average');
  });

  for (final double textScale in [2.0, 3.0]) {
    group('at text scale $textScale', () {
      testWidgets('the record dialog scrolls and still records', (
        WidgetTester tester,
      ) async {
        _usePhone(tester, textScale: textScale);
        final FakeTrackerWrites writes = FakeTrackerWrites();
        await _pump(tester, [
          userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
          unarchivedViceListProvider.overrideWith((ref) => AsyncData(_three)),
          trackerWritesProvider.overrideWithValue(writes),
          memoryJournal(),
        ], const RecordNewActivityDialog());

        expect(tester.takeException(), isNull);

        Future<void> submit() async {
          // A focused field scrolls itself back into view on each frame.
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(RecordNewActivityDialog.submitKey),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(RecordNewActivityDialog.submitKey),
          );
          await tester.pump();
          await tester.tap(find.byKey(RecordNewActivityDialog.submitKey));
          await tester.pumpAndSettle();
        }

        final Finder quantity = find.widgetWithText(TextFormField, 'Quantity');
        await tester.ensureVisible(quantity);
        await tester.pumpAndSettle();
        await tester.enterText(quantity, '0');
        await submit();

        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Please select a habit'));
        expect(find.text('Please select a habit'), findsOneWidget);
        expect(find.text('Please enter more than 0'), findsOneWidget);
        expect(writes.writes, isEmpty);

        await tester.ensureVisible(find.text('Select Habit'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select Habit'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('beer').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(quantity);
        await tester.pumpAndSettle();
        await tester.enterText(quantity, '2');
        await submit();

        expect(tester.takeException(), isNull);
        expect(writes.writes, hasLength(1));
        expect(writes.writes.single.op, 'recordActivity');
        expect(writes.writes.single.fields['viceID'], 'beer');
        expect(writes.writes.single.fields['quantity'], 2);
      });

      testWidgets('the home screen opens the record dialog without '
          'overflowing', (WidgetTester tester) async {
        _usePhone(tester, textScale: textScale);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ..._day(_three, [2, 0, 1]),
              userProvider.overrideWith(
                (ref) => Stream.value(FakeUser(ownerID)),
              ),
              viceActivityGraphProvider.overrideWith(
                (ref, ViceActivityGraphQuery query) => AsyncData(<ViceActivity>[
                  fakeActivity('coffee', 2, _today),
                ]),
              ),
            ],
            child: const MaterialApp(home: Homepage()),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.tap(find.byType(LogButton));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.longPress(
          find.descendant(
            of: find.byKey(const ValueKey<String>('fan-wedge-coffee')),
            matching: find.text('coffee'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(RecordNewActivityDialog), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        await openTrends(tester);
        expect(find.byType(LineChart), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Today shows every habit name whole', (
        WidgetTester tester,
      ) async {
        _usePhone(tester, textScale: textScale);
        await _pump(tester, _day(_longNamed, [4, 0, 0]), const ViceTracker());
        expect(tester.takeException(), isNull);

        // Top to bottom: equal creation times list by id.
        final List<Vice> shown = [..._longNamed]
          ..sort((Vice a, Vice b) => a.id.compareTo(b.id));
        for (final Vice vice in shown) {
          final Finder name = find.descendant(
            of: find.byType(TallyRow, skipOffstage: false),
            matching: find.text(vice.name, skipOffstage: false),
            skipOffstage: false,
          );
          await _centre(tester, name);
          final Text text = tester.widget<Text>(name);
          expect(text.maxLines, isNull, reason: vice.name);
          expect(text.overflow, isNot(TextOverflow.ellipsis));
          expect(
            find.text(vice.name).hitTestable(),
            findsOneWidget,
            reason: vice.name,
          );
        }
      });

      testWidgets('Today lays out without overflowing', (
        WidgetTester tester,
      ) async {
        _usePhone(tester, textScale: textScale);
        await _pump(tester, _day(_three, [2, 0, 1]), const ViceTracker());
        expect(tester.takeException(), isNull);

        for (int i = 0; i < 8; i++) {
          await tester.tap(find.byTooltip('Previous day'));
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byType(LogButton));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      // The record dialog's keyboard shrinks the home screen behind it.
      testWidgets('a clear day fits above the keyboard', (
        WidgetTester tester,
      ) async {
        _usePhone(tester, textScale: textScale);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 2);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ..._day(_three, [0, 0, 0]),
              userProvider.overrideWith(
                (ref) => Stream.value(FakeUser(ownerID)),
              ),
              viceActivityGraphProvider.overrideWith(
                (ref, ViceActivityGraphQuery query) =>
                    AsyncData(<ViceActivity>[]),
              ),
            ],
            child: const MaterialApp(home: Homepage()),
          ),
        );
        await tester.pumpAndSettle();

        // Today scrolls, so the dial can be reached above the keyboard.
        await _centre(tester, find.text(ClearDay.headline));
        expect(find.text(ClearDay.headline).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the graph reserves room for its scaled axis labels', (
        WidgetTester tester,
      ) async {
        _usePhone(tester, textScale: textScale);
        await _pump(
          tester,
          trendsOverrides(
            [_three.first],
            (ViceActivityGraphQuery query) =>
                AsyncData(<ViceActivity>[fakeActivity('coffee', 1200, _today)]),
          ),
          const ViceTracker(),
        );
        await openTrends(tester);
        expect(tester.takeException(), isNull);

        final FlTitlesData titles = tester
            .widget<LineChart>(find.byType(LineChart))
            .data
            .titlesData;
        final double scaledLabel = 10 * textScale;
        expect(
          titles.bottomTitles.sideTitles.reservedSize,
          greaterThan(scaledLabel + 8),
        );
        // "1380" at the scaled size, about 0.6 em per digit.
        expect(
          titles.leftTitles.sideTitles.reservedSize,
          greaterThan(4 * 0.5 * scaledLabel),
        );
      });
    });
  }

  group('the sign-in screen', () {
    List<Override> signedOut() => [
      userProvider.overrideWith((ref) => Stream.value(null)),
    ];

    testWidgets('names the password visibility toggle', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(overrides: signedOut(), child: const MyApp()),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Show password'), findsOneWidget);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(find.byTooltip('Hide password'), findsOneWidget);
    });

    testWidgets('the app-wide tap handler unfocuses whatever has focus now, '
        'and adds no unlabelled action', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(overrides: signedOut(), child: const MyApp()),
      );
      await tester.pumpAndSettle();

      final Finder email = find.byType(EditableText).first;
      await tester.tap(email);
      await tester.pump();
      expect(tester.widget<EditableText>(email).focusNode.hasFocus, isTrue);

      final GestureDetector root = tester.widget<GestureDetector>(
        find
            .ancestor(
              of: find.byType(MaterialApp),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      expect(root.excludeFromSemantics, isTrue);
      root.onTap!();
      await tester.pump();
      expect(tester.widget<EditableText>(email).focusNode.hasFocus, isFalse);
    });
  });
}
