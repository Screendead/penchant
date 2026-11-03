import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/main.dart';

import 'support.dart';

// The day header also reads "Today", so the tabs are found by their icons.
final Finder _graphTab = find.byIcon(Icons.show_chart_outlined);
final Finder _todayTab = find.byIcon(Icons.today_outlined);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets("signing out and in as someone else never shows the first "
      "account's data", (WidgetTester tester) async {
    const String second = 'e2e-switch-second@example.com';
    const List<String> firstVices = <String>['Coffee', 'Tea', 'Water'];

    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, second);
    await signOutThroughSettings(tester);

    await register(tester, 'e2e-switch-first@example.com');
    await addVicesThroughManageData(tester, firstVices);
    // The graph opens on the newest vice, so the activity goes on that one
    // for the graph to draw a line.
    await recordActivity(tester, 'Water', 2);
    await expectRadar(tester, <String>{
      'Coffee (0 drinks)',
      'Tea (0 drinks)',
      'Water (2 drinks)',
    });
    // The graph tab stays mounted, so its providers hold the first account's
    // vices too.
    await tap(tester, _graphTab);
    await pumpUntil(tester, find.byType(LineChart));
    await tap(tester, _todayTab);
    await openFromDrawer(tester, 'Manage Data');
    await pumpUntil(tester, find.text('1 activities'));
    await closeDrawerPage(tester);

    await signOutThroughSettings(tester);
    await signIn(tester, second);

    await pumpUntilNeverShowing(
      tester,
      find.textContaining('No vices yet. Add one'),
      firstVices,
    );
    await tap(tester, _graphTab);
    await pumpUntilNeverShowing(
      tester,
      find.text('No vices available to graph'),
      firstVices,
    );
    await tap(tester, _todayTab);
    await openFromDrawer(tester, 'Manage Data');
    await pumpUntilNeverShowing(
      tester,
      find.text('No vices yet. Tap + to add one.'),
      firstVices,
    );
    expect(find.byType(Homepage, skipOffstage: false), findsOneWidget);
  });
}
