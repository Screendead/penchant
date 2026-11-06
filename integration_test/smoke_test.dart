import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/manage_data.dart';
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

    await openFromMenu(tester, Homepage.habitsItem);
    await pumpUntil(tester, find.byType(ManageData));
    // Each row's count is its own server request, so the rows fill in any order.
    await pumpUntil(tester, habitsCount('1 entry'));
    await pumpUntilTrue(
      tester,
      () => habitsCount('0 entries').evaluate().length == 2,
      () => "two '0 entries' rows",
    );
    for (final String name in <String>['Coffee', 'Tea', 'Water']) {
      expect(
        find.descendant(of: find.byType(ManageData), matching: find.text(name)),
        findsOneWidget,
      );
    }
  });
}
