import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:tracker/formats.dart';
import 'package:tracker/main.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
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

Vice _habit(String name, int order, {bool archived = false}) => Vice(
  id: name.toLowerCase(),
  name: name,
  unit: Unit.drink,
  ownerID: ownerID,
  createdAt: Timestamp.fromDate(DateTime.utc(2026, 1, order)),
  archived: archived,
);

final Vice _coffee = _habit('Coffee', 1);
final Vice _sweets = _habit('Sweets', 2);
final Vice _juice = _habit('Juice', 3, archived: true);

ViceActivity _daysAgo(int days, int quantity, {Vice? vice, int hour = 12}) =>
    fakeActivity(
      (vice ?? _coffee).id,
      quantity,
      addDays(_today, -days).add(Duration(hours: hour)),
    );

// An iPhone SE-sized screen, the smallest the app runs on.
void _usePhone(WidgetTester tester, {double textScale = 1}) {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = const Size(375 * 2, 667 * 2);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _pump(
  WidgetTester tester,
  List<ViceActivity> activities, {
  List<Vice>? vices,
  AsyncValue<List<ViceActivity>> Function(ViceActivityGraphQuery)? graph,
  List<ViceActivity> Function(DateTime day)? days,
  bool open = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
        offlineProvider.overrideWithValue(const AsyncData(false)),
        trackerWritesProvider.overrideWithValue(FakeTrackerWrites()),
        ...trendsOverrides(
          vices ?? <Vice>[_juice, _sweets, _coffee],
          graph ?? inRange(activities),
          days: days,
        ),
      ],
      child: MaterialApp(
        theme: appTheme(Brightness.light),
        home: const Scaffold(body: ViceTracker()),
        onGenerateRoute: generateRoute,
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (open) {
    await openTrends(tester);
  }
}

LineChartData _chart(WidgetTester tester) =>
    tester.widget<LineChart>(find.byType(LineChart)).data;

List<double> _totals(WidgetTester tester) =>
    _chart(tester).lineBarsData.first.spots.map((FlSpot s) => s.y).toList();

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.tap(inTrends(find.text(text)));
  await tester.pumpAndSettle();
}

List<Element> _axisLabels(WidgetTester tester, {required bool dates}) => find
    .descendant(of: find.byType(LineChart), matching: find.byType(Text))
    .evaluate()
    .where(
      (Element e) =>
          RegExp(r'[A-Za-z]').hasMatch((e.widget as Text).data!) == dates,
    )
    .toList();

String _label(Element e) => (e.widget as Text).data!;

Rect _rect(Element e) {
  final RenderBox box = e.renderObject! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

void _expectApart(List<Element> labels) {
  for (int i = 0; i < labels.length; i++) {
    for (int j = i + 1; j < labels.length; j++) {
      expect(
        _rect(labels[i]).overlaps(_rect(labels[j])),
        isFalse,
        reason: '"${_label(labels[i])}" and "${_label(labels[j])}" overlap',
      );
    }
  }
}

double _opacityOf(WidgetTester tester, Finder finder) => tester
    .widget<Opacity>(
      find.ancestor(of: finder, matching: find.byType(Opacity)).first,
    )
    .opacity;

void main() {
  group('the sheet', () {
    testWidgets('peeks with the first habit in use and its daily average, '
        'opens on a tap, and closes again', (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      _usePhone(tester);
      await _pump(tester, <ViceActivity>[
        _daysAgo(0, 3),
        _daysAgo(10, 6),
      ], open: false);

      expect(find.text('Coffee · last 30 days'), findsOneWidget);
      expect(find.text('0.3'), findsOneWidget);
      expect(find.text('drinks a day'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Trends. Coffee, last 30 days: 0.3 drinks a day'),
        findsOneWidget,
      );
      // The chart is built only once the sheet leaves its peek.
      expect(find.byType(LineChart), findsNothing);
      expect(_opacityOf(tester, find.byType(LogButton)), 1);

      await openTrends(tester);
      expect(find.byType(LineChart), findsOneWidget);
      expect(_opacityOf(tester, find.byType(LogButton)), 0);
      expect(
        find.bySemanticsLabel(RegExp('^Daily totals of Coffee')),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip(TrendsSheet.closeLabel));
      await tester.pumpAndSettle();
      expect(find.byType(LineChart), findsNothing);
      expect(_opacityOf(tester, find.byType(LogButton)), 1);
      semantics.dispose();
    });

    testWidgets('a new text size or window height moves the peek without '
        'an error, and Log stays on its edge', (WidgetTester tester) async {
      _usePhone(tester);
      await _pump(tester, <ViceActivity>[_daysAgo(0, 1)], open: false);

      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(375 * 2, 800 * 2);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getCenter(find.byType(LogButton)).dy,
        moreOrLessEquals(
          tester.getTopLeft(inTrends(find.byType(Material)).first).dy,
          epsilon: 1,
        ),
      );
    });

    testWidgets('a drag up opens it', (WidgetTester tester) async {
      _usePhone(tester);
      await _pump(tester, <ViceActivity>[_daysAgo(0, 1)], open: false);

      await tester.drag(
        inTrends(find.text(TrendsSheet.title)),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip(TrendsSheet.closeLabel), findsOneWidget);
      expect(find.byType(LineChart), findsOneWidget);
    });

    testWidgets('works from a keyboard: Enter on the peek opens it with focus '
        'on Close, Escape closes it back to the peek, and Today takes no '
        'focus meanwhile', (WidgetTester tester) async {
      _usePhone(tester);
      await _pump(tester, <ViceActivity>[_daysAgo(0, 1)], open: false);
      FocusNode? focused() => FocusManager.instance.primaryFocus;
      bool inPeek() => focused()?.debugLabel == 'Trends peek';

      for (int i = 0; i < 40 && !inPeek(); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(inPeek(), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(LineChart), findsOneWidget);
      expect(focused()?.debugLabel, TrendsSheet.closeLabel);

      // Tab stays among the sheet's controls and the Log button is gone.
      for (int i = 0; i < 30; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          find
              .ancestor(
                of: find.byElementPredicate(
                  (Element e) => identical(e, focused()!.context),
                ),
                matching: find.byType(TrendsSheet),
              )
              .evaluate(),
          isNotEmpty,
          reason: 'focus left the sheet at tab ${i + 1}',
        );
      }

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(LineChart), findsNothing);
      expect(focused()?.debugLabel, 'Trends peek');
    });
  });

  group('habit chips', () {
    testWidgets('list the habits in use oldest first, then archived ones, '
        'marked; the default is never archived', (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      _usePhone(tester);
      await _pump(tester, <ViceActivity>[
        _daysAgo(0, 2),
        _daysAgo(1, 4, vice: _juice),
      ]);

      final List<String> chips = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(PillToggle),
              matching: find.byType(Text),
            ),
          )
          .map((Text t) => t.data!)
          .take(4)
          .toList();
      expect(chips, <String>['Coffee', 'Sweets', 'Juice', ' · archived']);
      expect(find.bySemanticsLabel('Juice, archived'), findsOneWidget);
      expect(_totals(tester).last, 2);

      await tester.tap(inTrends(find.text('Juice')));
      await tester.pumpAndSettle();
      expect(_totals(tester)[28], 4);
      expect(
        find.bySemanticsLabel(RegExp('^Daily totals of Juice')),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('a single recorded day in 30', () {
    testWidgets('labels the y-axis once per value', (
      WidgetTester tester,
    ) async {
      _usePhone(tester);
      await _pump(tester, <ViceActivity>[_daysAgo(12, 1)]);

      final List<String> labels = _axisLabels(
        tester,
        dates: false,
      ).map(_label).toList();
      expect(labels, <String>['0', '1', '2']);
      expect(_chart(tester).maxY, 2);
    });

    testWidgets('labels today and keeps the dates apart', (
      WidgetTester tester,
    ) async {
      _usePhone(tester);
      await _pump(tester, <ViceActivity>[_daysAgo(12, 1)]);

      final List<Element> dates = _axisLabels(tester, dates: true);
      expect(dates.length, greaterThanOrEqualTo(2));
      expect(dates.map(_label), contains('Today'));
      expect(dates.map(_label).toSet(), hasLength(dates.length));
      _expectApart(dates);
      final Rect chart = tester.getRect(find.byType(LineChart));
      for (final Element date in dates) {
        expect(_rect(date).left, greaterThanOrEqualTo(chart.left));
        expect(_rect(date).right, lessThanOrEqualTo(chart.right));
      }
    });

    testWidgets('keeps both lines from dipping below zero', (
      WidgetTester tester,
    ) async {
      _usePhone(tester);
      await _pump(tester, <ViceActivity>[_daysAgo(12, 1)]);

      final LineChartData data = _chart(tester);
      expect(data.minY, 0);
      expect(data.clipData.bottom, isTrue);
      expect(data.lineBarsData, hasLength(2));
      expect(data.lineBarsData.last.preventCurveOverShooting, isTrue);
      for (final LineChartBarData bar in data.lineBarsData) {
        expect(bar.spots.every((FlSpot s) => s.y >= 0), isTrue);
      }
    });

    testWidgets('states the total, the average per day and the peak', (
      WidgetTester tester,
    ) async {
      _usePhone(tester);
      await _pump(tester, <ViceActivity>[_daysAgo(12, 6), _daysAgo(3, 3)]);

      expect(find.text('last 30 days'), findsOneWidget);
      // The tile's, and the peek's under the open sheet.
      expect(find.text('0.3'), findsNWidgets(2));
      expect(find.text('per day'), findsOneWidget);
      expect(
        find.text(
          TrendsChart.readoutLabel(usageRange(_today, 30, 1), 17, _today),
        ),
        findsOneWidget,
      );
    });
  });

  for (final double textScale in <double>[1.0, 2.0, 3.0]) {
    testWidgets('a year of days keeps its dates apart at text scale '
        '$textScale', (WidgetTester tester) async {
      _usePhone(tester);
      await _pump(tester, <ViceActivity>[_daysAgo(0, 3), _daysAgo(200, 40)]);
      await _tapText(tester, '1Y');
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      await tester.pumpAndSettle();

      expect(_chart(tester).lineBarsData.first.spots, hasLength(365));
      final List<Element> dates = _axisLabels(tester, dates: true);
      expect(dates, isNotEmpty);
      _expectApart(dates);
      _expectApart(_axisLabels(tester, dates: false));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('every month fits the space measured for a date', (
    WidgetTester tester,
  ) async {
    _usePhone(tester);
    await _pump(tester, <ViceActivity>[_daysAgo(0, 1)]);
    final BuildContext context = tester.element(find.byType(TrendsChart));
    final TextStyle style = TextStyle(
      fontSize: 10,
      fontFamily: Theme.of(context).textTheme.bodySmall?.fontFamily,
    );
    final double widest = TrendsChart.widestDateLabel(context, style);
    for (int month = 1; month <= 12; month++) {
      for (final int day in <int>[1, 9, 28]) {
        final TextPainter painter = TextPainter(
          text: TextSpan(
            text: formatShortDay(DateTime(2000, month, day)),
            style: DefaultTextStyle.of(context).style.merge(style),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        expect(painter.width, lessThanOrEqualTo(widest + 0.5));
        painter.dispose();
      }
    }
  });

  group('weekly', () {
    testWidgets('counts weeks back from today, keeps every day of the range, '
        'and starts at a four-week average', (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      _usePhone(tester);
      await _pump(tester, <ViceActivity>[
        _daysAgo(0, 2),
        _daysAgo(6, 3),
        _daysAgo(7, 4),
        // In the two days left over before the four whole weeks.
        _daysAgo(29, 1),
      ]);
      await _tapText(tester, 'Week');

      expect(_totals(tester), <double>[1, 0, 0, 4, 5]);
      final String newestWeek = formatShortDay(addDays(_today, -6));
      expect(
        find.bySemanticsLabel(
          'Weekly totals of Coffee over the last 30 days: 10 drinks in all. '
          'The most was 5 drinks in the week of $newestWeek. '
          'Shown with a 4-week average.',
        ),
        findsOneWidget,
      );
      expect(find.text('Average over 4 weeks'), findsOneWidget);
      expect(find.text('per week'), findsOneWidget);
      expect(find.text('week of $newestWeek'), findsOneWidget);
      expect(
        _axisLabels(tester, dates: true).map(_label),
        contains(newestWeek),
      );
      expect(find.text(TrendsSheet.hint(7)), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a single week has no average to offer', (
      WidgetTester tester,
    ) async {
      _usePhone(tester);
      await _pump(tester, <ViceActivity>[_daysAgo(0, 2)]);
      await _tapText(tester, '7D');
      await _tapText(tester, 'Week');

      expect(find.text('No average line'), findsOneWidget);
      expect(_chart(tester).lineBarsData, hasLength(1));
      for (final String tooltip in <String>[
        TrendsSheet.shorterAverage,
        TrendsSheet.longerAverage,
      ]) {
        expect(
          tester
              .widget<IconButton>(
                find.ancestor(
                  of: find.byTooltip(tooltip),
                  matching: find.byType(IconButton),
                ),
              )
              .onPressed,
          isNull,
        );
      }
    });
  });

  group('the average stepper', () {
    testWidgets('lengthens and shortens the average, within the buckets '
        'shown, and is announced', (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      _usePhone(tester);
      await _pump(tester, <ViceActivity>[_daysAgo(0, 2), _daysAgo(10, 4)]);

      expect(find.text('Average over 7 days'), findsOneWidget);
      await tester.tap(find.byTooltip(TrendsSheet.longerAverage));
      await tester.pumpAndSettle();
      expect(find.text('Average over 8 days'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'Shown with a 8-day average\.$')),
        findsOneWidget,
      );
      final List<double> smoothed = _chart(
        tester,
      ).lineBarsData.last.spots.map((FlSpot s) => s.y).toList();
      expect(smoothed.last, 2 / 8);

      // 7 days hold only 7 buckets; 8 is kept for when there is room.
      await _tapText(tester, '7D');
      expect(find.text('Average over 7 days'), findsOneWidget);
      await _tapText(tester, '30D');
      expect(find.text('Average over 8 days'), findsOneWidget);

      for (int i = 0; i < 7; i++) {
        await tester.tap(find.byTooltip(TrendsSheet.shorterAverage));
        await tester.pumpAndSettle();
      }
      expect(find.text('No average line'), findsOneWidget);
      expect(_chart(tester).lineBarsData, hasLength(1));
      semantics.dispose();
    });
  });

  group('the cursor', () {
    testWidgets('starts on today and follows a drag; a tap on a day opens '
        'its dial, and Back returns', (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      _usePhone(tester);
      await _pump(tester, <ViceActivity>[
        _daysAgo(0, 2),
        _daysAgo(29, 5, hour: 8),
      ]);
      expect(find.textContaining('Today  2 drinks'), findsOneWidget);

      final Rect chart = tester.getRect(find.byType(LineChart));
      await tester.dragFrom(
        Offset(chart.right - 4, chart.center.dy),
        Offset(-chart.width, 0),
      );
      await tester.pumpAndSettle();
      final String oldest = TrendsChart.readoutLabel(
        usageRange(_today, 30, 1),
        0,
        _today,
      );
      expect(find.textContaining('$oldest  5 drinks'), findsOneWidget);

      await tester.tapAt(Offset(chart.left + 40, chart.center.dy));
      await tester.pumpAndSettle();
      final TrendsDay day = tester.widget<TrendsDay>(find.byType(TrendsDay));
      expect(daysBetween(day.day, _today), greaterThan(20));
      expect(find.byType(DayDial), findsNWidgets(2));
      expect(find.byType(LineChart), findsNothing);

      await tester.tap(find.byTooltip(TrendsDay.backLabel));
      await tester.pumpAndSettle();
      expect(find.byType(TrendsDay), findsNothing);
      expect(find.byType(LineChart), findsOneWidget);
      semantics.dispose();
    });

    testWidgets("a screen reader hears the cursor's day, moves it and opens "
        'that day', (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      _usePhone(tester);
      await _pump(tester, <ViceActivity>[_daysAgo(0, 2), _daysAgo(1, 3)]);
      final UsageRange range = usageRange(_today, 30, 1);
      final FinderBase<SemanticsNode> chart = find.semantics.byLabel(
        RegExp('^Daily totals of Coffee'),
      );
      SemanticsData data() => chart.evaluate().single.getSemanticsData();

      expect(data().value, startsWith('Today, 2 drinks'));
      expect(data().hasAction(SemanticsAction.increase), isFalse);
      expect(data().hasAction(SemanticsAction.tap), isTrue);

      tester.semantics.decrease(chart);
      await tester.pumpAndSettle();
      final String yesterday = TrendsChart.readoutLabel(range, 28, _today);
      expect(data().value, startsWith('$yesterday, 3 drinks'));
      expect(find.textContaining('$yesterday  3 drinks'), findsOneWidget);
      expect(data().hasAction(SemanticsAction.increase), isTrue);

      tester.semantics.tap(chart);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TrendsDay>(find.byType(TrendsDay)).day,
        addDays(_today, -1),
      );
      semantics.dispose();
    });

    testWidgets('a keyboard moves the cursor with the arrows, opens its day '
        'with Enter, and comes back to the chart', (WidgetTester tester) async {
      _usePhone(tester);
      await _pump(tester, <ViceActivity>[_daysAgo(0, 2), _daysAgo(1, 3)]);
      FocusNode? focused() => FocusManager.instance.primaryFocus;
      bool onChart() => focused()?.debugLabel == TrendsChart.focusLabel;

      for (int i = 0; i < 30 && !onChart(); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(onChart(), isTrue);
      final ShapeDecoration ring =
          tester
                  .widget<DecoratedBox>(
                    find.ancestor(
                      of: find.byType(LineChart),
                      matching: find.byWidgetPredicate(
                        (Widget w) =>
                            w is DecoratedBox &&
                            w.position == DecorationPosition.foreground,
                      ),
                    ),
                  )
                  .decoration
              as ShapeDecoration;
      expect(
        (ring.shape as OutlinedBorder).side.color,
        Theme.of(tester.element(find.byType(LineChart))).colorScheme.primary,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      final String yesterday = TrendsChart.readoutLabel(
        usageRange(_today, 30, 1),
        28,
        _today,
      );
      expect(find.textContaining('$yesterday  3 drinks'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.textContaining('Today  2 drinks'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TrendsDay>(find.byType(TrendsDay)).day,
        addDays(_today, -1),
      );
      expect(focused()?.debugLabel, TrendsDay.backLabel);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(TrendsDay), findsNothing);
      expect(onChart(), isTrue);
    });

    testWidgets("a day's dial shows every habit's entries, read only", (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      _usePhone(tester);
      final List<ViceActivity> entries = <ViceActivity>[
        _daysAgo(0, 2, hour: 0),
        _daysAgo(0, 1, vice: _sweets, hour: 0),
      ];
      await _pump(
        tester,
        entries,
        days: (DateTime day) =>
            day == _today ? entries : const <ViceActivity>[],
      );
      final Rect chart = tester.getRect(find.byType(LineChart));
      await tester.tapAt(Offset(chart.right - 2, chart.center.dy));
      await tester.pumpAndSettle();

      expect(tester.widget<TrendsDay>(find.byType(TrendsDay)).day, _today);
      expect(inTrends(find.text('Today')), findsWidgets);
      expect(find.text(TrendsDay.subtitle(2, _coffee, 2)), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(TrendsDay),
          matching: find.bySemanticsLabel('Sweets, 1 drink'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(TrendsDay),
          matching: find.byTooltip('Log 1 drink of Coffee'),
        ),
        findsNothing,
      );
      semantics.dispose();
    });
  });

  group('when it happens', () {
    testWidgets("names the busiest three hours and the morning's share", (
      WidgetTester tester,
    ) async {
      _usePhone(tester);
      await _pump(tester, <ViceActivity>[
        _daysAgo(0, 2, hour: 7),
        _daysAgo(1, 2, hour: 8),
        _daysAgo(2, 1, hour: 9),
        _daysAgo(2, 1, hour: 21),
      ]);
      final bool h24 = MediaQuery.alwaysUse24HourFormatOf(
        tester.element(find.byType(TrendsChart)),
      );
      String at(int h) =>
          formatTime(DateTime(2000, 1, 1, h), alwaysUse24HourFormat: h24);
      expect(find.text('Mostly ${at(7)}–${at(10)}'), findsOneWidget);
      expect(
        find.text(
          'When Coffee happens, over the last 30 days. 83% of it before noon.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('says so when the range is empty', (WidgetTester tester) async {
      _usePhone(tester);
      await _pump(tester, const <ViceActivity>[]);
      expect(find.text(TrendsSheet.whenEmptyTitle), findsOneWidget);
      expect(find.text('No entries for Coffee in this range'), findsOneWidget);
    });
  });

  testWidgets('a failed load says so and retries', (WidgetTester tester) async {
    _usePhone(tester);
    int calls = 0;
    await _pump(
      tester,
      const <ViceActivity>[],
      graph: (ViceActivityGraphQuery query) {
        calls++;
        return AsyncError<List<ViceActivity>>(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
          StackTrace.empty,
        );
      },
    );
    expect(find.textContaining('Coffee for this range'), findsOneWidget);
    expect(inTrends(find.text('Retry')), findsOneWidget);
    expect(calls, greaterThan(0));
  });
}
