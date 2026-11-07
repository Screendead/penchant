import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/main.dart' as app;
import 'package:tracker/onboarding/onboarding.dart';
import 'package:tracker/onboarding/presets.dart';

import 'support.dart';

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await clearEmulators();
  });

  testWidgets('a new account picks two presets and logs one on the way in', (
    WidgetTester tester,
  ) async {
    app.startApp();
    await pumpUntil(tester, find.byType(app.MyApp));
    await register(tester, 'e2e-onboarding@example.com', skipOnboarding: false);

    await pumpUntil(tester, find.text(OnboardingCopy.introHeadline));
    await screenshot(tester, 'onboarding-1-intro');
    await tap(tester, find.text(OnboardingCopy.start));
    await pumpUntil(tester, find.text(OnboardingCopy.question));
    await tap(tester, find.text('Coffee'));
    await tap(tester, find.text('Vape'));
    await screenshot(tester, 'onboarding-2-picker');
    await tap(tester, find.text(OnboardingCopy.continueWith(2)));

    await pumpUntil(tester, find.text(OnboardingCopy.disclaimer));
    await tap(tester, find.text(OnboardingCopy.acknowledge));

    await pumpUntil(tester, find.text(OnboardingCopy.firstLogTitle));
    await pumpUntil(tester, find.byTooltip('More Coffee'));
    await tap(tester, find.byTooltip('More Coffee'));
    await tap(tester, find.byKey(Onboarding.logKey('Coffee')));
    await pumpUntil(tester, find.text(OnboardingCopy.logged));
    await screenshot(tester, 'onboarding-4-first-log');
    await tap(tester, find.text(OnboardingCopy.toToday));

    await pumpUntil(tester, find.byType(Onboarding), present: false);
    await expectTallies(tester, const <String>{
      'Coffee (2 drinks)',
      'Vape (0 puffs)',
    });
    expect(await storedViceID('Vape'), isNotEmpty);
    expect((await storedActivities('Coffee')).single.data()['quantity'], 2);
  });
}
