import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tracker/main.dart' as app;

import 'support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  setUpAll(() async {
    requireEmulators();
    await clearEmulators();
  });

  testWidgets('register, add a vice, record an activity, see it listed', (
    WidgetTester tester,
  ) async {
    await app.main();
    await register(tester, 'e2e@example.com');
    await addVicesThroughManageData(tester);

    await recordActivity(tester, 'Coffee', 2);
    await pumpUntil(tester, find.byType(RadarChart));

    await openFromDrawer(tester, 'Manage Data');
    await pumpUntil(tester, find.text('Your Vices'));
    // Each row's count is its own server request, so the rows fill in any order.
    await pumpUntil(tester, find.text('1 activities'));
    await pumpUntilTrue(
      tester,
      () => find.text('0 activities').evaluate().length == 2,
      () => "two '0 activities' rows",
    );
    expect(find.text('Coffee'), findsOneWidget);
    expect(find.text('Tea'), findsOneWidget);
    expect(find.text('Water'), findsOneWidget);
  });
}
