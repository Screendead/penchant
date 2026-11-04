import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/main.dart';

import 'support.dart';

// The dialog scrolls at large text sizes, so a control can sit below the fold.
Future<void> _tapInDialog(WidgetTester tester, Finder finder) async {
  await pumpUntil(tester, finder);
  await tester.ensureVisible(finder);
  await pumpFor(tester, const Duration(milliseconds: 500));
  await tap(tester, finder);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('the radar puts an unused vice at its centre, and screen '
      'readers hear both charts', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, 'e2e-a11y-charts@example.com');
    await addVicesThroughManageData(tester);

    await recordActivity(tester, 'Coffee', 2);
    await recordActivity(tester, 'Tea', 1);
    await expectRadar(tester, const <String>{
      'Coffee (2 drinks)',
      'Tea (1 drink)',
      'Water (0 drinks)',
    });

    final RadarChartData radar = tester
        .widget<RadarChart>(find.byType(RadarChart))
        .data;
    expect(radar.isMinValueAtCenter, isTrue);
    expect(radar.minEntry.value, 0);
    await screenshot(tester, 'a11y-radar-zero-at-centre');

    // Vices list newest first.
    final DateTime today = startOfDay(DateTime.now());
    expect(
      find.bySemanticsLabel(
        'Totals for ${formatDay(today)}. Water: 0 drinks; '
        'Tea: 1 drink; Coffee: 2 drinks',
      ),
      findsOneWidget,
    );

    await tap(tester, find.text('Graph'));
    await pumpUntil(tester, find.text('Usage Graph'));
    await tap(tester, find.byType(DropdownButtonFormField<String>));
    await tap(tester, find.text('Coffee').last);
    await pumpUntil(tester, find.byType(LineChart));
    expect(
      find.bySemanticsLabel(
        'Daily totals of Coffee over the last 30 days: 2 drinks in all. '
        'The most was 2 drinks on ${formatShortDay(today)}.',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('an activity can be recorded at the largest text size', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, 'e2e-a11y-text@example.com');
    await addVicesThroughManageData(tester);

    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);

    await tap(tester, find.widgetWithText(TextButton, 'Record'));
    final Finder dialog = find.byType(AlertDialog);
    await pumpUntil(tester, dialog);
    await screenshot(tester, 'a11y-record-dialog-text-3x');
    await _tapInDialog(
      tester,
      find.descendant(
        of: find.byType(RecordNewActivityDialog),
        matching: find.byType(DropdownButtonFormField<String>),
      ),
    );
    await tap(tester, find.text('Water').last);
    final Finder quantity = find.widgetWithText(TextFormField, 'Quantity');
    await pumpUntil(tester, quantity);
    await tester.ensureVisible(quantity);
    await pumpFor(tester, const Duration(milliseconds: 500));
    await enterText(tester, 'Quantity', '4');
    await _tapInDialog(
      tester,
      find.descendant(of: dialog, matching: find.text('Record')),
    );
    await pumpUntil(tester, dialog, present: false);

    expect(tester.takeException(), isNull);
    final List<Object> stored = await storedActivities('Water');
    expect(stored, hasLength(1));
    // At this size the radar cuts its titles short to fit; screen readers
    // still hear the whole names.
    await pumpUntil(
      tester,
      find.bySemanticsLabel(
        'Totals for ${formatDay(startOfDay(DateTime.now()))}. '
        'Water: 4 drinks; Tea: 0 drinks; Coffee: 0 drinks',
      ),
    );
    final List<String> titles = chartTitles(tester)!.toList();
    expect(titles, hasLength(3));
    expect(titles.where((String t) => t.endsWith(' (4 drinks)')), hasLength(1));
    expect(titles.where((String t) => t.endsWith(' (0 drinks)')), hasLength(2));
    semantics.dispose();
  });
}
