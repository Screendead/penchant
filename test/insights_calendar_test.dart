import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/insights/after_event.dart';
import 'package:tracker/insights/calendar_source.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights_page.dart';
import 'package:tracker/providers/calendar_provider.dart';
import 'package:tracker/providers/insights_provider.dart';

import 'insights_harness.dart';

class _FakeCalendar implements CalendarSource {
  _FakeCalendar(this.state);

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
  Future<List<CalendarEvent>> events(DateTime start, DateTime end) async {
    reads++;
    return const <CalendarEvent>[];
  }
}

Future<void> _pump(
  WidgetTester tester,
  _FakeCalendar calendar, {
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
        calendarSourceProvider.overrideWithValue(calendar),
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
  testWidgets('the calendar is asked for only on a tap, then read', (
    WidgetTester tester,
  ) async {
    final _FakeCalendar calendar = _FakeCalendar(CalendarAccess.notDetermined);
    await _pump(tester, calendar);

    expect(find.text(InsightsPage.calendarLabel), findsOneWidget);
    expect(calendar.asked, 0);
    expect(calendar.reads, 0);

    await tester.tap(find.text(InsightsPage.calendarLabel));
    await tester.pumpAndSettle();

    expect(calendar.asked, 1);
    expect(find.text(InsightsPage.calendarLabel), findsNothing);
    expect(calendar.reads, greaterThan(0));
  });

  testWidgets('refused or add-only access says where to allow it', (
    WidgetTester tester,
  ) async {
    final _FakeCalendar calendar = _FakeCalendar(CalendarAccess.writeOnly);
    await _pump(tester, calendar);

    expect(find.text(InsightsPage.calendarLabel), findsNothing);
    expect(find.text(InsightsPage.calendarOffBody), findsOneWidget);
    expect(calendar.reads, 0);
  });

  testWidgets('with access, coming back to the app reads nothing again', (
    WidgetTester tester,
  ) async {
    final _FakeCalendar calendar = _FakeCalendar(CalendarAccess.full);
    int runs = 0;
    await _pump(tester, calendar, onRun: () => runs++);
    final int reads = calendar.reads, before = runs;
    expect(reads, greaterThan(0));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(calendar.reads, reads);
    expect(runs, before);
  });
}
