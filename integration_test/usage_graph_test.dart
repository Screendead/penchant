import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/main.dart';
import 'package:tracker/usage_graph_view.dart';
import 'package:tracker/writes/tracker_writes.dart';

import 'support.dart';

final TrackerWrites _writes = TrackerWrites(FirebaseFirestore.instance);

String get _uid => FirebaseAuth.instance.currentUser!.uid;

Future<void> _pickTimestep(WidgetTester tester, String label) async {
  await tap(tester, find.byType(DropdownButtonFormField<int>).last);
  await tap(tester, find.text(label).last);
  await pumpFor(tester, const Duration(milliseconds: 500));
}

List<double> _totals(WidgetTester tester) => tester
    .widget<LineChart>(find.byType(LineChart))
    .data
    .lineBarsData
    .first
    .spots
    .map((FlSpot spot) => spot.y)
    .toList();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('the graph buckets stored activities by day and by week, '
      'and keeps its smoothing within the weeks shown', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, 'e2e-usage-graph@example.com');

    await _writes.addVice(ownerID: _uid, name: 'Coffee', unit: Unit.drink);
    final String viceID = await storedViceID('Coffee');
    final DateTime today = startOfDay(DateTime.now());
    // Just after midnight, where a day counted in hours would slip a bucket.
    for (final (int daysAgo, int quantity) in const [
      (0, 3),
      (1, 2),
      (10, 4),
      (29, 1),
    ]) {
      await _writes.recordActivity(
        _writes.newActivityID(),
        ownerID: _uid,
        viceID: viceID,
        quantity: quantity,
        createdAt: addDays(today, -daysAgo).add(const Duration(minutes: 30)),
      );
    }

    await tap(tester, find.text('Graph'));
    await pumpUntil(tester, find.byType(LineChart));
    await pumpUntil(
      tester,
      find.bySemanticsLabel(
        'Daily totals of Coffee over the last 30 days: 10 drinks in all. '
        'The most was 4 drinks on '
        '${UsageGraphView.labelFormat.format(addDays(today, -10))}.',
      ),
    );
    final List<double> daily = _totals(tester);
    expect(daily, hasLength(30));
    expect([daily.first, daily[19], daily[28], daily[29]], [1, 4, 2, 3]);

    await tester.drag(find.byType(Slider), const Offset(1000, 0));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('Smoothing: 7 buckets for Coffee'), findsOneWidget);

    // Four whole weeks back from today, then the two days left over, which
    // hold the activity 29 days ago.
    await _pickTimestep(tester, 'Weekly');
    await pumpUntil(
      tester,
      find.bySemanticsLabel(
        'Weekly totals of Coffee over the last 30 days: 10 drinks in all. '
        'The most was 5 drinks in the week of '
        '${UsageGraphView.labelFormat.format(addDays(today, -6))}. '
        'Shown with a 5-week average.',
      ),
    );
    expect(_totals(tester), [1, 0, 0, 4, 5]);
    expect(find.text('Smoothing: 5 buckets for Coffee'), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 5);
    await screenshot(tester, 'usage-graph-weekly');

    await _pickTimestep(tester, 'Daily');
    await pumpUntil(tester, find.text('Smoothing: 7 buckets for Coffee'));
    semantics.dispose();
  });
}
