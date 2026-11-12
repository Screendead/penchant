import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/places.dart';
import 'package:tracker/insights/places_copy.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/what_follows.dart';

// Synthetic coordinates near 0°, 0°: about 1.1 km per 0.01° there.
PlaceVisit _visit(
  DateTime? arrival,
  DateTime? departure, {
  double lat = 0,
  double lon = 0,
  double accuracy = 30,
}) => PlaceVisit(
  arrival: arrival,
  departure: departure,
  latitude: lat,
  longitude: lon,
  accuracy: accuracy,
);

final DateTime _first = DateTime(2026, 3, 2);

/// [days] days at place 1 (18:00-23:00) and place 2 (9:00-17:00), with
/// Coffee logged twice at place 1 and once at place 2 on even days, the
/// other way round on odd ones.
({List<PlaceStay> stays, List<HabitUse> uses, DateTime through}) _weeks(
  int days,
) {
  final List<PlaceStay> stays = <PlaceStay>[];
  final List<HabitUse> uses = <HabitUse>[];
  DateTime at(DateTime d, int hour) => DateTime(d.year, d.month, d.day, hour);
  for (int i = 0; i < days; i++) {
    final DateTime d = addDays(_first, i);
    stays
      ..add(PlaceStay(2, at(d, 9), at(d, 17)))
      ..add(PlaceStay(1, at(d, 18), at(d, 23)));
    final List<int> hours = i.isEven ? <int>[10, 19, 21] : <int>[10, 12, 19];
    for (final int h in hours) {
      uses.add(HabitUse(habitId: 'Coffee', at: at(d, h), amount: 1));
    }
  }
  return (stays: stays, uses: uses, through: addDays(_first, days - 1));
}

void main() {
  test('visits cluster into places, and a departure joins its arrival', () {
    final DateTime nine = DateTime(2026, 3, 2, 9);
    final DateTime five = DateTime(2026, 3, 2, 17);
    final PlaceStore store = const PlaceStore().withVisits(<PlaceVisit>[
      _visit(nine, null),
      _visit(nine, five, lat: 0.0003),
      _visit(DateTime(2026, 3, 2, 18), null, lat: 0.01),
      _visit(null, DateTime(2026, 3, 2, 23), lat: 0.0101),
      _visit(DateTime(2026, 3, 3, 9), null, lat: 0.0002),
      _visit(DateTime(2026, 3, 3, 12), null, lat: 0.5, accuracy: 900),
    ]);
    expect(store.places.map((p) => (p.id, p.visits)), <(int, int)>[
      (1, 2),
      (2, 1),
    ]);
    expect(store.places.first.latitude, closeTo(0.0001, 1e-9));
    expect(store.stays, <PlaceStay>[
      PlaceStay(1, nine, five),
      PlaceStay(2, DateTime(2026, 3, 2, 18), DateTime(2026, 3, 2, 23)),
      PlaceStay(1, DateTime(2026, 3, 3, 9), null),
    ]);
    expect(store.since, nine);
  });

  test('a place keeps its name through the file, and is numbered until '
      'named', () {
    final PlaceStore store = const PlaceStore()
        .withVisits(<PlaceVisit>[
          _visit(DateTime(2026, 3, 2, 9), DateTime(2026, 3, 2, 10)),
          _visit(DateTime(2026, 3, 2, 11), null, lat: 0.02),
        ])
        .renamed(2, '  The office  ');
    final PlaceStore back = PlaceStore.decode(store.encode())!;
    expect(back.labelOf(1), 'Place 1');
    expect(back.labelOf(2), 'The office');
    expect(back.stays, store.stays);
    expect(back.renamed(2, ' ').labelOf(2), 'Place 2');
    expect(PlaceStore.decode(<int>[1, 2, 3]), isNull);
  });

  test('a habit logged at a place more than its share of time is found', () {
    final w = _weeks(40);
    final List<AtPlace> results = judgeAtPlace(
      atPlace(uses: w.uses, stays: w.stays, through: w.through),
      alongside: const <double>[],
    );
    final AtPlace home = results.singleWhere((r) => r.placeId == 1);
    expect(home.found, isTrue);
    expect(home.days, 40);
    expect(home.useShare, closeTo(0.5, 1e-9));
    expect(home.timeShare, closeTo(5 / 16, 1e-9));
    expect(home.effect, closeTo(0.5 - 5 / 16, 1e-9));
    // Half the entries in half the hours: no difference.
    final AtPlace work = results.singleWhere((r) => r.placeId == 2);
    expect(work.refusal, RefusalReason.withinNoise);
    expect(atPlaceCards(results), <AtPlace>[home]);
    expect(
      atPlaceSentence(home, 'Coffee', 'Home', 'en'),
      'On days you spend time at Home, you log 50% of your waking Coffee '
      'entries there, though you spend 31% of those hours there.',
    );
    expect(
      atPlaceBasis(home),
      'From 40 days with time both there and elsewhere, 7:00 to 23:00',
    );
  });

  test('too few days, a small difference and chance are refused', () {
    final w = _weeks(10);
    expect(
      atPlace(
        uses: w.uses,
        stays: w.stays,
        through: w.through,
      ).map((r) => r.refusal),
      everyElement(RefusalReason.tooFewDays),
    );
    const AtPlace small = AtPlace(
      habitId: 'Tea',
      placeId: 1,
      days: 30,
      useShare: 0.4,
      timeShare: 0.35,
      effect: 0.05,
      interval: Interval(0.01, 0.09),
      pValue: 0.01,
    );
    expect(
      judgeAtPlace(<AtPlace>[
        small,
      ], alongside: const <double>[]).single.refusal,
      RefusalReason.tooSmall,
    );
    const AtPlace weak = AtPlace(
      habitId: 'Tea',
      placeId: 1,
      days: 30,
      useShare: 0.6,
      timeShare: 0.35,
      effect: 0.25,
      interval: Interval(0.01, 0.49),
      pValue: 0.04,
    );
    expect(
      judgeAtPlace(<AtPlace>[
        weak,
      ], alongside: List<double>.filled(20, 0.9)).single.refusal,
      RefusalReason.chance,
    );
  });

  test('open stays and days before the first stay count for nothing', () {
    final w = _weeks(20);
    final List<HabitUse> earlier = <HabitUse>[
      for (int i = 1; i <= 30; i++)
        HabitUse(
          habitId: 'Coffee',
          at: addDays(_first, -i).add(const Duration(hours: 19)),
          amount: 1,
        ),
    ];
    final List<AtPlace> results = atPlace(
      uses: <HabitUse>[...earlier, ...w.uses],
      stays: <PlaceStay>[...w.stays, PlaceStay(3, addDays(_first, 20), null)],
      through: w.through,
    );
    expect(results.map((r) => r.placeId), <int>[1, 2]);
    expect(results.first.days, 20);
  });
}
