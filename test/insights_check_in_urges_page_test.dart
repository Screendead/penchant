import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/insights/check_in_urges.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/what_follows.dart';
import 'package:tracker/insights_page.dart';
import 'package:tracker/providers/insights_provider.dart';
import 'package:tracker/widgets/check_in_urges_card.dart';

import 'insights_harness.dart';

CheckInUrge _urge({RefusalReason? refusal}) => CheckInUrge(
  habitId: 'coffee',
  days: 18,
  entries: 41,
  checkIns: 37,
  noUrge: 15,
  entryMean: 3.6,
  checkInMean: 1.4,
  pValue: 0.0002,
  refusal: refusal,
);

Future<void> _pump(WidgetTester tester, CheckInUrge urge) async {
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
          checkInUrges: <CheckInUrge>[urge],
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
  testWidgets('a habit whose entries carry a stronger urge than random '
      'check-ins gets a card under What sets it off', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _urge());

    expect(find.byType(CheckInUrgesCard), findsOneWidget);
    expect(
      find.text(
        'At entries of Coffee you put the urge at 3.6 of 5 on average, '
        'against 1.4 at random check-ins.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Over 18 days with both: 41 entries with an urge and 37 check-ins, 15 '
        'of them answered 0 and counted as 1, where an entry’s scale starts. '
        'Check-ins ask about any urge at moments picked at random; entries '
        'are moments you chose.',
      ),
      findsOneWidget,
    );
    expect(find.text(InsightsPage.setsOffBody), findsNothing);
  });

  testWidgets('a refused comparison shows no card', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _urge(refusal: RefusalReason.withinNoise));

    expect(find.byType(CheckInUrgesCard), findsNothing);
    expect(find.text(InsightsPage.setsOffBody), findsOneWidget);
  });
}
