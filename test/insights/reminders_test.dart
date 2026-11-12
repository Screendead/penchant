import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/insights/health_source.dart' as hs;
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/reminders_source.dart';
import 'package:tracker/insights/what_follows.dart';

import '../fakes.dart';

final DateTime start = DateTime(2026, 1, 5);

DateTime at(int day, [int hour = 12]) =>
    addDays(start, day).add(Duration(hours: hour));

Map<DateTime, double> series(List<hs.DailyOutcome> outcomes, String metric) =>
    <DateTime, double>{
      for (final hs.DailyOutcome o in outcomes)
        if (o.metricId == metric) o.date: o.value,
    };

// One habit on a fair coin's days; on every other day 4 reminders done, give
// or take, and on the day after the habit, when [costs], about 2 fewer.
InsightsInput remindersInput(int seed, {bool costs = true}) {
  final Random random = Random(seed);
  const int days = 150;
  final List<ViceActivity> journal = <ViceActivity>[];
  final List<Reminder> reminders = <Reminder>[];
  bool usedYesterday = false;
  for (int i = 0; i < days; i++) {
    final bool used = random.nextBool();
    if (used) journal.add(fakeActivity('habit1', 1, at(i, 20)));
    final int done = max(
      0,
      4 + random.nextInt(3) - 1 - (costs && usedYesterday ? 2 : 0),
    );
    for (int r = 0; r < done; r++) {
      reminders.add(Reminder(completed: at(i, 9 + r)));
    }
    usedYesterday = used;
  }
  final DateTime today = addDays(start, days);
  return InsightsInput.from(
    activities: journal,
    health: const <hs.DailyOutcome>[],
    today: today,
    reminders: reminderOutcomes(reminders, through: addDays(today, -1)),
  );
}

void main() {
  test('the channel answer reads NaN as an absent time', () {
    final DateTime due = DateTime(2026, 3, 1, 9);
    final DateTime done = DateTime(2026, 3, 1, 17);
    expect(
      remindersFrom(
        Float64List.fromList(<double>[
          due.microsecondsSinceEpoch.toDouble(),
          double.nan,
          double.nan,
          done.microsecondsSinceEpoch.toDouble(),
          double.nan,
          double.nan,
        ]),
      ),
      <Reminder>[Reminder(due: due), Reminder(completed: done)],
    );
  });

  group('reminderOutcomes', () {
    List<Reminder> everyOtherDay(Reminder Function(int day) make) => <Reminder>[
      for (int i = 0; i < minSessionDays; i++) make(3 + 2 * i),
    ];

    test('counts completions on their day, zero between, through the end', () {
      final List<Reminder> reminders = <Reminder>[
        ...everyOtherDay((int d) => Reminder(completed: at(d))),
        Reminder(completed: at(3, 18)),
        // After the last whole day: left out.
        Reminder(completed: at(40)),
      ];
      final Map<DateTime, double> done = series(
        reminderOutcomes(reminders, through: addDays(start, 35)),
        remindersCompletedId,
      );
      expect(done.keys.first, addDays(start, 3));
      expect(done.keys.last, addDays(start, 35));
      expect(done.length, 33);
      expect(done[addDays(start, 3)], 2);
      expect(done[addDays(start, 4)], 0);
      expect(done[addDays(start, 5)], 1);
    });

    test('a reminder is missed on its due day unless done by its end', () {
      final List<Reminder> reminders = <Reminder>[
        // Done the next morning: missed.
        ...everyOtherDay(
          (int d) => Reminder(due: at(d, 9), completed: at(d + 1, 8)),
        ),
        // Never done: missed.
        Reminder(due: at(4, 0)),
        // Done late on its due day: not missed.
        Reminder(due: at(6, 9), completed: at(6, 23)),
        // Due after the last whole day: not yet missed.
        Reminder(due: at(36, 9)),
      ];
      final Map<DateTime, double> missed = series(
        reminderOutcomes(reminders, through: addDays(start, 35)),
        remindersMissedId,
      );
      expect(missed[addDays(start, 3)], 1);
      expect(missed[addDays(start, 4)], 1);
      expect(missed[addDays(start, 6)], 0);
      expect(missed.keys.last, addDays(start, 35));
    });

    test('a series with under minSessionDays days above zero is left out', () {
      final List<Reminder> reminders = <Reminder>[
        for (int i = 0; i < minSessionDays - 1; i++)
          Reminder(completed: at(2 * i)),
      ];
      expect(reminderOutcomes(reminders, through: addDays(start, 60)), isEmpty);
    });
  });

  test('both outcomes carry a floor, a family and copy', () {
    for (final String id in <String>[remindersCompletedId, remindersMissedId]) {
      expect(metricFloors[id]?.family, MetricFamily.reminders, reason: id);
      expect(metricCopy(id), isNotNull, reason: id);
    }
  });

  test('a habit followed by fewer reminders done is found, on its card', () {
    int found = 0;
    for (int seed = 0; seed < 10; seed++) {
      final InsightsReport report = computeInsights(remindersInput(seed));
      expect(report.floors[remindersCompletedId], greaterThanOrEqualTo(1));
      final HabitFinding? use = report.findings
          .where(
            (f) =>
                f.metricId == remindersCompletedId && f.kind == InsightKind.use,
          )
          .firstOrNull;
      if (use == null) continue;
      found++;
      expect(use.effect, inInclusiveRange(-2.5, -1.5));
      final InsightCard card = insightCards(
        report.findings,
        floors: report.floors,
      ).firstWhere((c) => c.headline.metricId == remindersCompletedId);
      expect(card.family, MetricFamily.reminders);
      expect(
        findingSentence(use, 'Wine', 'en'),
        startsWith('On days after Wine, your completed-reminder count '),
      );
    }
    expect(found, greaterThanOrEqualTo(9));
  });

  test('on noise, reminders rarely yield a finding', () {
    int found = 0;
    for (int seed = 0; seed < 20; seed++) {
      final InsightsReport report = computeInsights(
        remindersInput(seed, costs: false),
      );
      found += report.findings
          .where((f) => f.metricId == remindersCompletedId)
          .length;
    }
    expect(found, lessThanOrEqualTo(2));
  });
}
