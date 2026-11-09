import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/trends/trends_day.dart';
import 'package:tracker/trends/trends_sheet.dart';
import 'package:tracker/writes/tracker_writes.dart';

import 'support.dart';

final TrackerWrites _writes = TrackerWrites(FirebaseFirestore.instance);

String get _uid => FirebaseAuth.instance.currentUser!.uid;

Finder _inTrends(Finder finder) =>
    find.descendant(of: find.byType(TrendsSheet), matching: finder);

// The sheet scrolls in a short window (macOS), so each control is brought
// into view before it is used.
Future<void> _use(WidgetTester tester, Finder finder) async {
  await scrollIntoView(tester, finder);
  await tap(tester, finder);
}

Future<void> _pick(WidgetTester tester, String label) async {
  await _use(tester, _inTrends(find.text(label)));
  await pumpFor(tester, const Duration(milliseconds: 600));
}

Vice _coffee(WidgetTester tester) =>
    tester.widget<TrendsDay>(find.byType(TrendsDay)).vice;

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

  testWidgets('Trends buckets stored activities by day and by week, keeps '
      'its average within the weeks shown, and opens a day', (
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

    // Four whole weeks back from today; the 30-day range rounds down to 28,
    // which leaves out the activity 29 days ago.
    await _pick(tester, 'Week');
    await pumpUntil(
      tester,
      find.bySemanticsLabel(
        'Weekly totals of Coffee over the last 28 days: 9 drinks in all. '
        'The most was 5 drinks in the week of '
        '${formatShortDay(addDays(today, -6))}. '
        'Shown with a 4-week average.',
      ),
    );
    // The chart tweens from the daily spots to the weekly ones.
    await pumpUntilTrue(
      tester,
      () => listEquals(_totals(tester), [0, 0, 4, 5]),
      () => 'weekly totals ${_totals(tester)}',
    );
    expect(find.text('Average over 4 weeks'), findsOneWidget);
    // Four buckets hold no longer average.
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip(TrendsSheet.longerAverage),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await screenshot(tester, 'trends-weekly');

    // Day restarts at a week's average. In the sheet a tap on today opens
    // its dial; the pane hands the day to Today's dial (split_view_test).
    await _pick(tester, 'Day');
    await pumpUntil(tester, find.text('Average over 7 days'));
    if (!split) {
      await scrollIntoView(tester, find.byType(LineChart));
      final Rect chart = tester.getRect(find.byType(LineChart));
      await tester.tapAt(Offset(chart.right - 2, chart.center.dy));
      await pumpUntil(tester, find.byType(TrendsDay));
      await pumpUntil(
        tester,
        find.text(TrendsDay.subtitle(1, _coffee(tester), 3)),
      );
      await pumpFor(tester, const Duration(milliseconds: 800));
      await screenshot(tester, 'trends-day');
      await _use(tester, find.byTooltip(TrendsDay.backLabel));
      await pumpUntil(tester, find.byType(LineChart));
    }

    await closeTrends(tester);
    expect(find.byType(LineChart), split ? findsOneWidget : findsNothing);
    semantics.dispose();
  });
}
