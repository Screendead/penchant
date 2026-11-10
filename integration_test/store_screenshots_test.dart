// The App Store screenshots: run alone through tools/e2e-screenshots.sh on an
// iPhone Pro Max simulator, never in all_test.dart, since seeding the journal
// takes a few minutes.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights_page.dart';
import 'package:tracker/providers/insights_provider.dart';
import 'package:tracker/providers/last_night_provider.dart';
import 'package:tracker/widgets/log_fan.dart';
import 'package:tracker/writes/tracker_writes.dart';

import '../test/store_journal.dart';
import 'support.dart';

final TrackerWrites _writes = TrackerWrites(
  FirebaseFirestore.instance,
  sealer: e2eSealer,
);

// The simulator has no Health data, so Insights reads the journal's.
class _StoreHealth implements HealthSource {
  _StoreHealth(this.values);

  final List<DailyOutcome> values;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<HealthRequestStatus> requestStatus() async =>
      HealthRequestStatus.unnecessary;

  @override
  Future<bool> requestAuthorization() async => true;

  @override
  Future<HealthChanges?> changes(Set<HealthMetric> metrics) async =>
      HealthChanges(
        generation: 1,
        whole: <String>{for (final HealthMetric m in metrics) m.id},
      );

  @override
  Future<void> changesHandled(int generation) async {}

  @override
  Future<HealthRead> dailyValues(
    Set<HealthMetric> metrics,
    DateTime start,
    DateTime end,
  ) async => HealthValues(<DailyOutcome>[
    for (final DailyOutcome v in values)
      if (!v.date.isBefore(start) &&
          v.date.isBefore(end) &&
          metrics.any((HealthMetric m) => m.id == v.metricId))
        v,
  ]);

  @override
  Future<HealthSampleRead> samples(
    HealthSampleMetric metric,
    DateTime start,
    DateTime end, {
    int limit = maxHealthSamplesPerCall,
  }) async => const HealthSamples(<HealthSample>[]);

  @override
  Future<HealthChanges?> changes(Set<HealthMetric> metrics) async =>
      HealthChanges(
        generation: 0,
        whole: <String>{for (final HealthMetric m in metrics) m.id},
      );

  @override
  Future<void> changesHandled(int generation) async {}
}

Future<void> _pumpUntilLong(
  WidgetTester tester,
  bool Function() condition,
  String what,
) async {
  final DateTime deadline = DateTime.now().add(const Duration(minutes: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      final String shown = find
          .byType(Text)
          .evaluate()
          .map((Element e) => (e.widget as Text).data)
          .whereType<String>()
          .join(' | ');
      throw TestFailure('Timed out waiting for $what. Text on screen: $shown');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('store screenshots', (WidgetTester tester) async {
    WidgetsApp.debugAllowBannerOverride = false;
    addTearDown(() => WidgetsApp.debugAllowBannerOverride = true);
    final DateTime now = DateTime.now();
    final journal = storeJournal(now);
    await tester.pumpWidget(
      e2eApp(
        overrides: [
          healthSourceProvider.overrideWithValue(_StoreHealth(journal.health)),
          healthConnectedProvider.overrideWith((Ref ref) async => true),
          lastNightProvider.overrideWith((Ref ref) async => storeLastNight),
        ],
      ),
    );
    await register(tester, 'store@example.com');
    final String uid = FirebaseAuth.instance.currentUser!.uid;

    final List<String> viceIDs = <String>[];
    for (final StoreHabit habit in storeHabits) {
      final SentWrite write = _writes.addVice(
        ownerID: uid,
        name: habit.name,
        unit: habit.unit,
        category: habit.category,
      );
      await write.done;
      viceIDs.add(write.id);
    }
    for (int start = 0; start < journal.entries.length; start += 50) {
      await Future.wait(<Future<void>>[
        for (final StoreEntry e in journal.entries.skip(start).take(50))
          _writes
              .recordActivity(
                _writes.newActivityID(),
                ownerID: uid,
                viceID: viceIDs[e.habit],
                quantity: e.quantity,
                createdAt: e.at,
                triggers: e.triggers,
              )
              .done,
      ]);
    }

    // The busiest of the last week, so the dial is full whatever the time.
    int daysBack(StoreEntry e) =>
        startOfDay(now).difference(startOfDay(e.at)).inDays;
    int busiest = 0;
    for (int back = 1; back < 7; back++) {
      int count(int b) =>
          journal.entries.where((StoreEntry e) => daysBack(e) == b).length;
      if (count(back) > count(busiest)) {
        busiest = back;
      }
    }
    for (int back = 0; back < busiest; back++) {
      await tap(tester, find.byTooltip('Previous day'));
      await tester.pump(const Duration(milliseconds: 300));
    }
    await _pumpUntilLong(
      tester,
      () =>
          dialSummary(tester)?.contains(RegExp(r' (First|One) entry')) ?? false,
      'entries on the dial',
    );
    await pumpFor(tester, const Duration(seconds: 3));
    await screenshot(tester, '1-today');

    await openTrends(tester);
    await pumpUntil(tester, find.byType(LineChart));
    await screenshot(tester, '2-trends');
    await closeTrends(tester);

    await openFromMenu(tester, Homepage.insightsItem);
    await _pumpUntilLong(
      tester,
      () =>
          find.text(InsightsPage.costsHeading).evaluate().isNotEmpty &&
          find.text(InsightsPage.loadingLabel).evaluate().isEmpty &&
          find.text(InsightsPage.hoursAfterPending).evaluate().isEmpty,
      'the insight cards',
    );
    expect(
      find.byWidgetPredicate(
        (Widget w) => w.runtimeType.toString() == '_FindingCard',
      ),
      findsWidgets,
    );
    await Scrollable.ensureVisible(
      tester.element(find.text(InsightsPage.lastNightHeading)),
    );
    await screenshot(tester, '3-insights');
    await closeMenuPage(tester);

    await tap(tester, find.byType(LogButton));
    await pumpUntil(tester, fanWedge('Coffee').hitTestable());
    await pumpFor(tester, const Duration(milliseconds: 800));
    await screenshot(tester, '4-log');
  });
}
