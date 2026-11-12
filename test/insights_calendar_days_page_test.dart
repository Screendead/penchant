import 'package:flutter/material.dart' hide Interval;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/insights/calendar_days.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/what_follows.dart';
import 'package:tracker/insights_page.dart';
import 'package:tracker/providers/insights_provider.dart';
import 'package:tracker/widgets/after_event_card.dart';

import 'insights_harness.dart';

Future<void> _pump(WidgetTester tester, List<CalendarDay> days) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    healthConnectedKey: true,
  });
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: insightsOverrides(
        health: FakeHealthSource(read: HealthValues(insightsJournal().health)),
        runner: (_) async => InsightsReport(
          findings: const <HabitFinding>[],
          refused: const <HabitRefusal>[],
          calendarDays: days,
        ),
      ),
      child: MaterialApp(
        theme: appTheme(Brightness.light),
        home: const InsightsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a habit used on more of the busy days gets a card under What '
      'sets it off; a refused one does not', (WidgetTester tester) async {
    await _pump(tester, const <CalendarDay>[
      CalendarDay(
        habitId: 'coffee',
        feature: CalendarDayFeature.meetingMinutes,
        cut: 120,
        usableDays: 90,
        moreDays: 40,
        effect: 0.18,
        interval: Interval(0.06, 0.3),
        pValue: 0.001,
      ),
      CalendarDay(
        habitId: 'tea',
        feature: CalendarDayFeature.events,
        cut: 2,
        usableDays: 90,
        moreDays: 40,
        refusal: RefusalReason.withinNoise,
      ),
    ]);

    expect(find.byType(CalendarDayCardView), findsOneWidget);
    expect(
      find.textContaining('On days with over 2 h in meetings, you log '),
      findsOneWidget,
    );
    expect(find.text('Range: 6 to 30 points more often'), findsOneWidget);
    expect(find.text(InsightsPage.setsOffBody), findsNothing);
  });
}
