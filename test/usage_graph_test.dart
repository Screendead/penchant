import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/usage_graph_view.dart';
import 'package:tracker/vice_chart.dart';

import 'fakes.dart';

final DateTime _today = startOfDay(DateTime.now());
final Vice _coffee = fakeVice('coffee');

ViceActivity _daysAgo(int days, int quantity) =>
    fakeActivity('coffee', quantity, addDays(_today, -days).add(_noon));

const Duration _noon = Duration(hours: 12);

// An iPhone SE-sized screen, the smallest the app runs on.
void _usePhone(WidgetTester tester, {double textScale = 1}) {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = const Size(375 * 2, 667 * 2);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _pumpGraph(
  WidgetTester tester,
  List<ViceActivity> activities,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        viceListProvider.overrideWith((ref) => AsyncData([_coffee])),
        viceActivityGraphProvider.overrideWith(
          (ref, ViceActivityGraphQuery query) => AsyncData([
            for (final ViceActivity activity in activities)
              if (!activity.createdAt.toDate().isBefore(query.start) &&
                  activity.createdAt.toDate().isBefore(query.end))
                activity,
          ]),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: UsageGraphView())),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pickTimestep(WidgetTester tester, String label) async {
  await tester.tap(find.byType(DropdownButtonFormField<int>).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _dragSmoothingToMax(WidgetTester tester) async {
  await tester.drag(find.byType(Slider), const Offset(1000, 0));
  await tester.pumpAndSettle();
}

LineChartData _chart(WidgetTester tester) =>
    tester.widget<LineChart>(find.byType(LineChart)).data;

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

String _smoothingCaption(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text t) => t.data)
    .whereType<String>()
    .firstWhere((String s) => s.startsWith('Smoothing: '));

void main() {
  group('a single recorded day in 30', () {
    testWidgets('labels the y-axis once per value', (
      WidgetTester tester,
    ) async {
      _usePhone(tester);
      await _pumpGraph(tester, [_daysAgo(12, 1)]);

      final List<String> labels = _axisLabels(
        tester,
        dates: false,
      ).map(_label).toList();
      expect(labels, ['0', '1', '2']);
      expect(_chart(tester).maxY, 2);
    });

    testWidgets('labels today and keeps the dates apart', (
      WidgetTester tester,
    ) async {
      _usePhone(tester);
      await _pumpGraph(tester, [_daysAgo(12, 1)]);

      final List<Element> dates = _axisLabels(tester, dates: true);
      expect(dates.length, greaterThanOrEqualTo(2));
      expect(dates.map(_label), contains(formatShortDay(_today)));
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
      await _pumpGraph(tester, [_daysAgo(12, 1)]);
      await _dragSmoothingToMax(tester);

      final LineChartData data = _chart(tester);
      expect(data.minY, 0);
      expect(data.clipData.bottom, isTrue);
      expect(data.lineBarsData, hasLength(2));
      for (final LineChartBarData bar in data.lineBarsData) {
        expect(bar.preventCurveOverShooting, isTrue);
        expect(bar.spots.every((FlSpot s) => s.y >= 0), isTrue);
      }
    });
  });

  for (final double textScale in [1.0, 2.0, 3.0]) {
    testWidgets('a year of days keeps its dates apart at text scale '
        '$textScale', (WidgetTester tester) async {
      _usePhone(tester);
      await _pumpGraph(tester, [_daysAgo(0, 3), _daysAgo(200, 40)]);
      await tester.tap(find.byType(DropdownButtonFormField<int>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('365 days').last);
      await tester.pumpAndSettle();
      // The range menu scrolls at large text sizes; pick first, then scale.
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

  group('weekly', () {
    testWidgets('counts weeks back from today and keeps every day of the '
        'range', (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      _usePhone(tester);
      await _pumpGraph(tester, [
        _daysAgo(0, 2),
        _daysAgo(6, 3),
        _daysAgo(7, 4),
        // In the two days left over before the four whole weeks.
        _daysAgo(29, 1),
      ]);
      await _pickTimestep(tester, 'Weekly');

      expect(_chart(tester).lineBarsData.first.spots.map((FlSpot s) => s.y), [
        1,
        0,
        0,
        4,
        5,
      ]);
      final String newestWeek = formatShortDay(addDays(_today, -6));
      expect(
        find.bySemanticsLabel(
          'Weekly totals of coffee over the last 30 days: 10 items in all. '
          'The most was 5 items in the week of $newestWeek.',
        ),
        findsOneWidget,
      );
      expect(
        _axisLabels(tester, dates: true).map(_label),
        contains(newestWeek),
      );
      semantics.dispose();
    });

    testWidgets('a smoothing window picked on Daily shrinks to the weeks '
        'there are, everywhere it shows', (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      _usePhone(tester);
      await _pumpGraph(tester, [_daysAgo(0, 2), _daysAgo(10, 4)]);

      await _dragSmoothingToMax(tester);
      expect(_smoothingCaption(tester), 'Smoothing: 7 buckets for coffee');
      expect(find.text('7-day average'), findsOneWidget);

      await _pickTimestep(tester, 'Weekly');
      expect(_smoothingCaption(tester), 'Smoothing: 5 buckets for coffee');
      final Slider slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, 5);
      expect(slider.max, 5);
      expect(find.text('5-week average'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'Shown with a 5-week average\.$')),
        findsOneWidget,
      );
      // The average is over the 5 buckets, not a 7-wide window.
      final List<double> smoothed = _chart(
        tester,
      ).lineBarsData.last.spots.map((FlSpot s) => s.y).toList();
      expect(smoothed.last, (0 + 0 + 0 + 4 + 2) / 5);

      await _pickTimestep(tester, 'Daily');
      expect(_smoothingCaption(tester), 'Smoothing: 7 buckets for coffee');
      semantics.dispose();
    });

    testWidgets('a single week has no smoothing to offer', (
      WidgetTester tester,
    ) async {
      _usePhone(tester);
      await _pumpGraph(tester, [_daysAgo(0, 2)]);
      await _dragSmoothingToMax(tester);
      await tester.tap(find.byType(DropdownButtonFormField<int>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('7 days').last);
      await tester.pumpAndSettle();
      await _pickTimestep(tester, 'Weekly');

      expect(find.byType(Slider), findsNothing);
      expect(
        find.text('Smoothing is unavailable for a single bucket'),
        findsOneWidget,
      );
      expect(_smoothingCaption(tester), 'Smoothing: 1 bucket for coffee');
      expect(_chart(tester).lineBarsData, hasLength(1));
    });
  });

  group('Today shows every name and amount whole', () {
    final String longName = '${'a' * 30} ${'b' * 29}';

    List<Override> day(List<Vice> vices, List<int> quantities) => [
      unarchivedViceListProvider.overrideWith((ref) => AsyncData(vices)),
      viceActivityDayProvider.overrideWith(
        (ref, DateTime day) => AsyncData([
          for (int i = 0; i < vices.length; i++)
            if (quantities[i] > 0)
              fakeActivity(vices[i].id, quantities[i], day),
        ]),
      ),
    ];

    Future<void> pumpToday(
      WidgetTester tester,
      List<Vice> vices,
      List<int> quantities,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: day(vices, quantities),
          child: MaterialApp(
            home: Scaffold(body: ViceChart(selectedDate: _today)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder amount(String text) => find.text(text, findRichText: true);

    testWidgets('a 60-character name wraps whole beside its amount', (
      WidgetTester tester,
    ) async {
      _usePhone(tester);
      await pumpToday(
        tester,
        [fakeVice('long', name: longName), fakeVice('tea')],
        [1, 0],
      );

      for (final Finder text in [
        find.text(longName),
        amount('1 item'),
        find.text('tea'),
        amount('0 items'),
      ]) {
        expect(text, findsOneWidget);
        final Rect rect = tester.getRect(text);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(375));
        expect(rect.bottom, lessThanOrEqualTo(667));
      }
      expect(
        tester
            .getRect(find.text(longName))
            .overlaps(tester.getRect(amount('1 item'))),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('at large text, many vices scroll rather than overflow', (
      WidgetTester tester,
    ) async {
      _usePhone(tester, textScale: 3);
      final List<Vice> vices = [
        for (int i = 1; i <= 31; i++) fakeVice('v$i', name: 'Vice $i'),
      ];
      await pumpToday(tester, vices, [for (int i = 1; i <= 31; i++) i % 3]);

      for (final Vice vice in [vices.first, vices.last]) {
        await tester.ensureVisible(find.text(vice.name));
        await tester.pumpAndSettle();
        expect(find.text(vice.name).hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  });
}
