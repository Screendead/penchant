import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/trends/trends_chart.dart';
import 'package:tracker/trends/trends_sheet.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/day_dial.dart';
import 'package:tracker/widgets/day_picker.dart';
import 'package:tracker/widgets/log_fan.dart';
import 'package:tracker/widgets/tally_row.dart';

import 'mac_window_harness.dart';

Finder _inTrends(Finder f) =>
    find.descendant(of: find.byType(TrendsSheet), matching: f);

Rect _rect(WidgetTester tester, Finder f) => tester.getRect(f);

ScrollPosition _trendsScroll(WidgetTester tester) => tester
    .state<ScrollableState>(_inTrends(find.byType(Scrollable)).first)
    .position;

Future<void> _expectCommonLayout(
  WidgetTester tester, {
  required bool chipsWrap,
}) async {
  expect(tester.takeException(), isNull);

  // Synced sits on the Trends title row, not over Today.
  expect(_inTrends(find.byType(SyncPill)), findsOneWidget);
  expect(find.byType(SyncPill), findsOneWidget);
  expect(
    _rect(tester, find.byType(SyncPill)).center.dy,
    moreOrLessEquals(
      _rect(tester, _inTrends(find.text(TrendsSheet.title))).center.dy,
      epsilon: 1,
    ),
  );

  // The chips stay in the pane, wrapping onto more rows when they must.
  final Rect pane = _rect(tester, find.byType(TrendsSheet));
  final List<Rect> chips = <Rect>[
    for (final String name in macHabits.map((h) => h.name))
      _rect(tester, _inTrends(find.text(name)).first),
  ];
  if (chipsWrap) {
    expect(chips.map((Rect r) => r.top.round()).toSet().length, greaterThan(1));
  }
  for (final Rect chip in chips) {
    expect(chip.right, lessThanOrEqualTo(pane.right));
  }

  // The Log button docks under the last tally, once Today's list is at
  // its end.
  final ScrollPosition today = tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(ViceTracker),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;
  today.jumpTo(today.maxScrollExtent);
  await tester.pump();
  final Rect lastTally = find
      .byType(TallyRow)
      .evaluate()
      .map((Element e) => tester.getRect(find.byWidget(e.widget)))
      .reduce((Rect a, Rect b) => a.bottom > b.bottom ? a : b);
  final Rect log = _rect(tester, find.byType(LogButton));
  expect(log.top, greaterThan(lastTally.bottom));
  expect(log.top - lastTally.bottom, lessThan(DialSpace.l + 1));
  expect(find.byType(LogButton).hitTestable(), findsOneWidget);
}

void main() {
  testWidgets('the 1200x780 default window keeps Today at 504 pt', (
    WidgetTester tester,
  ) async {
    await pumpMacWindow(tester, const Size(1200, 780));

    expect(_rect(tester, find.byType(TrendsSheet)).left, 504);
    expect(ViceTracker.splitColumnWidth(1200), 504);
    expect(
      _rect(tester, find.byType(DayDial)).width,
      inInclusiveRange(DialSize.dialDiameter, DialSize.dialDiameter + 8),
    );
    // Too short for more: the chart keeps its own height and the pane scrolls.
    expect(
      _rect(tester, _inTrends(find.byType(LineChart))).height,
      TrendsChart.plotHeight,
    );
    expect(_trendsScroll(tester).maxScrollExtent, greaterThan(0));
    await _expectCommonLayout(tester, chipsWrap: true);
  });

  testWidgets('a 2000x1250 fullscreen window grows the dial, Today and the '
      'chart', (WidgetTester tester) async {
    await pumpMacWindow(tester, const Size(2000, 1250));

    expect(
      _rect(tester, find.byType(TrendsSheet)).left,
      ViceTracker.splitColumnMax,
    );
    expect(_rect(tester, find.byType(DayDial)).width, ViceTracker.splitDialMax);
    // The chart takes the height the rest of the pane leaves, so the pane
    // fills the window without scrolling.
    final double plot = _rect(tester, _inTrends(find.byType(LineChart))).height;
    expect(plot, greaterThan(TrendsChart.plotHeight));
    expect(plot, lessThanOrEqualTo(TrendsSheet.paneChartMax));
    expect(_trendsScroll(tester).maxScrollExtent, 0);
    final Rect pane = _rect(tester, find.byType(TrendsSheet));
    final Rect hint = _rect(
      tester,
      _inTrends(find.text(TrendsSheet.hint(1, pane: true))),
    );
    expect(
      pane.bottom - hint.bottom,
      moreOrLessEquals(DialSpace.xl, epsilon: 1),
    );
    await _expectCommonLayout(tester, chipsWrap: false);
  });

  testWidgets('while the habits load, Today stays at the top of its column', (
    WidgetTester tester,
  ) async {
    await pumpMacWindow(
      tester,
      const Size(1200, 780),
      vices: const AsyncLoading<List<Vice>>(),
    );
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.byType(LogButton), findsNothing);
    // The list's 6 pt top padding, as when the habits are there.
    expect(
      _rect(tester, find.byType(DayPicker)).top,
      _rect(tester, find.byType(ViceTracker)).top + 6,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wide window whose habits failed to load shows Synced in the '
      'header', (WidgetTester tester) async {
    await pumpMacWindow(
      tester,
      const Size(1200, 780),
      vices: AsyncError<List<Vice>>(StateError('offline'), StackTrace.empty),
    );
    expect(find.byType(TrendsSheet), findsNothing);
    expect(
      find.descendant(
        of: find.byType(TodayHeader),
        matching: find.byType(SyncPill),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a taller window stops the chart at its largest', (
    WidgetTester tester,
  ) async {
    await pumpMacWindow(tester, const Size(2000, 2400));

    expect(
      _rect(tester, _inTrends(find.byType(LineChart))).height,
      TrendsSheet.paneChartMax,
    );
    expect(_trendsScroll(tester).maxScrollExtent, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text keeps the chart at its own height and scrolls', (
    WidgetTester tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpMacWindow(tester, const Size(1200, 780));

    expect(
      _rect(tester, _inTrends(find.byType(LineChart))).height,
      TrendsChart.plotHeight,
    );
    expect(_trendsScroll(tester).maxScrollExtent, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
