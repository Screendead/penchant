import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/photo_stays.dart';
import 'package:tracker/insights/places.dart';

// Simulated people whose logging does not depend on place, put through the
// photo comparison as the app runs it: photos to runs, runs into a store,
// atPlace, then judgeAtPlace. Seeded, so the rates are fixed numbers.

enum _Photos {
  /// Photo occasions independent of the habit, outings and evenings most.
  independent,

  /// Each entry sets off photos around it, far more often on outings and
  /// evenings out than at home or work: coverage is chosen by the habit.
  setOffByUse,
}

const int _people = 300;
const int _days = 180;
final DateTime _start = DateTime(2025, 1, 6);

// Places 0 home, 1 work, 2 park, 3-5 evenings out; about 1.1 km apart.
const List<double> _sessionOdds = <double>[0.2, 0.15, 0.6, 0.6, 0.6, 0.6];
const List<double> _triggerOdds = <double>[0.1, 0.1, 0.8, 0.8, 0.8, 0.8];

typedef _Segment = ({int place, DateTime from, DateTime to});

class _Person {
  _Person(int seed, this.photos, {this.atPlaceRate = 1}) : r = Random(seed);

  final Random r;
  final _Photos photos;

  /// How many times the base rate the habit is logged at place 3.
  final double atPlaceRate;
  final List<PhotoPoint> points = <PhotoPoint>[];
  final List<HabitUse> uses = <HabitUse>[];

  DateTime _at(DateTime d, double hour) => DateTime(
    d.year,
    d.month,
    d.day,
    hour.floor(),
    ((hour - hour.floor()) * 60).round(),
  );

  List<_Segment> _segments(DateTime d) {
    final bool weekend = d.weekday >= DateTime.saturday;
    final List<(int, double, double)> plan = weekend
        ? <(int, double, double)>[(0, 7, 11), (2, 11.25, 15), (0, 15.5, 19)]
        : <(int, double, double)>[(0, 7, 8.5), (1, 9, 17), (0, 17.5, 19)];
    if (r.nextDouble() < 0.4) {
      plan
        ..add((3 + r.nextInt(3), 19.25, 22.5))
        ..add((0, 22.75, 23));
    } else {
      plan.add((0, 19, 23));
    }
    return <_Segment>[
      for (final (int p, double a, double b) in plan)
        (place: p, from: _at(d, a), to: _at(d, b)),
    ];
  }

  void _session(int place, DateTime from, DateTime to, {DateTime? also}) {
    if (!to.isAfter(from)) return;
    final int n = 2 + r.nextInt(5);
    final int span = to.difference(from).inSeconds;
    final List<DateTime> times = <DateTime>[
      for (int i = 0; i < n; i++)
        from.add(Duration(seconds: r.nextInt(max(span, 1)))),
      ?also,
    ];
    for (final DateTime t in times) {
      points.add(
        PhotoPoint(
          at: t,
          latitude: 51.5 + 0.01 * place + (r.nextDouble() - 0.5) * 0.0004,
          longitude: -0.1 + (r.nextDouble() - 0.5) * 0.0004,
          accuracy: 10,
        ),
      );
    }
  }

  void live() {
    for (int i = 0; i < _days; i++) {
      final DateTime d = addDays(_start, i);
      final List<_Segment> segments = _segments(d);
      // The habit: evening-weighted, by the hour, wherever the person is.
      final List<DateTime> entries = <DateTime>[];
      for (int h = placeWakingFromHour; h < placeWakingToHour; h++) {
        final double rate = h < 17 ? 0.1 : 0.4;
        final DateTime h0 = DateTime(d.year, d.month, d.day, h);
        for (int s = 0; s < 3600; s += 60) {
          final DateTime t = h0.add(Duration(seconds: s));
          final _Segment? at = segments
              .where((g) => !t.isBefore(g.from) && t.isBefore(g.to))
              .firstOrNull;
          final double scale = at?.place == 3 ? atPlaceRate : 1;
          if (r.nextDouble() < rate * scale / 60) entries.add(t);
        }
      }
      for (final DateTime t in entries) {
        uses.add(HabitUse(habitId: 'h', at: t, amount: 1));
      }
      final double background = photos == _Photos.independent ? 1 : 0.5;
      for (final _Segment g in segments) {
        if (r.nextDouble() >= _sessionOdds[g.place] * background) continue;
        final int length = g.to.difference(g.from).inMinutes;
        final int l = min(length, 20 + r.nextInt(100));
        final DateTime from = g.from.add(
          Duration(minutes: r.nextInt(max(length - l, 0) + 1)),
        );
        _session(g.place, from, from.add(Duration(minutes: l)));
      }
      if (photos == _Photos.setOffByUse) {
        for (final DateTime t in entries) {
          final _Segment? g = segments
              .where((g) => !t.isBefore(g.from) && t.isBefore(g.to))
              .firstOrNull;
          if (g == null || r.nextDouble() >= _triggerOdds[g.place]) continue;
          DateTime from = t.subtract(Duration(minutes: 5 + r.nextInt(26)));
          DateTime to = t.add(Duration(minutes: 5 + r.nextInt(26)));
          if (from.isBefore(g.from)) from = g.from;
          if (to.isAfter(g.to)) to = g.to;
          _session(g.place, from, to, also: t);
        }
      }
    }
  }
}

typedef _Rates = ({double anyCard, int tested, int medianDays});

_Rates _run(_Photos photos, {double atPlaceRate = 1, bool asVisits = false}) {
  int withCard = 0, tested = 0;
  final List<int> days = <int>[];
  for (int p = 0; p < _people; p++) {
    final _Person person = _Person(p * 7919 + photos.index, photos,
        atPlaceRate: atPlaceRate)
      ..live();
    final List<PhotoRun> runs = photoRuns(person.points);
    final PlaceStore store = const PlaceStore().withPhotoRuns(
      runs,
      photos: person.points.length,
    );
    final List<PlaceStay> stays = asVisits
        ? <PlaceStay>[
            for (final PlaceStay s in store.stays)
              PlaceStay(s.placeId, s.arrival, s.departure),
          ]
        : store.stays;
    final List<AtPlace> judged = judgeAtPlace(
      atPlace(
        uses: person.uses,
        stays: stays,
        through: addDays(_start, _days),
      ),
      alongside: const <double>[],
    );
    tested += judged.where((a) => a.pValue != null).length;
    for (final AtPlace a in judged) {
      days.add(a.days);
    }
    if (judged.any((a) => a.found)) withCard++;
  }
  days.sort();
  return (
    anyCard: withCard / _people,
    tested: tested,
    medianDays: days.isEmpty ? 0 : days[days.length ~/ 2],
  );
}

void main() {
  // The family's false-discovery rate (InsightGates.falseDiscoveryRate) is
  // 0.1; under a complete null it bounds the chance of any card at 0.1.
  const double bound = 0.1;

  test('photo occasions independent of the habit: no more false cards '
      'than the family allows', () {
    final _Rates rates = _run(_Photos.independent);
    // ignore: avoid_print
    print('independent photos, photo comparison: $rates');
    expect(rates.anyCard, lessThanOrEqualTo(bound));
  });

  test('photos set off by the habit, place irrelevant: no more false '
      'cards than the family allows', () {
    final _Rates rates = _run(_Photos.setOffByUse);
    // ignore: avoid_print
    print('photos set off by use, photo comparison: $rates');
    expect(rates.anyCard, lessThanOrEqualTo(bound));
  });

  test('treating photo stays as visits (unknown time as elsewhere) would '
      'not be honest', () {
    final _Rates independent = _run(_Photos.independent, asVisits: true);
    final _Rates setOff = _run(_Photos.setOffByUse, asVisits: true);
    // ignore: avoid_print
    print('as visits: independent $independent, set off by use $setOff');
    expect(setOff.anyCard, greaterThan(bound));
  });

  test('a habit logged three times as often at one place is found', () {
    final _Rates rates = _run(_Photos.independent, atPlaceRate: 3);
    // ignore: avoid_print
    print('three times as often at one place: $rates');
    expect(rates.anyCard, greaterThan(0.5));
  });
}
