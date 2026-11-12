import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/trigger_amounts.dart';
import 'package:tracker/insights/what_follows.dart';
import 'package:tracker/insights_page.dart';
import 'package:tracker/providers/insights_provider.dart';
import 'package:tracker/widgets/trigger_amounts_card.dart';

import 'insights_harness.dart';

TriggerAmount _trigger(
  String trigger, {
  double withMean = 2.9,
  TriggerVerdict verdict = TriggerVerdict.found,
}) => TriggerAmount(
  trigger: trigger,
  entries: 30,
  withDays: 18,
  withoutDays: 25,
  withMean: withMean,
  withoutMean: 2,
  pValue: 0.001,
  verdict: verdict,
);

Future<void> _pump(WidgetTester tester, List<HabitTriggers> triggers) async {
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
          triggers: triggers,
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
  testWidgets('a trigger whose tagged entries hold more gets a card under '
      'What sets it off, saying only tagged entries were compared', (
    WidgetTester tester,
  ) async {
    await _pump(tester, <HabitTriggers>[
      HabitTriggers(
        habitId: 'coffee',
        entries: 120,
        tagged: 64,
        triggers: <TriggerAmount>[
          _trigger('social/friends'),
          _trigger('work', withMean: 1.4),
          _trigger('Bored', verdict: TriggerVerdict.chance),
        ],
      ),
    ]);

    expect(find.byType(TriggerAmountsCard), findsOneWidget);
    expect(
      find.text(
        'Entries of Coffee you tagged Social › With friends hold 45% more '
        'than your other tagged ones: 2.9 against 2 on average.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Among the 64 entries you tagged, of 120; Social › With friends is '
        'on 30 of them, over 18 days',
      ),
      findsOneWidget,
    );
    expect(find.text('Tagged Work: 30% less'), findsOneWidget);
    expect(find.text(InsightsPage.setsOffBody), findsNothing);
  });

  testWidgets('a trigger that is not a finding shows no card', (
    WidgetTester tester,
  ) async {
    await _pump(tester, <HabitTriggers>[
      HabitTriggers(
        habitId: 'coffee',
        entries: 120,
        tagged: 64,
        triggers: <TriggerAmount>[
          _trigger('work', verdict: TriggerVerdict.tooSmall),
        ],
      ),
    ]);

    expect(find.byType(TriggerAmountsCard), findsNothing);
    expect(find.text(InsightsPage.setsOffBody), findsOneWidget);
  });
}
