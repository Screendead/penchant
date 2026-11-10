import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/trends/trends_sheet.dart';
import 'package:tracker/writes/tracker_writes.dart';

import 'support.dart';

final TrackerWrites _writes = TrackerWrites(
  FirebaseFirestore.instance,
  sealer: e2eSealer,
);

String get _uid => FirebaseAuth.instance.currentUser!.uid;

List<double> _totals(WidgetTester tester) => tester
    .widget<LineChart>(find.byType(LineChart))
    .data
    .lineBarsData
    .first
    .spots
    .map((FlSpot spot) => spot.y)
    .toList();

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('Trends buckets stored activities by day over its range', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(e2eApp());
    await register(tester, 'e2e-trends@example.com');

    await _writes.addVice(ownerID: _uid, name: 'Coffee', unit: Unit.drink).done;
    final String viceID = await storedViceID('Coffee');
    final DateTime today = startOfDay(DateTime.now());
    // Just after midnight, where a day counted in hours would slip a bucket.
    for (final (int daysAgo, int quantity) in const [
      (0, 3),
      (1, 2),
      (10, 4),
      (29, 1),
    ]) {
      await _writes
          .recordActivity(
            _writes.newActivityID(),
            ownerID: _uid,
            viceID: viceID,
            quantity: quantity,
            createdAt: addDays(
              today,
              -daysAgo,
            ).add(const Duration(minutes: 30)),
          )
          .done;
    }

    // The peek reads the same range before the sheet opens; the split
    // view's pane has no peek.
    await pumpUntil(tester, find.byType(TrendsSheet));
    final bool split = splitLayout(tester);
    if (!split) {
      await pumpUntil(tester, find.text('Coffee · last 30 days'));
      await pumpUntil(tester, find.text(formatAverage(10 / 30)));
      await screenshot(tester, 'trends-peek');
    }

    await openTrends(tester);
    await pumpUntil(tester, find.byType(LineChart));
    await pumpUntil(
      tester,
      find.bySemanticsLabel(
        'Daily totals of Coffee over the last 30 days: 10 drinks in all. '
        'The most was 4 drinks on '
        '${formatShortDay(addDays(today, -10))}. '
        'Shown with a 7-day average.',
      ),
    );
    final List<double> daily = _totals(tester);
    expect(daily, hasLength(30));
    expect([daily.first, daily[19], daily[28], daily[29]], [1, 4, 2, 3]);
    expect(find.text('Average over 7 days'), findsOneWidget);
    expect(find.textContaining('of it before noon'), findsOneWidget);
    await screenshot(tester, 'trends-daily');

    await closeTrends(tester);
    expect(find.byType(LineChart), split ? findsOneWidget : findsNothing);
    semantics.dispose();
  });
}
