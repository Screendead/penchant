import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/measure_shifts.dart';
import 'package:tracker/insights/step_changes.dart';
import 'package:tracker/insights/what_follows.dart';
import 'package:tracker/insights_page.dart';
import 'package:tracker/providers/insights_provider.dart';
import 'package:tracker/widgets/measure_shift_card.dart';
import 'package:tracker/widgets/not_yet_box.dart';

import 'insights_harness.dart';

final DateTime _at = DateTime(2026, 3, 12);

MeasureShift _shift({List<HabitChange> habits = const <HabitChange>[]}) =>
    MeasureShift(
      metricId: 'restingHeartRate',
      shift: LevelShift(
        at: _at,
        before: 58,
        after: 64,
        daysBefore: 43,
        daysAfter: 60,
        pValue: 0.0001,
      ),
      habits: habits,
      found: true,
    );

Future<void> _pump(WidgetTester tester, List<MeasureShift> shifts) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    healthConnectedKey: true,
  });
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final List<Override> overrides = insightsOverrides(
    health: FakeHealthSource(read: HealthValues(insightsJournal().health)),
    runner: (_) async => InsightsReport(
      findings: const <HabitFinding>[],
      refused: const <HabitRefusal>[],
      shifts: shifts,
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: appTheme(Brightness.light),
        home: const InsightsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final String sentence =
      'From ${formatDate(_at)}, your resting heart rate averaged 6.0 bpm '
      'higher than before.';
  const String basis =
      '58.0 bpm over the 43 days before, 64.0 bpm over the 60 days from then';
  const String coffee =
      'Coffee changed around then too, from 1.5 a day to 3.5, so the two '
      'can’t be told apart.';
  const List<HabitChange> changes = <HabitChange>[
    HabitChange(habitId: 'coffee', before: 1.5, after: 3.5),
    HabitChange(habitId: 'gone', before: 0, after: 2),
  ];

  testWidgets('a measure that moved to a new level waits behind What it '
      'costs\'s More, counted there, and its card names the habit that '
      'changed with it', (WidgetTester tester) async {
    await _pump(tester, <MeasureShift>[_shift(habits: changes)]);

    expect(find.byType(MeasureShiftCard), findsNothing);
    expect(find.text(InsightsPage.shiftsHeading), findsNothing);
    expect(find.text(InsightsPage.shiftsNote), findsNothing);
    expect(find.text(InsightsPage.more(1)), findsOneWidget);

    await tester.tap(find.text(InsightsPage.moreCosts));
    await tester.pumpAndSettle();

    expect(find.byType(InsightsCostsPage), findsOneWidget);
    expect(find.byType(MeasureShiftCard), findsOneWidget);
    expect(find.text(InsightsPage.shiftsHeading), findsOneWidget);
    expect(find.text(sentence), findsOneWidget);
    expect(find.text(basis), findsOneWidget);
    expect(find.text(coffee), findsOneWidget);
    expect(find.textContaining('a removed habit'), findsNothing);
    expect(find.text(InsightsPage.shiftsNote), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(MeasureShiftCard)).dy,
      greaterThan(tester.getTopLeft(find.byType(NotYetBox)).dy),
    );
  });

  testWidgets('with no shift neither page has the cards', (
    WidgetTester tester,
  ) async {
    await _pump(tester, const <MeasureShift>[]);

    expect(find.text(InsightsPage.more(1)), findsNothing);
    await tester.tap(find.text(InsightsPage.moreCosts));
    await tester.pumpAndSettle();

    expect(find.byType(MeasureShiftCard), findsNothing);
    expect(find.text(InsightsPage.shiftsHeading), findsNothing);
    expect(find.text(InsightsPage.shiftsNote), findsNothing);
  });

  testWidgets('Copy as text carries the card at the foot of What it costs', (
    WidgetTester tester,
  ) async {
    final List<String?> copied = <String?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(
            (call.arguments as Map<Object?, Object?>)['text'] as String?,
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pump(tester, <MeasureShift>[_shift(habits: changes)]);

    await tester.tap(find.text(InsightsPage.copyLabel));
    await tester.pump();

    final String text = copied.single!;
    const String block =
        '\n${InsightsPage.shiftsHeading}\n\n';
    expect(
      text,
      contains(
        '$block$sentence\n$basis\n$coffee\n'
        '\n${InsightsPage.shiftsNote}\n',
      ),
    );
    expect(text.indexOf(block), greaterThan(text.indexOf(InsightsPage.costsHeading)));
    expect(text.indexOf(block), lessThan(text.indexOf(InsightsPage.foot)));
  });

  test('the engine says nothing of an archived habit beside a shift', () {
    final InsightsReport report = computeInsights(
      InsightsInput.from(
        activities: insightsJournal().activities,
        health: insightsJournal().health,
        today: insightsToday,
        archived: const <String>{'tea'},
      ),
    );

    for (final MeasureShift s in report.shifts) {
      expect(s.found, isTrue);
      expect(
        s.habits.map((HabitChange c) => c.habitId),
        isNot(contains('tea')),
      );
    }
  });
}
