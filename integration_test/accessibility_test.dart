import 'package:fl_chart/fl_chart.dart' show LineChart;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/widgets/log_fan.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';
import 'package:tracker/widgets/tally_row.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/trends/trends_sheet.dart';

import 'support.dart';

// The dialog scrolls at large text sizes, so a control can sit below the fold.
Future<void> _tapInDialog(WidgetTester tester, Finder finder) async {
  // A focused field scrolls itself back into view, away from the button.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await pumpUntil(tester, finder);
  await tester.ensureVisible(finder);
  await pumpFor(tester, const Duration(milliseconds: 500));
  await tap(tester, finder);
}

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('screen readers hear the dial, each bead and tally, and the '
      'graph', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(e2eApp());
    await register(tester, 'e2e-a11y-charts@example.com');
    await addVicesThroughManageData(tester);

    await recordActivity(tester, 'Coffee', 2);
    await recordActivity(tester, 'Tea', 1);
    await expectTallies(tester, const <String>{
      'Coffee (2 drinks)',
      'Tea (1 drink)',
      'Water (0 drinks)',
    });

    // Habits list oldest first.
    final DateTime today = startOfDay(DateTime.now());
    expect(
      find.bySemanticsLabel(
        RegExp(
          '^Today, ${RegExp.escape(dayPillDate(today, today))}\\. '
          'Coffee 2 drinks, Tea 1 drink, Water 0 drinks\\. First entry ',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('^Coffee, 2 drinks at ')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('^Tea, 1 drink at ')), findsOneWidget);
    await screenshot(tester, 'a11y-today-dial');
    // macOS's window can leave the last row below the fold.
    await scrollIntoView(
      tester,
      find.byTooltip('Log 1 drink of Water', skipOffstage: false),
    );
    expect(find.bySemanticsLabel('Water, 0 drinks'), findsOneWidget);
    expect(find.byTooltip('Log 1 drink of Water'), findsOneWidget);

    // Coffee is the oldest habit, so Trends opens on it. The pane of the
    // split view has no peek.
    await pumpUntil(tester, find.byType(TrendsSheet));
    final bool split = splitLayout(tester);
    if (!split) {
      expect(
        find.bySemanticsLabel(
          'Trends. Coffee, last 30 days: '
          '${formatAverage(2 / 30)} drinks a day',
        ),
        findsOneWidget,
      );
    }
    await openTrends(tester);
    await pumpUntil(tester, find.byType(LineChart));
    expect(
      find.bySemanticsLabel(
        'Daily totals of Coffee over the last 30 days: 2 drinks in all. '
        'The most was 2 drinks on ${formatShortDay(today)}. '
        'Shown with a 7-day average.',
      ),
      findsOneWidget,
    );
    // Under the sheet the Log button stays in the widget tree, out of the
    // semantics tree; beside the pane it stays in reach.
    expect(
      find.semantics.byLabel(LogButton.label),
      split ? findsOneWidget : findsNothing,
    );
    expect(
      find.byType(LogButton).hitTestable(),
      split ? findsOneWidget : findsNothing,
    );
    await closeTrends(tester);
    semantics.dispose();
  });

  testWidgets('an activity can be recorded at the largest text size', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(e2eApp());
    await register(tester, 'e2e-a11y-text@example.com');
    const List<String> names = <String>[
      'Coffee',
      'Tea',
      'Water',
      'Sparkling water',
    ];
    await addVicesThroughManageData(tester, names);

    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);

    // The fan's labels stop growing at 1.3 times, so the wedge stays whole.
    await tap(tester, find.byType(LogButton));
    await pumpFor(tester, const Duration(milliseconds: 800));
    expect(tester.takeException(), isNull);
    await screenshot(tester, 'a11y-log-fan-text-3x');
    await tester.longPress(fanWedge('Water'));
    final Finder dialog = find.byType(RecordNewActivityDialog);
    await pumpUntilRouteSettled(tester, dialog);
    await screenshot(tester, 'a11y-record-dialog-text-3x');
    final Finder quantity = find.widgetWithText(TextFormField, 'Quantity');
    await pumpUntil(tester, quantity);
    await tester.ensureVisible(quantity);
    await pumpFor(tester, const Duration(milliseconds: 500));
    await enterText(tester, 'Quantity', '4');
    await _tapInDialog(tester, find.byKey(RecordNewActivityDialog.submitKey));
    await pumpUntil(tester, dialog, present: false);

    expect(tester.takeException(), isNull);
    final List<Object> stored = await storedActivities('Water');
    expect(stored, hasLength(1));
    // Habits list oldest first.
    await pumpUntil(
      tester,
      find.bySemanticsLabel(
        RegExp(
          '^Today, .*\\. Coffee 0 drinks, Tea 0 drinks, Water 4 drinks, '
          'Sparkling water 0 drinks\\. One entry, at ',
        ),
      ),
    );
    // The Undo bar covers the bottom of the screen until it times out.
    await pumpUntil(tester, find.byType(SnackBar), present: false);
    await pumpFor(tester, const Duration(seconds: 1));
    await screenshot(tester, 'a11y-today-text-3x');

    // Each name is drawn whole in its tally row; hitTestable() rules out a
    // row covered by the Log button. Today scrolls, so each is brought into
    // view first.
    for (final String name in names) {
      final Finder row = find.descendant(
        of: find.byType(TallyRow, skipOffstage: false),
        matching: find.text(name, skipOffstage: false),
        skipOffstage: false,
      );
      for (int i = 0; i < 20 && row.evaluate().isEmpty; i++) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -150));
        await pumpFor(tester, const Duration(milliseconds: 300));
      }
      await scrollIntoView(tester, row);
      await pumpFor(tester, const Duration(milliseconds: 500));
      final Text text = tester.widget<Text>(row);
      expect(text.maxLines, isNull, reason: name);
      expect(
        find
            .descendant(of: find.byType(TallyRow), matching: find.text(name))
            .hitTestable(),
        findsOneWidget,
        reason: '$name is not shown whole',
      );
    }

    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpFor(tester, const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    await screenshot(tester, 'a11y-today-text-2x');
    semantics.dispose();
  });
}
