import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/insights/insights_report.dart';

import 'fakes.dart';
import 'store_journal.dart';

// The store screenshots' Insights shot needs cards, and finding out there
// costs a full simulator build.
void main() {
  for (final DateTime now in <DateTime>[
    DateTime(2026, 11, 10, 9, 5),
    DateTime(2026, 11, 10, 23, 55),
    DateTime(2027, 3, 28, 14),
  ]) {
    test('the store journal yields Coffee and Chocolate cards at $now', () {
      final journal = storeJournal(now);
      final List<ViceActivity> activities = <ViceActivity>[
        for (final StoreEntry e in journal.entries)
          fakeActivity('h${e.habit}', e.quantity, e.at, triggers: e.triggers),
      ];
      final InsightsReport report = computeInsights(
        InsightsInput.from(
          activities: activities,
          health: journal.health,
          today: now,
        ),
      );
      final List<InsightCard> cards = insightCards(
        report.findings,
        floors: report.floors,
      );
      expect(cards.map((InsightCard c) => c.habitId).toSet(), <String>{
        'h0',
        'h2',
      });
      expect(cards.length, greaterThanOrEqualTo(2));
    });
  }
}
