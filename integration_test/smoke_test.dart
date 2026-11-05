import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/main.dart' as app;

import 'support.dart';

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await clearEmulators();
  });

  testWidgets('register, add a vice, record an activity, see it listed', (
    WidgetTester tester,
  ) async {
    app.startApp();
    // MyApp is built only once Bootstrap has started Firebase.
    await pumpUntil(tester, find.byType(app.MyApp));
    await register(tester, 'e2e@example.com');
    await addVicesThroughManageData(tester);

    await recordActivity(tester, 'Coffee', 2);
    await expectTallies(tester, const <String>{
      'Coffee (2 drinks)',
      'Tea (0 drinks)',
      'Water (0 drinks)',
    });

    await openFromDrawer(tester, 'Manage Data');
    await pumpUntil(tester, find.text('Your Habits'));
    // Each row's count is its own server request, so the rows fill in any order.
    await pumpUntil(tester, find.text('1 activity'));
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
