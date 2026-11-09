import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/onboarding/presets.dart';
import 'package:tracker/trends/trends_sheet.dart';

import 'support.dart';

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets("signing out and in as someone else never shows the first "
      "account's data", (WidgetTester tester) async {
    const String second = 'e2e-switch-second@example.com';
    const List<String> firstVices = <String>['Coffee', 'Tea', 'Water'];

    await tester.pumpWidget(e2eApp());
    await register(tester, second);
    await signOutThroughSettings(tester);

    await register(tester, 'e2e-switch-first@example.com');
    await addVicesThroughManageData(tester, firstVices);
    // Trends opens on the oldest habit, so the activity goes on that one for
    // its chart to draw a line.
    await recordActivity(tester, 'Coffee', 2);
    await expectTallies(tester, <String>{
      'Coffee (2 drinks)',
      'Tea (0 drinks)',
      'Water (0 drinks)',
    });
    // Opening Trends loads the first account's range too.
    await openTrends(tester);
    await pumpUntil(tester, find.byType(LineChart));
    await closeTrends(tester);
    await openFromMenu(tester, Homepage.habitsItem);
    await pumpUntil(tester, habitsCount('1 entry'));
    await closeMenuPage(tester);

    await signOutThroughSettings(tester);
    await signIn(tester, second);

    // The second account has no habits, so it starts on the onboarding.
    await pumpUntilNeverShowing(
      tester,
      find.text(OnboardingCopy.introHeadline),
      firstVices,
    );
    await skipTheOnboarding(tester);
    await pumpUntilNeverShowing(
      tester,
      find.textContaining('No habits yet. Add one'),
      firstVices,
    );
    // With no habits there is no Trends sheet to carry the first account's.
    expect(find.byType(TrendsSheet), findsNothing);
    await openFromMenu(tester, Homepage.habitsItem);
    await pumpUntilNeverShowing(
      tester,
      find.text('No habits yet. Tap + to add one.'),
      firstVices,
    );
    expect(find.byType(Homepage, skipOffstage: false), findsOneWidget);
  });
}
