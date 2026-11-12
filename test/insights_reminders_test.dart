import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/insights/calendar_source.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights_page.dart';
import 'package:tracker/insights/reminders_source.dart';
import 'package:tracker/providers/insights_provider.dart';
import 'package:tracker/providers/reminders_provider.dart';

import 'insights_harness.dart';

class _FakeReminders implements RemindersSource {
  _FakeReminders(this.state);

  CalendarAccess state;
  int asked = 0;
  int reads = 0;

  @override
  Future<CalendarAccess> access() async => state;

  @override
  Future<bool> requestAccess() async {
    asked++;
    state = CalendarAccess.full;
    return state == CalendarAccess.full;
  }

  @override
  Future<List<Reminder>> reminders() async {
    reads++;
    return const <Reminder>[];
  }
}

Future<void> _pump(
  WidgetTester tester,
  _FakeReminders reminders, {
  void Function()? onRun,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    healthConnectedKey: true,
  });
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        ...insightsOverrides(
          health: FakeHealthSource(
            read: HealthValues(insightsJournal().health),
          ),
          runner: (InsightsInput input) async {
            onRun?.call();
            return computeInsights(input);
          },
        ),
        remindersSourceProvider.overrideWithValue(reminders),
      ],
      child: MaterialApp(
        theme: appTheme(Brightness.light),
        home: const InsightsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Reminders are asked for only on a tap, then read', (
    WidgetTester tester,
  ) async {
    final _FakeReminders reminders = _FakeReminders(
      CalendarAccess.notDetermined,
    );
    await _pump(tester, reminders);

    expect(find.text(InsightsPage.remindersLabel), findsOneWidget);
    expect(reminders.asked, 0);
    expect(reminders.reads, 0);

    await tester.tap(find.text(InsightsPage.remindersLabel));
    await tester.pumpAndSettle();

    expect(reminders.asked, 1);
    expect(find.text(InsightsPage.remindersLabel), findsNothing);
    expect(reminders.reads, greaterThan(0));
  });

  testWidgets('refused access says where to allow it', (
    WidgetTester tester,
  ) async {
    final _FakeReminders reminders = _FakeReminders(CalendarAccess.denied);
    await _pump(tester, reminders);

    expect(find.text(InsightsPage.remindersLabel), findsNothing);
    expect(find.text(InsightsPage.remindersOffBody), findsOneWidget);
    expect(reminders.reads, 0);
  });

  testWidgets('with access, coming back to the app reads nothing again', (
    WidgetTester tester,
  ) async {
    final _FakeReminders reminders = _FakeReminders(CalendarAccess.full);
    int runs = 0;
    await _pump(tester, reminders, onRun: () => runs++);
    final int reads = reminders.reads, before = runs;
    expect(reads, greaterThan(0));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(reminders.reads, reads);
    expect(runs, before);
  });
}
