import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights_page.dart';
import 'package:tracker/providers/insights_provider.dart';

import 'insights_harness.dart';

Future<void> _pump(WidgetTester tester, List<Override> overrides) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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

void _prefs({bool connected = true, int? askedVersion}) =>
    SharedPreferences.setMockInitialValues(<String, Object>{
      healthConnectedKey: connected,
      healthAskedVersionKey: ?askedVersion,
    });

FakeHealthSource _health(HealthRequestStatus status) => FakeHealthSource(
  read: HealthValues(insightsJournal().health),
  status: status,
);

void main() {
  testWidgets('connected before a new read type: the card offers the sheet '
      'and does not show it unasked', (WidgetTester tester) async {
    _prefs();
    final FakeHealthSource health = _health(HealthRequestStatus.shouldRequest);
    await _pump(tester, insightsOverrides(health: health));

    expect(find.text(InsightsPage.askAgainLabel), findsOneWidget);
    expect(find.text(InsightsPage.askAgainBody), findsOneWidget);
    expect(find.text('Connected'), findsNothing);
    expect(find.text(InsightsPage.manageBody), findsOneWidget);
    expect(health.authorizationRequests, 0);
  });

  testWidgets('tapping it shows the sheet, records the types asked for and '
      'reads Health again', (WidgetTester tester) async {
    _prefs();
    final FakeHealthSource health = _health(HealthRequestStatus.shouldRequest);
    await _pump(tester, insightsOverrides(health: health));
    final int reads = health.reads;

    await tester.tap(find.text(InsightsPage.askAgainLabel));
    await tester.pumpAndSettle();

    expect(health.authorizationRequests, 1);
    expect(health.reads, reads + insightsHealthCalls);
    expect(find.text(InsightsPage.askAgainLabel), findsNothing);
    expect(find.text('Connected'), findsOneWidget);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(healthAskedVersionKey), healthReadTypesVersion);
  });

  testWidgets('connected and current: Connected, with where to manage access', (
    WidgetTester tester,
  ) async {
    _prefs(askedVersion: healthReadTypesVersion);
    final FakeHealthSource health = _health(HealthRequestStatus.unnecessary);
    await _pump(tester, insightsOverrides(health: health));

    expect(find.text('Connected'), findsOneWidget);
    expect(find.text(InsightsPage.askAgainLabel), findsNothing);
    expect(find.text(InsightsPage.manageLabel), findsOneWidget);
    expect(find.text(InsightsPage.manageBody), findsOneWidget);
    expect(health.authorizationRequests, 0);
  });

  testWidgets('when HealthKit cannot tell, a device that never recorded the '
      'types it asked for is offered the sheet', (WidgetTester tester) async {
    _prefs();
    await _pump(
      tester,
      insightsOverrides(health: _health(HealthRequestStatus.unknown)),
    );

    expect(find.text(InsightsPage.askAgainLabel), findsOneWidget);
  });

  testWidgets('when HealthKit cannot tell, the current version recorded means '
      'Connected', (WidgetTester tester) async {
    _prefs(askedVersion: healthReadTypesVersion);
    await _pump(
      tester,
      insightsOverrides(health: _health(HealthRequestStatus.unknown)),
    );

    expect(find.text(InsightsPage.askAgainLabel), findsNothing);
    expect(find.text('Connected'), findsOneWidget);
  });

  testWidgets('never connected: Connect, and no manage hint', (
    WidgetTester tester,
  ) async {
    _prefs(connected: false);
    final FakeHealthSource health = _health(HealthRequestStatus.shouldRequest);
    await _pump(tester, insightsOverrides(health: health));

    expect(find.text(InsightsPage.connectLabel), findsOneWidget);
    expect(find.text(InsightsPage.askAgainLabel), findsNothing);
    expect(find.text(InsightsPage.manageLabel), findsNothing);
  });

  testWidgets('on macOS nothing changes: Health is on the iPhone and HealthKit '
      'is not asked', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    _prefs();
    final FakeHealthSource health = _health(HealthRequestStatus.shouldRequest);
    await _pump(tester, insightsOverrides(health: health));

    expect(find.text(InsightsPage.onIPhone), findsOneWidget);
    expect(find.text(InsightsPage.askAgainLabel), findsNothing);
    expect(find.text(InsightsPage.manageLabel), findsNothing);
    expect(health.statusChecks, 0);
    expect(health.authorizationRequests, 0);
    debugDefaultTargetPlatformOverride = null;
  });
}
