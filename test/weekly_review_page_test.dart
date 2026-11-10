import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/insights/what_follows.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/main.dart';
import 'package:tracker/providers/insights_provider.dart';
import 'package:tracker/providers/weekly_review_provider.dart';
import 'package:tracker/weekly_review_page.dart';

import 'weekly_review_fixture.dart';

Future<void> _pump(
  WidgetTester tester, {
  List<ViceActivity>? journal,
  WeeklyInsights? insights,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(600, 3200);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: reviewOverrides(journal: journal, insights: insights),
      child: MaterialApp(
        theme: appTheme(Brightness.light),
        home: const WeeklyReviewPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('the review has its own route', () {
    expect(routePage(WeeklyReviewPage.route), isA<WeeklyReviewPage>());
  });

  testWidgets('shows each total beside its usual week, without judgement', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    expect(find.text('Monday Nov 2 to Sunday Nov 8'), findsOneWidget);
    expect(find.text('Coffee'), findsOneWidget);
    expect(find.text('11 drinks'), findsOneWidget);
    expect(find.text('Usually 10.5 drinks a week'), findsOneWidget);
    for (final String judged in <String>['better', 'worse', 'good', 'bad']) {
      expect(find.textContaining(judged), findsNothing);
    }
  });

  testWidgets('lists the busiest hours and the most common triggers', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    expect(find.text('8:00\u202fAM to 9:00\u202fAM'), findsOneWidget);
    expect(find.text('10:00\u202fPM to 11:00\u202fPM'), findsOneWidget);
    expect(find.text('8:00\u202fPM to 9:00\u202fPM'), findsOneWidget);
    expect(find.text('7 entries'), findsNWidgets(2));
    expect(find.text('with friends'), findsOneWidget);
    expect(find.text('Work › Meeting'), findsOneWidget);
  });

  testWidgets('names findings that started and stopped, and what collects', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final WeeklyInsightsComputed computed =
        reviewInsights as WeeklyInsightsComputed;
    expect(find.text(WeeklyReviewPage.newHeading), findsOneWidget);
    expect(find.text('Alcohol · sleep'), findsOneWidget);
    expect(
      find.text(
        findingSentence(
          computed.changes.started.single.headline,
          'Alcohol',
          formatLocale,
          unit: Unit.drink,
        ),
      ),
      findsOneWidget,
    );
    expect(find.text(WeeklyReviewPage.stoppedHeading), findsOneWidget);
    expect(find.text('Coffee · heart'), findsOneWidget);
    expect(find.text(WeeklyReviewPage.stoppedBody), findsOneWidget);
    expect(find.text(WeeklyReviewPage.holding(1)), findsOneWidget);
    expect(find.text(WeeklyReviewPage.collectingHeading), findsOneWidget);
    expect(find.text('Doomscrolling'), findsNWidgets(2));
    expect(find.textContaining('12 of 21'), findsOneWidget);
  });

  testWidgets('with no change it says so and counts what still holds', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      insights: WeeklyInsightsComputed(
        changes: (
          started: const <InsightCard>[],
          stopped: const <InsightCard>[],
          holding: <InsightCard>[
            InsightCard(
              family: MetricFamily.sleep,
              headline: reviewFinding('alcohol', 'sleepAsleep', -20),
            ),
          ],
        ),
        collecting: const <HabitRefusal>[],
        floors: const <String, double>{},
      ),
    );
    expect(find.text(WeeklyReviewPage.noChange), findsOneWidget);
    expect(find.text(WeeklyReviewPage.holding(1)), findsOneWidget);
    expect(find.text(WeeklyReviewPage.collectingHeading), findsNothing);
  });

  testWidgets('without Health the journal side still shows', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      insights: const WeeklyInsightsUnavailable(HealthNotConnected()),
    );
    expect(find.text('11 drinks'), findsOneWidget);
    expect(find.text(WeeklyReviewPage.needsHealth), findsOneWidget);
    expect(find.text(WeeklyReviewPage.connectInInsights), findsOneWidget);
  });

  testWidgets('on the Mac it points to the iPhone', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      insights: const WeeklyInsightsUnavailable(HealthOnIPhone()),
    );
    expect(find.text(WeeklyReviewPage.onIPhone), findsOneWidget);
  });

  testWidgets('an empty week shows zero totals and no hours', (
    WidgetTester tester,
  ) async {
    await _pump(tester, journal: const <ViceActivity>[]);
    expect(find.text('0 drinks'), findsNWidgets(2));
    expect(find.text(WeeklyReviewPage.nothingLogged), findsOneWidget);
    expect(find.text(WeeklyReviewPage.noTriggers), findsOneWidget);
  });
}
