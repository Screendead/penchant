import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  group('Today chart titles stay within their own space', () {
    final String longName = '${'a' * 30} ${'b' * 29}';

    List<Override> day(List<Vice> vices) => [
      unarchivedViceListProvider.overrideWith((ref) => AsyncData(vices)),
      viceActivityDayProvider.overrideWith(
        (ref, DateTime day) => AsyncData([
          for (final Vice vice in vices) fakeActivity(vice.id, 2, day),
        ]),
      ),
    ];

    Future<void> pumpToday(WidgetTester tester, List<Vice> vices) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: day(vices),
          child: MaterialApp(
            home: Scaffold(body: ViceChart(selectedDate: _today)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    List<Element> radarLabels(WidgetTester tester) => find
        .descendant(of: find.byType(ViceRadar), matching: find.byType(Text))
        .evaluate()
        .toList();

    bool cut(WidgetTester tester, String name) => tester
        .renderObject<RenderParagraph>(
          find.descendant(
            of: find.byType(ViceRadar),
            matching: find.text(name),
          ),
        )
        .didExceedMaxLines;

    // Every label on the screen, apart from the others, and above the key.
    void expectRadarLabelsFit(WidgetTester tester) {
      final List<Element> labels = radarLabels(tester);
      final Size screen =
          tester.view.physicalSize / tester.view.devicePixelRatio;
      for (final Element label in labels) {
        final Rect rect = _rect(label);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(screen.width));
        expect(rect.bottom, lessThanOrEqualTo(screen.height));
      }
      _expectApart(labels);
      final Finder key = find.byType(Wrap);
      if (key.evaluate().isNotEmpty) {
        for (final Element label in labels) {
          expect(
            _rect(label).bottom,
            lessThanOrEqualTo(tester.getRect(key).top),
          );
        }
      }
    }

    // The key's entries, which every vice has once the key is shown.
    Finder keyEntry(Vice vice) => find.text('${vice.name}: 2 items');

    testWidgets('two bars, one with a 60-character name, and a key', (
      WidgetTester tester,
    ) async {
      _usePhone(tester);
      final List<Vice> vices = [
        fakeVice('long', name: longName),
        fakeVice('tea'),
      ];
      await pumpToday(tester, vices);

      final Finder titles = find.descendant(
        of: find.byType(BarChart),
        matching: find.byType(Text),
      );
      expect(titles, findsNWidgets(2));
      _expectApart(titles.evaluate().toList());
      final Rect chart = tester.getRect(find.byType(BarChart));
      for (final Element title in titles.evaluate()) {
        expect(chart.left, lessThanOrEqualTo(_rect(title).left));
        expect(chart.right, greaterThanOrEqualTo(_rect(title).right));
      }
      expect(titles.evaluate().map((Element e) => (e.widget as Text).data), [
        longName,
        'tea (2 items)',
      ]);
      for (final Vice vice in vices) {
        expect(keyEntry(vice), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('two bars at large text with a 60-character name have a '
        'key that names both', (WidgetTester tester) async {
      _usePhone(tester, textScale: 3);
      final List<Vice> vices = [
        fakeVice('long', name: longName),
        fakeVice('tea'),
      ];
      await pumpToday(tester, vices);

      for (final Vice vice in vices) {
        await tester.ensureVisible(keyEntry(vice));
        await tester.pumpAndSettle();
        expect(keyEntry(vice).hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('bars whose titles fit have no key', (
      WidgetTester tester,
    ) async {
      _usePhone(tester);
      final List<Vice> vices = [fakeVice('tea'), fakeVice('gin')];
      await pumpToday(tester, vices);

      expect(find.text('tea (2 items)'), findsOneWidget);
      expect(keyEntry(vices.first), findsNothing);
    });

    testWidgets(
      'a bar drops the quantity at large text before cutting a name',
      (WidgetTester tester) async {
        _usePhone(tester, textScale: 3);
        final List<Vice> vices = [fakeVice('coffee', name: 'Coffee')];
        await pumpToday(tester, vices);

        expect(find.text('Coffee'), findsOneWidget);
        expect(keyEntry(vices.first), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a radar with too many axes for its names cuts them and '
        'lists every vice in the key', (WidgetTester tester) async {
      _usePhone(tester);
      final List<Vice> vices = [
        for (int i = 1; i <= 12; i++) fakeVice('v$i', name: 'Vice $i'),
      ];
      await pumpToday(tester, vices);

      expect(vices.where((Vice v) => cut(tester, v.name)), isNotEmpty);
      expectRadarLabelsFit(tester);
      for (final Vice vice in vices) {
        expect(keyEntry(vice).hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a key with no room left for the radar takes its place', (
      WidgetTester tester,
    ) async {
      _usePhone(tester, textScale: 3);
      final List<Vice> vices = [
        for (int i = 1; i <= 31; i++) fakeVice('v$i', name: 'Vice $i'),
      ];
      await pumpToday(tester, vices);

      expect(find.byType(ViceRadar), findsNothing);
      expect(keyEntry(vices.first).hitTestable(), findsOneWidget);
      expect(keyEntry(vices.last), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a radar name too long for its space is cut, keeps its '
        'amount, and the key names every vice', (WidgetTester tester) async {
      _usePhone(tester);
      final List<Vice> vices = [
        fakeVice('long', name: longName),
        fakeVice('tea'),
        fakeVice('beer'),
      ];
      await pumpToday(tester, vices);

      expect(cut(tester, longName), isTrue);
      expect(
        find.descendant(
          of: find.byType(ViceRadar),
          matching: find.text('2 items'),
        ),
        findsNWidgets(3),
      );
      expectRadarLabelsFit(tester);
      for (final Vice vice in vices) {
        expect(keyEntry(vice), findsOneWidget);
      }
    });

    testWidgets('radar names that fit at large text need no key', (
      WidgetTester tester,
    ) async {
      _usePhone(tester, textScale: 3);
      final List<Vice> vices = [
        fakeVice('gin', name: 'Gin'),
        fakeVice('tea', name: 'Tea'),
        fakeVice('rum', name: 'Rum'),
      ];
      await pumpToday(tester, vices);

      for (final Vice vice in vices) {
        expect(cut(tester, vice.name), isFalse);
      }
      expectRadarLabelsFit(tester);
      expect(keyEntry(vices.first), findsNothing);
    });
  });
}
