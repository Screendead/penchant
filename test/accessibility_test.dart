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
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/usage_graph_view.dart';
import 'package:tracker/vice_chart.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/clean_day.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';

import 'fakes.dart';

final DateTime _today = startOfDay(DateTime.now());
final String _todayLabel = formatDay(_today);

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
  unarchivedViceListProvider.overrideWith((ref) => AsyncData(vices)),
  viceActivityDayProvider.overrideWith(
    (ref, DateTime day) => AsyncData([
      for (int i = 0; i < vices.length; i++)
        if (quantities[i] > 0) fakeActivity(vices[i].id, quantities[i], day),
    ]),
  ),
];

final List<Vice> _three = [
  fakeVice('coffee'),
  fakeVice('beer'),
  fakeVice('tea'),
];

RadarChartData _radar(WidgetTester tester) =>
    tester.widget<RadarChart>(find.byType(RadarChart)).data;

void main() {
  group('the radar', () {
    testWidgets('puts a zero at the centre', (WidgetTester tester) async {
      await _pump(tester, _day(_three, [2, 0, 1]), const ViceTracker());

      final RadarChartData data = _radar(tester);
      expect(data.isMinValueAtCenter, isTrue);
      expect(data.minEntry.value, 0);
      expect(data.dataSets.first.dataEntries.map((RadarEntry e) => e.value), [
        2,
        0,
        1,
      ]);
    });

    testWidgets('keeps the centre at zero when every vice was used', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _day(_three, [3, 1, 2]), const ViceTracker());

      final RadarChartData data = _radar(tester);
      expect(data.isMinValueAtCenter, isTrue);
      expect(data.minEntry.value, 0);
      expect(data.maxEntry.value, 3);
      expect(data.tickCount, 3);
    });

    test('rings are round numbers, at most five of them', () {
      expect(ViceChart.radarScale(1), (top: 1, step: 1));
      expect(ViceChart.radarScale(3), (top: 3, step: 1));
      expect(ViceChart.radarScale(7), (top: 8, step: 2));
      expect(ViceChart.radarScale(120), (top: 150, step: 50));
      for (int largest = 1; largest <= 1000; largest++) {
        final ({int top, int step}) scale = ViceChart.radarScale(largest);
        expect(scale.top, greaterThanOrEqualTo(largest));
        expect(scale.top ~/ scale.step, lessThanOrEqualTo(5));
        expect(scale.top % scale.step, 0);
      }
    });
  });

  group('screen readers', () {
    testWidgets('hear the radar as the day and each total', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await _pump(tester, _day(_three, [2, 0, 1]), const ViceTracker());

      expect(
        find.bySemanticsLabel(
          'Totals for $_todayLabel. coffee: 2 items; beer: 0 items; '
          'tea: 1 item',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('hear the bars as the day and each total, once', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await _pump(
        tester,
        _day(_three.sublist(0, 2), [2, 1]),
        const ViceTracker(),
      );

      expect(
        find.bySemanticsLabel(
          'Totals for $_todayLabel. coffee: 2 items; beer: 1 item',
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('coffee (2 items)'), findsNothing);
      semantics.dispose();
    });

    testWidgets('hear the graph as its range, total and peak', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      final DateTime peakDay = addDays(_today, -3);
      await _pump(tester, [
        viceListProvider.overrideWith((ref) => AsyncData([_three.first])),
        viceActivityGraphProvider.overrideWith(
          (ref, ViceActivityGraphQuery query) => AsyncData(<ViceActivity>[
            fakeActivity('coffee', 4, peakDay.add(const Duration(hours: 9))),
            fakeActivity('coffee', 1, _today.add(const Duration(hours: 9))),
          ]),
        ),
      ], const UsageGraphView());

      expect(
        find.bySemanticsLabel(
          'Daily totals of coffee over the last 30 days: 5 items in all. '
          'The most was 4 items on ${formatShortDay(peakDay)}.',
        ),
        findsOneWidget,
      );
      expect(find.text('Smoothing: 1 bucket for coffee'), findsOneWidget);
      semantics.dispose();
    });
  });

  test('the graph says which series is which in words', () {
    expect(UsageGraphView.seriesName(1), 'Daily total');
    expect(UsageGraphView.averageName(1, 3), '3-day average');
    expect(UsageGraphView.averageName(7, 2), '2-week average');
  });

  for (final double textScale in [2.0, 3.0]) {
    group('at text scale $textScale', () {
      testWidgets('the record dialog scrolls and still records', (
        WidgetTester tester,
      ) async {
        _usePhone(tester, textScale: textScale);
        await _pump(tester, [
          userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
          unarchivedViceListProvider.overrideWith((ref) => AsyncData(_three)),
        ], const RecordNewActivityDialog());

        expect(tester.takeException(), isNull);
        expect(find.byType(Scrollable), findsWidgets);

        final Finder quantity = find.widgetWithText(TextFormField, 'Quantity');
        await tester.ensureVisible(quantity);
        await tester.pumpAndSettle();
        await tester.enterText(quantity, '0');
        // No vice is selected, so validation runs but nothing is written.
        await tester.tap(find.text('Record'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Please select a vice'));
        expect(find.text('Please select a vice'), findsOneWidget);
        expect(find.text('Please enter at least 1'), findsOneWidget);
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
              viceListProvider.overrideWith((ref) => AsyncData(_three)),
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

        await tester.tap(find.text('Record'));
        await tester.pumpAndSettle();
        expect(find.byType(RecordNewActivityDialog), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Graph'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('Today lays out without overflowing', (
        WidgetTester tester,
      ) async {
        _usePhone(tester, textScale: textScale);
        await _pump(tester, _day(_three, [2, 0, 1]), const ViceTracker());
        expect(tester.takeException(), isNull);

        for (int i = 0; i < ViceTracker.selectableDays - 1; i++) {
          await tester.tap(find.byTooltip('Previous day'));
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(find.text('29 days ago'), findsOneWidget);
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
              viceListProvider.overrideWith((ref) => AsyncData(_three)),
              viceActivityGraphProvider.overrideWith(
                (ref, ViceActivityGraphQuery query) =>
                    AsyncData(<ViceActivity>[]),
              ),
            ],
            child: const MaterialApp(home: Homepage()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(CleanDay), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the graph reserves room for its scaled axis labels', (
        WidgetTester tester,
      ) async {
        _usePhone(tester, textScale: textScale);
        await _pump(tester, [
          viceListProvider.overrideWith((ref) => AsyncData([_three.first])),
          viceActivityGraphProvider.overrideWith(
            (ref, ViceActivityGraphQuery query) =>
                AsyncData(<ViceActivity>[fakeActivity('coffee', 1200, _today)]),
          ),
        ], const UsageGraphView());
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
