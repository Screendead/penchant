import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/main.dart';
import 'package:tracker/manage_data.dart';
import 'package:tracker/usage_graph_view.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';

import 'support.dart';

final Finder _graphTab = find.byIcon(Icons.show_chart_outlined);

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('an archived vice leaves recording and Today, and keeps its '
      'history in Manage Data and on the Graph', (WidgetTester tester) async {
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
    await expectRadar(tester, <String>{
      'Coffee (1 drink)',
      'Tea (0 drinks)',
      'Water (0 drinks)',
      'Juice (2 drinks)',
    });

    await openFromDrawer(tester, 'Manage Data');
    await pumpUntil(tester, find.text('Your Vices'));
    final Finder juiceRow = find.ancestor(
      of: find.text('Juice'),
      matching: find.byType(ListTile),
    );
    await tap(
      tester,
      find.descendant(of: juiceRow, matching: find.byTooltip('Archive')),
    );
    await pumpUntil(
      tester,
      find.text('${ManageData.archivedLabel}, 1 activity'),
    );

    await tap(tester, find.text('Juice'));
    await pumpUntilRouteSettled(tester, find.text('Juice history'));
    await pumpUntil(tester, find.text('Quantity: 2'));
    await tap(tester, find.byType(BackButton));
    await pumpUntil(tester, find.text('Juice history'), present: false);
    await pumpUntilRouteSettled(tester, find.text('Your Vices'));
    await closeDrawerPage(tester);

    await expectRadar(tester, <String>{
      'Coffee (1 drink)',
      'Tea (0 drinks)',
      'Water (0 drinks)',
    });

    await tap(tester, find.widgetWithText(TextButton, 'Record'));
    final Finder dialog = find.byType(RecordNewActivityDialog);
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

    // Vices list newest first, so Juice would be the default if archived
    // vices were not listed after the rest.
    await tap(tester, _graphTab);
    await pumpUntil(tester, find.text('Smoothing: 1 bucket for Water'));
    await tap(
      tester,
      find.descendant(
        of: find.byType(UsageGraphView),
        matching: find.byType(DropdownButtonFormField<String>),
      ),
    );
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tap(tester, find.text('Juice (archived)').last);
    await pumpUntil(tester, find.text('Smoothing: 1 bucket for Juice'));
    await pumpUntil(tester, find.byType(LineChart));
  });
}
