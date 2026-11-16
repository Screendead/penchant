import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/ask/ask_answer.dart';
import 'package:tracker/ask/ask_chart.dart';
import 'package:tracker/design/app_theme.dart';

const AskChartSpec _monthBars = AskChartSpec(
  type: AskChartType.bar,
  x: 'month',
  y: <String>['glasses'],
  xKind: AskXKind.month,
);

AskRows _months(List<String> months, [List<Object?>? values]) => AskRows(
  const <String>['month', 'glasses'],
  <List<Object?>>[
    for (int i = 0; i < months.length; i++)
      <Object?>[months[i], values == null ? i + 1 : values[i]],
  ],
);

Future<void> _pump(
  WidgetTester tester,
  AskChartSpec spec,
  AskRows rows, {
  ValueChanged<DateTime>? onOpenDay,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(Brightness.light),
      home: Scaffold(
        body: AskChart(spec: spec, rows: rows, onOpenDay: onOpenDay),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('planAskChart', () {
    test('falls back to a table when a column is missing', () {
      final AskChartPlan plan = planAskChart(
        const AskChartSpec(
          type: AskChartType.bar,
          x: 'month',
          y: <String>['nope'],
          xKind: AskXKind.month,
        ),
        _months(<String>['2025-01', '2025-02']),
      );
      expect(plan.kind, AskChartKind.table);
    });

    test('falls back to a table when y is not numeric', () {
      final AskChartPlan plan = planAskChart(
        _monthBars,
        _months(<String>['2025-01', '2025-02'], <Object?>[1, 'two']),
      );
      expect(plan.kind, AskChartKind.table);
      expect(plan.cells[1], <String>['2025-02', 'two']);
    });

    test('falls back to a table on a month that is not one', () {
      expect(
        planAskChart(_monthBars, _months(<String>['2025-01', '2025-13'])).kind,
        AskChartKind.table,
      );
      expect(
        planAskChart(_monthBars, _months(<String>['2025-01', 'Jan'])).kind,
        AskChartKind.table,
      );
    });

    test('falls back to a table on a day that does not exist', () {
      final AskChartPlan plan = planAskChart(
        const AskChartSpec(
          type: AskChartType.line,
          x: 'day',
          y: <String>['n'],
          xKind: AskXKind.day,
        ),
        const AskRows(
          <String>['day', 'n'],
          <List<Object?>>[
            <Object?>['2025-02-28', 1],
            <Object?>['2025-02-30', 2],
          ],
        ),
      );
      expect(plan.kind, AskChartKind.table);
    });

    test('pivots one series per value, and too many is a table', () {
      const AskChartSpec spec = AskChartSpec(
        type: AskChartType.line,
        x: 'month',
        y: <String>['total'],
        series: 'habit',
        xKind: AskXKind.month,
      );
      final AskChartPlan plan = planAskChart(
        spec,
        const AskRows(
          <String>['month', 'habit', 'total'],
          <List<Object?>>[
            <Object?>['2025-02', 'Wine', 4],
            <Object?>['2025-01', 'Wine', 3],
            <Object?>['2025-01', 'Coffee', 9.5],
          ],
        ),
      );
      expect(plan.kind, AskChartKind.line);
      expect(plan.points.map((AskPoint p) => p.full), <String>[
        'January 2025',
        'February 2025',
      ]);
      expect(plan.series.map((AskSeries s) => s.name), <String>[
        'Wine',
        'Coffee',
      ]);
      expect(plan.series[0].values, <double?>[3, 4]);
      expect(plan.series[1].values, <double?>[9.5, null]);

      final AskChartPlan many = planAskChart(
        spec,
        AskRows(
          const <String>['month', 'habit', 'total'],
          <List<Object?>>[
            for (int i = 0; i < 7; i++) <Object?>['2025-01', 'H$i', i],
          ],
        ),
      );
      expect(many.kind, AskChartKind.table);
    });

    test('a number of several rows is a table, of one row a number', () {
      const AskChartSpec spec = AskChartSpec(
        type: AskChartType.number,
        y: <String>['glasses_total'],
      );
      expect(
        planAskChart(
          spec,
          const AskRows(
            <String>['glasses_total'],
            <List<Object?>>[
              <Object?>[1],
              <Object?>[2],
            ],
          ),
        ).kind,
        AskChartKind.table,
      );
      final AskChartPlan one = planAskChart(
        spec,
        const AskRows(
          <String>['glasses_total'],
          <List<Object?>>[
            <Object?>[12.345],
          ],
        ),
      );
      expect(one.kind, AskChartKind.number);
      expect(formatAskNumber(one.number!), '12.35');
      expect(one.numberLabel, 'Glasses total');
    });

    test('a line of one point is a bar; an empty y takes the one number', () {
      final AskChartPlan plan = planAskChart(
        const AskChartSpec(
          type: AskChartType.line,
          x: 'month',
          xKind: AskXKind.month,
        ),
        _months(<String>['2025-01']),
      );
      expect(plan.kind, AskChartKind.bar);
      expect(plan.series.single.key, 'glasses');
    });

    test('caps a table at 100 rows and says so', () {
      final AskChartPlan plan = planAskChart(
        const AskChartSpec(type: AskChartType.table),
        AskRows(
          const <String>['n'],
          <List<Object?>>[
            for (int i = 0; i < 340; i++) <Object?>[i],
          ],
        ),
      );
      expect(plan.cells, hasLength(100));
      expect(plan.tableNote, 'First 100 of 340 rows');
    });
  });

  group('labels', () {
    test('months carry the year at the ends and where it changes', () {
      final AskChartPlan plan = planAskChart(
        _monthBars,
        _months(<String>[
          '2025-11',
          '2025-12',
          '2026-01',
          '2026-02',
          '2026-03',
        ]),
      );
      expect(askAxisLabels(plan, 6), <String>[
        'Nov 2025',
        'Dec',
        'Jan 2026',
        'Feb',
        'Mar 2026',
      ]);
      expect(plan.points[1].full, 'December 2025');
    });

    test('thinned labels keep the first and last', () {
      final AskChartPlan plan = planAskChart(
        _monthBars,
        _months(<String>[
          for (int m = 1; m <= 12; m++) '2025-${'$m'.padLeft(2, '0')}',
        ]),
      );
      final List<String?> labels = askAxisLabels(plan, 6);
      expect(labels.first, 'Jan 2025');
      expect(labels.last, 'Dec 2025');
      expect(labels.whereType<String>().length, lessThanOrEqualTo(6));
      expect(labels.whereType<String>().skip(1).first, isNot(contains('2025')));
    });

    test('days and weeks name the month', () {
      final AskChartPlan days = planAskChart(
        const AskChartSpec(
          type: AskChartType.bar,
          x: 'd',
          y: <String>['n'],
          xKind: AskXKind.day,
        ),
        const AskRows(
          <String>['d', 'n'],
          <List<Object?>>[
            <Object?>['2025-12-03', 1],
            <Object?>['2025-12-04', 2],
          ],
        ),
      );
      expect(askAxisLabels(days, 6), <String>['3 Dec 2025', '4 Dec 2025']);
      expect(days.points.first.full, 'Wed 3 Dec 2025');

      final AskChartPlan weeks = planAskChart(
        const AskChartSpec(
          type: AskChartType.bar,
          x: 'w',
          y: <String>['n'],
          xKind: AskXKind.week,
        ),
        const AskRows(
          <String>['w', 'n'],
          <List<Object?>>[
            <Object?>['2025-12-01', 1],
            <Object?>['2025-12-08', 1],
            <Object?>['2025-12-15', 1],
          ],
        ),
      );
      expect(askAxisLabels(weeks, 6), <String>[
        'w/c 1 Dec 2025',
        'w/c 8 Dec',
        'w/c 15 Dec 2025',
      ]);
      // Not a Monday.
      expect(
        planAskChart(
          const AskChartSpec(
            type: AskChartType.bar,
            x: 'w',
            y: <String>['n'],
            xKind: AskXKind.week,
          ),
          const AskRows(
            <String>['w', 'n'],
            <List<Object?>>[
              <Object?>['2025-12-02', 1],
            ],
          ),
        ).kind,
        AskChartKind.table,
      );
    });

    test('hours are 00 to 23 and weekdays are named', () {
      final AskChartPlan hours = planAskChart(
        const AskChartSpec(
          type: AskChartType.bar,
          x: 'h',
          y: <String>['n'],
          xKind: AskXKind.hour,
        ),
        AskRows(
          const <String>['h', 'n'],
          <List<Object?>>[
            for (int h = 23; h >= 0; h--) <Object?>[h == 5 ? '05' : h, h],
          ],
        ),
      );
      final List<String?> labels = askAxisLabels(hours, 6);
      expect(labels.first, '00');
      expect(labels.last, '23');
      expect(hours.points[20].full, '20:00–21:00');
      expect(hours.points[23].full, '23:00–00:00');

      final AskChartPlan weekdays = planAskChart(
        const AskChartSpec(
          type: AskChartType.bar,
          x: 'wd',
          y: <String>['n'],
          xKind: AskXKind.weekday,
        ),
        AskRows(
          const <String>['wd', 'n'],
          <List<Object?>>[
            for (int d = 1; d <= 7; d++) <Object?>[d, d],
          ],
        ),
      );
      expect(askAxisLabels(weekdays, 8), <String>[
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ]);
      expect(weekdays.points[2].full, 'Wednesday');
    });

    test('a long category is cut to 40 characters', () {
      final AskChartPlan plan = planAskChart(
        const AskChartSpec(
          type: AskChartType.bar,
          x: 'c',
          y: <String>['n'],
          xKind: AskXKind.category,
        ),
        AskRows(
          const <String>['c', 'n'],
          <List<Object?>>[
            <Object?>['x' * 60, 1],
          ],
        ),
      );
      expect(plan.points.single.axis, hasLength(40));
      expect(plan.points.single.axis, endsWith('…'));
    });
  });

  group('AskChart', () {
    final AskRows months = _months(
      <String>['2025-11', '2025-12', '2026-01'],
      <Object?>[3, 12, 7],
    );

    testWidgets('shows the last point, then the tapped one, then the next '
        'by arrow key', (WidgetTester tester) async {
      await _pump(tester, _monthBars, months);
      expect(find.byType(BarChart), findsOneWidget);
      expect(find.text('January 2026'), findsOneWidget);
      expect(find.text('Glasses 7'), findsOneWidget);
      // Axis titles are widgets under the chart.
      expect(find.text('Nov 2025'), findsOneWidget);

      final Rect chart = tester.getRect(find.byType(BarChart));
      await tester.tapAt(Offset(chart.left + chart.width / 5, chart.center.dy));
      await tester.pump();
      expect(find.text('November 2025'), findsOneWidget);
      expect(find.text('Glasses 3'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(find.text('December 2025'), findsOneWidget);
      expect(find.text('Glasses 12'), findsOneWidget);
    });

    testWidgets('has a summary and the read-out for a screen reader', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pump(tester, _monthBars, months);
      final Finder node = find.bySemanticsLabel(
        RegExp(
          r'^Bar chart, from November 2025 to January 2026\. Glasses: '
          r'highest 12 at December 2025, lowest 3 at November 2025\.$',
        ),
      );
      expect(node, findsOneWidget);
      expect(tester.getSemantics(node).value, 'January 2026: Glasses 7');
      handle.dispose();
    });

    testWidgets('a table shows formatted values', (WidgetTester tester) async {
      await _pump(
        tester,
        _monthBars,
        const AskRows(
          <String>['month', 'glasses_total'],
          <List<Object?>>[
            <Object?>['2025-01', 1.5],
            <Object?>['2025-02', null],
            <Object?>['2025-03', 'lots'],
          ],
        ),
      );
      expect(find.byType(BarChart), findsNothing);
      expect(find.text('Glasses total'), findsOneWidget);
      expect(find.text('1.5'), findsOneWidget);
      expect(find.text('–'), findsOneWidget);
      expect(find.text('lots'), findsOneWidget);
    });

    testWidgets('a number is one figure over its column', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const AskChartSpec(type: AskChartType.number, y: <String>['n_days']),
        const AskRows(
          <String>['n_days'],
          <List<Object?>>[
            <Object?>[14.0],
          ],
        ),
      );
      expect(find.text('14'), findsOneWidget);
      expect(find.text('N days'), findsOneWidget);
    });

    testWidgets('opens a month on its first day and a day on itself', (
      WidgetTester tester,
    ) async {
      final List<DateTime> opened = <DateTime>[];
      await _pump(tester, _monthBars, months, onOpenDay: opened.add);
      await tester.tap(find.text('Open January 2026 in Today'));
      expect(opened, <DateTime>[DateTime(2026)]);

      await _pump(
        tester,
        const AskChartSpec(
          type: AskChartType.bar,
          x: 'd',
          y: <String>['n'],
          xKind: AskXKind.day,
        ),
        const AskRows(
          <String>['d', 'n'],
          <List<Object?>>[
            <Object?>['2025-12-02', 1],
            <Object?>['2025-12-03', 2],
          ],
        ),
        onOpenDay: opened.add,
      );
      await tester.tap(find.text('Open Wed 3 Dec 2025 in Today'));
      expect(opened.last, DateTime(2025, 12, 3));
    });

    testWidgets('an hour chart offers no day to open', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const AskChartSpec(
          type: AskChartType.bar,
          x: 'h',
          y: <String>['n'],
          xKind: AskXKind.hour,
        ),
        AskRows(
          const <String>['h', 'n'],
          <List<Object?>>[
            for (int h = 0; h < 24; h++) <Object?>[h, h % 5],
          ],
        ),
        onOpenDay: (DateTime _) {},
      );
      expect(find.text('23:00–00:00'), findsOneWidget);
      expect(find.textContaining('in Today'), findsNothing);
    });
  });
}
