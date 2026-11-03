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
    await pumpUntil(tester, find.text('1 activities'));
    expect(find.text('Coffee'), findsOneWidget);
    expect(find.text('Tea'), findsOneWidget);
    expect(find.text('Water'), findsOneWidget);
    expect(find.text('0 activities'), findsNWidgets(2));
  });
}
