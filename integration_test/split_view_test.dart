import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/main.dart';
import 'package:tracker/trends/trends_sheet.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/day_dial.dart';
import 'package:tracker/widgets/log_fan.dart';
import 'package:tracker/widgets/pill_toggle.dart';

import 'support.dart';

// The window is laid out at each width in turn, whatever the device's own
// size, as a Mac window resized by hand would be.
Future<void> _resize(WidgetTester tester, double width) async {
  final double ratio = tester.view.devicePixelRatio;
  tester.view.physicalSize = Size(width * ratio, 760 * ratio);
  await pumpFor(tester, const Duration(milliseconds: 600));
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

List<double> _totals(WidgetTester tester) => tester
    .widget<LineChart>(find.byType(LineChart))
    .data
    .lineBarsData
    .first
    .spots
    .map((FlSpot spot) => spot.y)
    .toList();

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('from 900 pt Trends is a pane beside Today, and resizing '
      'across 900 pt keeps the day and the habit', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, 'e2e-split@example.com');
    await addVicesThroughManageData(tester, const <String>['Coffee', 'Tea']);
    addTearDown(tester.view.reset);
    final DateTime today = startOfDay(DateTime.now());

    for (final double width in <double>[900, 1200, 1600]) {
      await _resize(tester, width);
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(find.byTooltip(TrendsSheet.closeLabel), findsNothing);
      await pumpUntil(tester, find.byType(LineChart).hitTestable());
      final Rect pane = tester.getRect(find.byType(TrendsSheet));
      expect(pane.left, ViceTracker.splitColumnWidth(width));
      expect(
        tester.getRect(find.byType(DayDial)).right,
        lessThanOrEqualTo(pane.left),
      );
      expect(
        tester.getRect(find.byType(LogButton)).right,
        lessThanOrEqualTo(pane.left),
      );
    }

    // A log on the left reaches the chart on the right.
    await _resize(tester, 1200);
    await logOne(tester, 'Coffee');
    await expectTallies(tester, const <String>{
      'Coffee (1 drink)',
      'Tea (0 drinks)',
    });
    await pumpUntilTrue(
      tester,
      () => _totals(tester).last == 1,
      () => "Trends to count today's Coffee",
    );

    await tap(
      tester,
      find.descendant(of: find.byType(TrendsSheet), matching: find.text('Tea')),
    );
    await pumpFor(tester, const Duration(milliseconds: 600));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(_todaysDay(tester), addDays(today, -1));
    expect(_chipSelected(tester, 'Tea'), isTrue);

    await _resize(tester, 800);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(_todaysDay(tester), addDays(today, -1));
    await openTrends(tester);
    expect(_chipSelected(tester, 'Tea'), isTrue);
    await closeTrends(tester);

    await _resize(tester, 1600);
    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(_todaysDay(tester), addDays(today, -1));
    expect(_chipSelected(tester, 'Tea'), isTrue);

    // Today's point on the chart brings Today's dial back to today.
    await scrollIntoView(tester, find.byType(LineChart));
    final Rect chart = tester.getRect(find.byType(LineChart));
    await tester.tapAt(Offset(chart.right - 2, chart.center.dy));
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(_todaysDay(tester), today);
  });
}
