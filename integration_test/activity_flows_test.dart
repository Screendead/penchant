import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/widgets/day_dial.dart';

import 'support.dart';

final Finder _back = find.byTooltip('Previous day');

DateTime _shownDay(WidgetTester tester) =>
    tester.widget<DayDial>(find.byType(DayDial)).day;

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('an entry logged on a past day shows on that day alone', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(e2eApp());
    await register(tester, 'e2e-bars@example.com');
    await addVicesThroughManageData(tester, const <String>['Coffee']);

    final DateTime today = startOfDay(DateTime.now());
    await recordActivity(
      tester,
      'Coffee',
      3,
      at: addDays(today, -1).add(const Duration(hours: 12)),
    );

    await tap(tester, _back);
    expect(_shownDay(tester), addDays(today, -1));
    await expectTallies(tester, const <String>{'Coffee (3 drinks)'});
    await tap(tester, _back);
    await pumpUntil(tester, find.text(ClearDay.headline));
  });
}
