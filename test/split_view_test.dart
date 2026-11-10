import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/usage_series.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/main.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/trends/trends_chart.dart';
import 'package:tracker/trends/trends_day.dart';
import 'package:tracker/trends/trends_sheet.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/day_dial.dart';
import 'package:tracker/widgets/log_fan.dart';
import 'package:tracker/widgets/pill_toggle.dart';

import 'fake_writes.dart';
import 'fakes.dart';
import 'trends_harness.dart';

final DateTime _today = startOfDay(DateTime.now());

Vice _habit(String name, int order) => Vice(
  id: name.toLowerCase(),
  name: name,
  unit: Unit.drink,
  ownerID: ownerID,
  createdAt: Timestamp.fromDate(DateTime.utc(2026, 1, order)),
  archived: false,
);

final Vice _coffee = _habit('Coffee', 1);
final Vice _sweets = _habit('Sweets', 2);

final List<ViceActivity> _entries = <ViceActivity>[
  for (int d = 0; d < 30; d++)
    fakeActivity(
      d.isEven ? _coffee.id : _sweets.id,
      1 + d % 3,
      addDays(_today, -d).add(const Duration(hours: 9)),
    ),
];

void _useWindow(WidgetTester tester, double width, {double textScale = 1}) {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = Size(width * 2, 800 * 2);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _resize(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width * 2, 800 * 2);
  await tester.pumpAndSettle();
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
        offlineProvider.overrideWithValue(const AsyncData(false)),
        trackerWritesProvider.overrideWithValue(FakeTrackerWrites()),
        ...trendsOverrides(
          <Vice>[_sweets, _coffee],
          inRange(_entries),
          days: (DateTime day) => <ViceActivity>[
            for (final ViceActivity a in _entries)
              if (startOfDay(a.createdAt.toDate()) == day) a,
          ],
        ),
      ],
      child: MaterialApp(
        theme: appTheme(Brightness.light),
        home: const Homepage(),
        onGenerateRoute: generateRoute,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

DateTime _todaysDay(WidgetTester tester) => tester
    .widget<DayDial>(
      find.descendant(
        of: find.byType(ViceTracker),
        matching: find.byType(DayDial),
      ),
    )
    .day;

bool _chipSelected(WidgetTester tester, String name) => tester
    .widget<PillToggle>(
      find.byWidgetPredicate(
        (Widget w) => w is PillToggle && w.semanticsLabel == name,
      ),
    )
    .selected;

Rect _rectOf(WidgetTester tester, Finder finder) => tester.getRect(finder);

void main() {
  testWidgets('below 900 pt Today is the phone layout, with Trends as a '
      'sheet', (WidgetTester tester) async {
    _useWindow(tester, 899);
    await _pump(tester);

    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
    await openTrends(tester);
    expect(find.byTooltip(TrendsSheet.closeLabel), findsOneWidget);
    expect(find.text(TrendsSheet.hint(1)), findsOneWidget);
  });

  for (final double width in <double>[900, 1200, 1600]) {
    testWidgets('at $width pt Trends is a pane right of the dial and '
        'tallies, open without a tap', (WidgetTester tester) async {
      _useWindow(tester, width);
      await _pump(tester);

      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(find.byTooltip(TrendsSheet.closeLabel), findsNothing);
      expect(find.byType(LineChart).hitTestable(), findsOneWidget);
      // A tapped day shows on Today's dial, not in the pane.
      expect(find.text(TrendsSheet.hint(1, pane: true)), findsOneWidget);
      expect(find.text(TrendsSheet.hint(1)), findsNothing);

      final Rect pane = _rectOf(tester, find.byType(TrendsSheet));
      final Rect dial = _rectOf(tester, find.byType(DayDial));
      final Rect log = _rectOf(tester, find.byType(LogButton));
      final Rect tally = _rectOf(tester, find.text('Sweets').first);
      expect(pane.right, width);
      expect(pane.left, ViceTracker.splitColumnWidth(width));
      expect(dial.right, lessThanOrEqualTo(pane.left));
      expect(tally.right, lessThanOrEqualTo(pane.left));
      expect(log.right, lessThanOrEqualTo(pane.left));
      expect(log.center.dx, closeTo(pane.left / 2, 1));
      expect(find.byType(LogButton).hitTestable(), findsOneWidget);
      // The chart keeps to a readable width on a wide window.
      expect(
        _rectOf(tester, find.byType(TrendsChart)).width,
        lessThanOrEqualTo(TrendsSheet.paneContentWidth),
      );
    });
  }

  testWidgets('at 900 pt with large text nothing overflows', (
    WidgetTester tester,
  ) async {
    _useWindow(tester, 900, textScale: 2);
    await _pump(tester);
    expect(find.byType(TrendsChart), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Pro Max iPhone on its side, the shortest split, lays out '
      'both panes without overflow', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(956 * 3, 440 * 3);
    tester.view.padding = const FakeViewPadding(
      left: 62 * 3,
      right: 62 * 3,
      bottom: 21 * 3,
    );
    addTearDown(tester.view.reset);
    await _pump(tester);

    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(find.byType(DayDial), findsOneWidget);
    expect(find.byType(TrendsChart), findsOneWidget);
    expect(find.byType(LogButton).hitTestable(), findsOneWidget);
    // Clear of the notch on the left and the camera on the right.
    expect(tester.getRect(find.text('Sweets').first).left, greaterThan(62));
    expect(
      tester.getRect(find.byType(TrendsChart)).right,
      lessThanOrEqualTo(956 - 62),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('resizing across 900 pt keeps the day and the habit', (
    WidgetTester tester,
  ) async {
    _useWindow(tester, 1200);
    await _pump(tester);

    await tester.tap(inTrends(find.text('Sweets')));
    await tester.pumpAndSettle();
    // Two presses within one frame each count.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(_todaysDay(tester), addDays(_today, -2));
    expect(_chipSelected(tester, 'Sweets'), isTrue);

    await _resize(tester, 800);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(_todaysDay(tester), addDays(_today, -2));
    await openTrends(tester);
    expect(_chipSelected(tester, 'Sweets'), isTrue);

    await _resize(tester, 1600);
    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(_todaysDay(tester), addDays(_today, -2));
    expect(_chipSelected(tester, 'Sweets'), isTrue);
  });

  testWidgets('the pane compares habits, and a resize across 900 pt keeps '
      'the comparison', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    _useWindow(tester, 1200);
    await _pump(tester);
    int bars() => tester
        .widget<LineChart>(inTrends(find.byType(LineChart)))
        .data
        .lineBarsData
        .length;

    await tester.tap(inTrends(find.text(TrendsSheet.compareLabel)));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (Widget w) =>
            w is PillToggle &&
            w.semanticsLabel == TrendsSheet.compareChipLabel(_sweets),
      ),
    );
    await tester.pumpAndSettle();
    expect(bars(), 3);
    expect(
      tester.getSemantics(find.byType(TrendsChart)).label,
      contains('Compared with Sweets'),
    );

    await _resize(tester, 800);
    await openTrends(tester);
    expect(_chipSelected(tester, TrendsSheet.compareChipLabel(_sweets)), isTrue);
    expect(bars(), 3);
    semantics.dispose();
  });

  testWidgets('an open sheet resized into the split view and back is at its '
      'peek, with the Log button and the arrow keys working', (
    WidgetTester tester,
  ) async {
    _useWindow(tester, 800);
    await _pump(tester);
    await openTrends(tester);

    await _resize(tester, 1200);
    await _resize(tester, 800);
    final DraggableScrollableSheet sheet = tester
        .widget<DraggableScrollableSheet>(
          find.byType(DraggableScrollableSheet),
        );
    // The Log button rides the sheet's top edge.
    final Rect today = _rectOf(tester, find.byType(ViceTracker));
    expect(
      tester.getCenter(find.byType(LogButton)).dy,
      moreOrLessEquals(
        today.top + today.height * (1 - sheet.minChildSize),
        epsilon: 1,
      ),
    );
    expect(find.byType(LogButton).hitTestable(), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(_todaysDay(tester), addDays(_today, -1));
  });

  testWidgets('Left and Right step through days on Today, never past today', (
    WidgetTester tester,
  ) async {
    _useWindow(tester, 1200);
    await _pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_todaysDay(tester), _today);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(_todaysDay(tester), addDays(_today, -1));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_todaysDay(tester), _today);
  });

  testWidgets("with the chart focused the arrows move its cursor, not "
      "Today's day, and Enter shows the day on Today's dial", (
    WidgetTester tester,
  ) async {
    _useWindow(tester, 1200);
    await _pump(tester);
    FocusNode? focused() => FocusManager.instance.primaryFocus;
    bool onChart() => focused()?.debugLabel == TrendsChart.focusLabel;
    for (int i = 0; i < 40 && !onChart(); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(onChart(), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(_todaysDay(tester), _today);
    final String twoAgo = TrendsChart.readoutLabel(
      usageRange(_today, 30, 1),
      27,
      _today,
    );
    expect(find.textContaining(twoAgo), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_todaysDay(tester), addDays(_today, -2));
    expect(find.byType(TrendsDay), findsNothing);
    expect(onChart(), isTrue);
  });

  testWidgets("a tapped day point moves Today's dial to that day", (
    WidgetTester tester,
  ) async {
    _useWindow(tester, 1600);
    await _pump(tester);

    final Rect chart = _rectOf(tester, find.byType(LineChart));
    await tester.tapAt(Offset(chart.left + 40, chart.center.dy));
    await tester.pumpAndSettle();
    expect(daysBetween(_todaysDay(tester), _today), greaterThan(20));
    expect(find.byType(TrendsDay), findsNothing);
    expect(find.byType(LineChart), findsOneWidget);
  });

  testWidgets('a screen reader hears where a day activated on the chart '
      'went', (WidgetTester tester) async {
    _useWindow(tester, 1200);
    final SemanticsHandle semantics = tester.ensureSemantics();
    final List<Map<Object?, Object?>> announced = <Map<Object?, Object?>>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
      SystemChannels.accessibility,
      (Object? message) async {
        final Map<Object?, Object?> event = message! as Map<Object?, Object?>;
        if (event['type'] == 'announce') {
          announced.add(event['data']! as Map<Object?, Object?>);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(
            SystemChannels.accessibility,
            null,
          ),
    );
    await _pump(tester);

    Future<void> act(SemanticsAction action) async {
      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          type: action,
          viewId: tester.view.viewId,
          nodeId: tester.getSemantics(find.byType(TrendsChart)).id,
        ),
      );
      await tester.pumpAndSettle();
    }

    await act(SemanticsAction.decrease);
    await act(SemanticsAction.decrease);
    await act(SemanticsAction.tap);

    final DateTime twoAgo = addDays(_today, -2);
    expect(_todaysDay(tester), twoAgo);
    expect(announced.map((Map<Object?, Object?> e) => e['message']), <String>[
      TrendsSheet.shownOnDial(twoAgo),
    ]);
    semantics.dispose();
  });
}
