import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/main.dart';
import 'package:tracker/manage_data.dart';
import 'package:tracker/trends/trends_chart.dart';
import 'package:tracker/trends/trends_sheet.dart';
import 'package:tracker/widgets/pill_toggle.dart';
import 'package:tracker/widgets/log_fan.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';

import 'support.dart';

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('an archived vice leaves recording and Today, and keeps its '
      'history in Manage Data and in Trends', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, 'e2e-archive@example.com');
    await addVicesThroughManageData(tester, <String>[
      'Coffee',
      'Tea',
      'Water',
      'Juice',
    ]);
    await recordActivity(tester, 'Juice', 2);
    // Without an entry for a vice still in use, the day would read as clean
    // once Juice is archived, and show no radar.
    await recordActivity(tester, 'Coffee', 1);
    await expectTallies(tester, <String>{
      'Coffee (1 drink)',
      'Tea (0 drinks)',
      'Water (0 drinks)',
      'Juice (2 drinks)',
    });

    await openFromMenu(tester, Homepage.habitsItem);
    await pumpUntil(tester, find.byType(ManageData));
    final Finder juiceRow = find
        .ancestor(of: find.text('Juice'), matching: find.byType(InkWell))
        .first;
    await tap(
      tester,
      find.descendant(of: juiceRow, matching: find.byTooltip('Archive')),
    );
    await pumpUntil(tester, find.text(ManageData.archivedLabel));
    await pumpUntil(
      tester,
      find.descendant(
        of: find
            .ancestor(of: find.text('Juice'), matching: find.byType(InkWell))
            .first,
        matching: find.byTooltip('Unarchive'),
      ),
    );

    await tap(tester, find.text('Juice'));
    await pumpUntilRouteSettled(tester, historyTitle('Juice'));
    await pumpUntil(tester, historyEntry(2));
    await tap(tester, find.byTooltip('Back'));
    await pumpUntil(tester, historyTitle('Juice'), present: false);
    await pumpUntilRouteSettled(tester, find.byType(ManageData));
    await closeMenuPage(tester);

    await expectTallies(tester, <String>{
      'Coffee (1 drink)',
      'Tea (0 drinks)',
      'Water (0 drinks)',
    });

    // The fan offers no wedge for an archived habit.
    await tap(tester, find.byType(LogButton));
    await pumpFor(tester, const Duration(milliseconds: 800));
    expect(fanWedge('Water'), findsOneWidget);
    expect(fanWedge('Juice'), findsNothing);
    await tester.longPress(fanWedge('Water'));
    final Finder dialog = find.byType(RecordNewActivityDialog);
    await pumpUntil(tester, dialog);
    await tap(
      tester,
      find.descendant(
        of: dialog,
        matching: find.byType(DropdownButtonFormField<String>),
      ),
    );
    await pumpUntil(tester, find.text('Coffee'));
    // The menu fades in; read it once it is up.
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('Water'), findsWidgets);
    expect(find.text('Juice'), findsNothing);
    await tap(tester, find.text('Coffee').last);
    await tap(
      tester,
      find.descendant(of: dialog, matching: find.text('Cancel')),
    );
    await pumpUntil(tester, dialog, present: false);

    // Trends lists the habits in use first, so the archived Juice is never
    // the default, though it was the newest.
    await openTrends(tester);
    // The chart gives way to a spinner while a habit's range loads.
    String? graphed() => find.byType(TrendsChart).evaluate().isEmpty
        ? null
        : tester.widget<TrendsChart>(find.byType(TrendsChart)).vice.name;
    await pumpUntil(tester, find.byType(TrendsChart));
    expect(graphed(), 'Coffee');
    // The chips come first among the sheet's toggles, before the segments.
    expect(
      tester
          .widgetList<PillToggle>(find.byType(PillToggle))
          .take(4)
          .map((PillToggle chip) => chip.semanticsLabel),
      <String>['Coffee', 'Tea', 'Water', 'Juice, archived'],
    );
    await tap(
      tester,
      find.descendant(
        of: find.byType(TrendsSheet),
        matching: find.text('Juice'),
      ),
    );
    await pumpUntilTrue(
      tester,
      () => graphed() == 'Juice',
      () => 'Trends to show Juice',
    );
    await closeTrends(tester);
  });
}
