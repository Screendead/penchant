// Monte Carlo rates for the days-away comparison in
// lib/insights/days_away.dart, on synthetic people only: photos to coarse
// cells per day, cells to away days, then the comparison and its judging as
// one family of one. Slow, so it lives outside test/:
//   flutter test tools/insights-calibration/days_away_test.dart
// Each line prints the share of people with a card, the median away days
// detected and the median truly away.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/days_away.dart';

const int people = 400;
const int span = 365;
final DateTime start = DateTime(2025, 1, 6);

enum Photos {
  /// Photos on some days at home or nearby, more often away.
  independent,

  /// At home, photos far more likely on days the habit is used.
  withUseAtHome,

  /// Away, photos far more likely on days the habit is used.
  withUseAway,
}

class Person {
  Person(int seed, this.photos, {this.tripOdds = 0.06, this.awayLift = 0})
    : r = Random(seed);

  final Random r;
  final Photos photos;

  /// The chance each day that a trip starts, more on Fridays and Saturdays.
  final double tripOdds;

  /// How much more likely a use is on a day away.
  final double awayLift;
  final Map<DateTime, Set<DayCell>> cells = <DateTime, Set<DayCell>>{};
  final List<HabitUse> uses = <HabitUse>[];
  int trulyAway = 0;

  void live() {
    // A small chance of moving house halfway, 300 km away.
    final bool moves = r.nextDouble() < 0.1;
    int tripLeft = 0;
    double tripLat = 0, tripLon = 0;
    bool usedYesterday = false;
    for (int i = 0; i < span; i++) {
      final DateTime d = addDays(start, i);
      final double homeLat = moves && i > span ~/ 2 ? 54.2 : 51.5;
      const double homeLon = -0.1;
      final bool weekend = d.weekday >= DateTime.saturday;
      if (tripLeft == 0) {
        final double odds = d.weekday >= DateTime.friday
            ? tripOdds * 2
            : tripOdds * 0.5;
        if (r.nextDouble() < odds) {
          final double roll = r.nextDouble();
          tripLeft = roll < 0.4
              ? 1
              : roll < 0.8
              ? 2 + r.nextInt(2)
              : 4 + r.nextInt(6);
          final double km = 100 + r.nextDouble() * 700;
          final double bearing = r.nextDouble() * 2 * pi;
          tripLat = homeLat + km / 111 * cos(bearing);
          tripLon = homeLon + km / 70 * sin(bearing);
        }
      }
      final bool away = tripLeft > 0;
      if (away) {
        tripLeft--;
        trulyAway++;
      }
      double p = (weekend ? 0.45 : 0.35) + (usedYesterday ? 0.15 : 0);
      if (away) p += awayLift;
      final bool used = r.nextDouble() < p;
      usedYesterday = used;
      if (used) {
        uses.add(
          HabitUse(
            habitId: 'h',
            at: DateTime(d.year, d.month, d.day, 12 + r.nextInt(10)),
            amount: 1,
          ),
        );
      }
      final double photoOdds = switch ((photos, away)) {
        (Photos.withUseAtHome, false) => used ? 0.6 : 0.15,
        (Photos.withUseAway, true) => used ? 0.9 : 0.3,
        (_, false) => 0.3,
        (_, true) => 0.6,
      };
      if (r.nextDouble() >= photoOdds) continue;
      final Set<DayCell> day = cells.putIfAbsent(d, () => <DayCell>{});
      for (int k = 1 + r.nextInt(4); k > 0; k--) {
        // At home, anywhere within about 20 km; away, around the trip.
        final double jitter = (away ? 0.1 : 0.18) * (r.nextDouble() - 0.5);
        day.add(
          dayCellOf(
            (away ? tripLat : homeLat) + jitter,
            (away ? tripLon : homeLon) + jitter * 1.6,
          ),
        );
      }
    }
  }
}

void rate(
  String name,
  Photos photos, {
  double tripOdds = 0.06,
  double awayLift = 0,
}) {
  int withCard = 0, tested = 0;
  final List<int> detected = <int>[], truly = <int>[];
  for (int seed = 0; seed < people; seed++) {
    final Person p = Person(
      seed * 7919 + photos.index,
      photos,
      tripOdds: tripOdds,
      awayLift: awayLift,
    )..live();
    final DateTime through = addDays(start, span - 1);
    final Map<DateTime, bool> away = daysAwayFrom(p.cells, through: through);
    detected.add(away.values.where((a) => a).length);
    truly.add(p.trulyAway);
    final List<DaysAway> judged = judgeDaysAway(
      daysAway(uses: p.uses, away: away, through: through),
      alongside: const <double>[],
    );
    if (judged.any((d) => d.pValue != null)) tested++;
    if (judged.any((d) => d.found)) withCard++;
  }
  detected.sort();
  truly.sort();
  stdout.writeln(
    '$name: card ${(100 * withCard / people).toStringAsFixed(1)}% '
    '(tested $tested of $people), away days detected median '
    '${detected[people ~/ 2]}, truly away median ${truly[people ~/ 2]}',
  );
}

void main() {
  test('days away', () {
    rate('a null, independent photos', Photos.independent);
    rate('b null, photos with use at home', Photos.withUseAtHome);
    rate('c null, photos with use away', Photos.withUseAway);
    for (final (int days, double odds) in <(int, double)>[
      (15, 0.012),
      (30, 0.025),
      (60, 0.05),
    ]) {
      rate(
        'd +20 points away, about $days days away',
        Photos.independent,
        tripOdds: odds,
        awayLift: 0.2,
      );
    }
  }, timeout: Timeout.none);
}
