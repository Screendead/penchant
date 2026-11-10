import 'dart:math';

import 'package:tracker/data/category.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/last_night.dart';

typedef StoreHabit = ({String name, Unit unit, ViceCategory category});

typedef StoreEntry = ({
  int habit,
  int quantity,
  DateTime at,
  List<String> triggers,
});

/// Oldest first, the order their colours follow. Neutral habits and round
/// amounts, so the listing reads as illustrative (App Review 1.4.3).
const List<StoreHabit> storeHabits = <StoreHabit>[
  (name: 'Coffee', unit: Unit.drink, category: ViceCategory.caffeine),
  (name: 'Tea', unit: Unit.drink, category: ViceCategory.caffeine),
  (name: 'Chocolate', unit: Unit.item, category: ViceCategory.food),
  (name: 'Fizzy drink', unit: Unit.drink, category: ViceCategory.other),
];

const int storeJournalDays = 120;

/// The last night shown on Insights, against the usual the Health data gives.
const LastNight storeLastNight = LastNight(
  sleepingHeartRate: NightCompare(value: 61, usual: 57, low: 56, high: 58),
  heartRateVariability: NightCompare(value: 38, usual: 46, low: 43, high: 49),
  asleep: NightCompare(value: 395, usual: 430, low: 415, high: 445),
);

/// [storeJournalDays] of entries up to [now], and the Health values that
/// follow them: the night after a Coffee day has less deep sleep and the next
/// day a higher resting heart rate, more so the more cups; a Chocolate
/// evening costs some sleep. Nothing follows Tea or Fizzy drink.
({List<StoreEntry> entries, List<DailyOutcome> health}) storeJournal(
  DateTime now, {
  int seed = 14,
}) {
  final Random random = Random(seed);
  double noise(double spread) =>
      (random.nextDouble() + random.nextDouble() - 1) * spread;
  DateTime at(DateTime day, int fromMinute, int toMinute) => day.add(
    Duration(
      minutes: fromMinute + 5 * random.nextInt((toMinute - fromMinute) ~/ 5),
    ),
  );
  final DateTime today = startOfDay(now);
  final List<StoreEntry> entries = <StoreEntry>[];
  final List<DailyOutcome> health = <DailyOutcome>[];
  int coffeeBefore = 0;
  bool chocolateBefore = false;
  for (int back = storeJournalDays; back >= 0; back--) {
    final DateTime day = addDays(today, -back);
    health
      ..add(
        DailyOutcome(
          day,
          HealthMetric.sleepDeep.id,
          72 + noise(10) - (coffeeBefore == 0 ? 0 : 12 + 5 * coffeeBefore),
        ),
      )
      ..add(
        DailyOutcome(
          day,
          HealthMetric.sleepAsleep.id,
          435 + noise(30) - (chocolateBefore ? 30 : 0),
        ),
      )
      ..add(
        DailyOutcome(
          day,
          HealthMetric.restingHeartRate.id,
          56 + noise(1.5) + (coffeeBefore == 0 ? 0 : 3 + 1.5 * coffeeBefore),
        ),
      );
    final List<StoreEntry> dayEntries = <StoreEntry>[];
    void add(int habit, int quantity, DateTime time, List<String> triggers) {
      dayEntries.add((
        habit: habit,
        quantity: quantity,
        at: time,
        triggers: triggers,
      ));
    }

    int cups = 0;
    if (random.nextDouble() < 0.65) {
      cups = 1 + random.nextInt(3);
      add(0, 1, at(day, 7 * 60, 8 * 60 + 30), <String>['routine/morning']);
      if (cups > 1) {
        add(0, 1, at(day, 10 * 60, 11 * 60 + 30), <String>[
          if (random.nextBool()) 'work/meeting' else 'work/break',
        ]);
      }
      if (cups > 2) {
        add(0, 1, at(day, 14 * 60, 16 * 60), <String>[
          'body/tired',
          if (random.nextBool()) 'work/deadline',
        ]);
      }
    }
    if (random.nextDouble() < 0.6) {
      add(1, 1 + random.nextInt(2), at(day, 15 * 60, 17 * 60), const []);
    }
    final bool chocolate = random.nextDouble() < 0.35;
    if (chocolate) {
      add(2, 1 + random.nextInt(2), at(day, 20 * 60, 22 * 60), <String>[
        if (random.nextBool()) 'routine/wind-down' else 'feeling/stressed',
      ]);
    }
    if (random.nextDouble() < 0.25) {
      add(3, 1, at(day, 12 * 60, 13 * 60 + 30), <String>['routine/meal']);
    }
    entries.addAll(dayEntries.where((StoreEntry e) => !e.at.isAfter(now)));
    coffeeBefore = cups;
    chocolateBefore = chocolate;
  }
  return (entries: entries, health: health);
}
