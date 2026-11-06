import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/vice_chart.dart';
import 'package:tracker/vice_tracker.dart';

import 'fakes.dart';

// An iPhone 13 Pro Max, in points.
void _useLargePhone(WidgetTester tester) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(428 * 3, 926 * 3);
  addTearDown(tester.view.reset);
}

Future<void> _pumpDay(
  WidgetTester tester,
  List<Vice> vices,
  List<int> quantities,
) async {
  final List<Override> overrides = [
    unarchivedViceListProvider.overrideWith((ref) => AsyncData(vices)),
    viceActivityDayProvider.overrideWith(
      (ref, DateTime day) => AsyncData([
        for (int i = 0; i < vices.length; i++)
          if (quantities[i] > 0) fakeActivity(vices[i].id, quantities[i], day),
      ]),
    ),
  ];
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: appTheme(Brightness.dark),
        home: const Scaffold(body: ViceTracker()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// The chart's titles: the radar paints its own, so they come from its data;
// the bars' are Text widgets.
List<String> _titles(WidgetTester tester, int count) {
  final Finder radar = find.byType(RadarChart);
  if (radar.evaluate().isNotEmpty) {
    final RadarChartData data = tester.widget<RadarChart>(radar).data;
    return [for (int i = 0; i < count; i++) data.getTitle!(i, 0).text];
  }
  return [
    for (final Element e
        in find
            .descendant(of: find.byType(BarChart), matching: find.byType(Text))
            .evaluate())
      (e.widget as Text).data!,
  ];
}

// Each vice's amount is on screen: in its title or in the key.
void _expectEveryAmountShown(
  WidgetTester tester,
  List<Vice> vices,
  List<int> quantities,
) {
  final List<String> titles = _titles(tester, vices.length);
  for (int i = 0; i < vices.length; i++) {
    final String amount = vices[i].unit.label(quantities[i]);
    if (titles.contains('${vices[i].name} ($amount)')) {
      continue;
    }
    expect(
      find.text(ViceChart.total(vices[i], quantities[i])).hitTestable(),
      findsOneWidget,
      reason: '${vices[i].name}: $amount appears nowhere',
    );
  }
}

Finder _inChart(Finder finder) =>
    find.descendant(of: find.byType(ViceChart), matching: finder);

void main() {
  // In the test font a glyph is as wide as its size, so these names fit a
  // title of their own at this size but not with the amount after them.
  final List<Vice> five = [
    fakeVice('late-nights', name: 'Late Nights'),
    fakeVice('coffee', name: 'Coffee'),
    fakeVice('takeaway', name: 'Takeaway'),
    fakeVice('gaming', name: 'Gaming'),
    fakeVice('snacking', name: 'Snacking'),
  ];

  group('every amount is on screen', () {
    testWidgets('on the radar, when a title drops its amount', (
      WidgetTester tester,
    ) async {
      _useLargePhone(tester);
      const List<int> quantities = [1, 0, 1, 0, 0];
      await _pumpDay(tester, five, quantities);

      expect(find.byType(RadarChart), findsOneWidget);
      expect(
        _titles(tester, five.length).first,
        'Late Nights',
        reason: 'the name fits here, its amount does not',
      );
      _expectEveryAmountShown(tester, five, quantities);
    });

    testWidgets('on the bars, when a title drops its amount', (
      WidgetTester tester,
    ) async {
      _useLargePhone(tester);
      final List<Vice> two = five.sublist(0, 2);
      const List<int> quantities = [1, 0];
      await _pumpDay(tester, two, quantities);

      expect(find.byType(BarChart), findsOneWidget);
      expect(
        _titles(tester, two.length),
        contains('Late Nights'),
        reason: 'the name fits here, its amount does not',
      );
      _expectEveryAmountShown(tester, two, quantities);
    });

    testWidgets('with no key when every title holds its amount', (
      WidgetTester tester,
    ) async {
      _useLargePhone(tester);
      final List<Vice> short = [
        fakeVice('a', name: 'Tea'),
        fakeVice('b', name: 'Gum'),
        fakeVice('c', name: 'Pie'),
      ];
      await _pumpDay(tester, short, const [1, 2, 0]);

      expect(_titles(tester, short.length), [
        'Tea (1 item)',
        'Gum (2 items)',
        'Pie (0 items)',
      ]);
      expect(find.text(ViceChart.total(short.first, 1)), findsNothing);
    });
  });

  group('the radar rings', () {
    testWidgets('are labelled with whole numbers, not at the centre', (
      WidgetTester tester,
    ) async {
      _useLargePhone(tester);
      // Rings at 2, 4, 6 and 8, the last the radar's edge.
      await _pumpDay(tester, five, const [7, 0, 1, 0, 0]);

      final RadarChartData data = tester
          .widget<RadarChart>(find.byType(RadarChart))
          .data;
      // fl_chart prints each ring's value with one decimal, the centre's too.
      expect(data.ticksTextStyle?.color?.a, 0);
      for (final String ring in ['2', '4', '6']) {
        expect(_inChart(find.text(ring)), findsOneWidget);
      }
      for (final String ring in ['0', '0.0', '2.0', '8']) {
        expect(_inChart(find.text(ring)), findsNothing);
      }
    });

    testWidgets('print nothing when the only ring is the edge', (
      WidgetTester tester,
    ) async {
      _useLargePhone(tester);
      await _pumpDay(tester, five, const [1, 0, 1, 0, 0]);

      final RadarChartData data = tester
          .widget<RadarChart>(find.byType(RadarChart))
          .data;
      expect(data.ticksTextStyle?.color?.a, 0);
      for (final String ring in ['0', '0.0', '1']) {
        expect(_inChart(find.text(ring)), findsNothing);
      }
    });
  });
}
