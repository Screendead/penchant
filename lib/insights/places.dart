import 'dart:convert';
import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/photo_stays.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/what_follows.dart';

// Coordinates and stays stay on the device, in the sealed device files: never
// logged, reported or sent anywhere.

/// One visit as Core Location reports it. A visit is reported on arrival,
/// with no departure, and again once left.
class PlaceVisit {
  const PlaceVisit({
    required this.arrival,
    required this.departure,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  });

  /// Null when Core Location does not know it.
  final DateTime? arrival;

  /// Null while the person is still there.
  final DateTime? departure;
  final double latitude;
  final double longitude;

  /// In metres.
  final double accuracy;
}

/// One of the person's own places: visits within [placeRadiusMeters] of its
/// centre.
class Place {
  const Place({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.visits,
    this.name,
    this.photoStays = 0,
  });

  /// From 1, in the order the places were first visited; never reused.
  final int id;

  /// Placed by its visits; by its photo stays only while it has none.
  final double latitude;
  final double longitude;
  final int visits;

  /// Stays derived from photos ([PlaceSource.photos]).
  final int photoStays;

  /// What the person called it; null until renamed.
  final String? name;

  String get label => name ?? 'Place $id';

  Place copyWith({
    double? latitude,
    double? longitude,
    int? visits,
    String? Function()? name,
    int? photoStays,
  }) => Place(
    id: id,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    visits: visits ?? this.visits,
    name: name == null ? this.name : name(),
    photoStays: photoStays ?? this.photoStays,
  );
}

/// What a stay was learnt from.
enum PlaceSource {
  /// Core Location's visits: every stay from the first visit on, so time
  /// outside them is elsewhere.
  visits,

  /// A run of photos ([photoRuns]): time outside such stays is unknown.
  photos,
}

/// Time spent at one of the places. Sendable to another isolate.
class PlaceStay {
  const PlaceStay(
    this.placeId,
    this.arrival,
    this.departure, {
    this.source = PlaceSource.visits,
  });

  final int placeId;
  final DateTime arrival;

  /// Null while the person is still there.
  final DateTime? departure;
  final PlaceSource source;

  bool get fromPhotos => source == PlaceSource.photos;

  @override
  bool operator ==(Object other) =>
      other is PlaceStay &&
      other.placeId == placeId &&
      other.arrival == arrival &&
      other.departure == departure &&
      other.source == source;

  @override
  int get hashCode => Object.hash(placeId, arrival, departure, source);
}

/// Visits this far from a place's centre, or nearer, are at that place.
const double placeRadiusMeters = 150;

/// Visits less certain than this, in metres, are left out.
const double placeMaxAccuracyMeters = 200;

/// Two reports of one visit have arrivals this close.
const Duration _sameVisit = Duration(minutes: 1);

/// The longest name a place may be given.
const int placeNameMaxLength = 40;

double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
  const double earth = 6371000;
  double rad(double d) => d * pi / 180;
  final double dLat = rad(lat2 - lat1), dLon = rad(lon2 - lon1);
  final double a =
      pow(sin(dLat / 2), 2) +
      cos(rad(lat1)) * cos(rad(lat2)) * pow(sin(dLon / 2), 2);
  return 2 * earth * asin(min(1, sqrt(a)));
}

/// The person's places and the time spent at each, as kept in the sealed
/// device file.
class PlaceStore {
  const PlaceStore({
    this.places = const <Place>[],
    this.stays = const <PlaceStay>[],
    this.lastId = 0,
    this.photosRead = 0,
  });

  final List<Place> places;

  /// Sorted by arrival.
  final List<PlaceStay> stays;

  /// The highest place id ever given, so a removed place's id is never given
  /// again.
  final int lastId;

  /// How many photos the last import from the photo library read.
  final int photosRead;

  /// Format 1 had no stay sources, [lastId] or [photosRead]; it still opens.
  static const int format = 2;

  /// When the first visit was kept: no visit is known before it.
  DateTime? get since {
    for (final PlaceStay s in stays) {
      if (!s.fromPhotos) return s.arrival;
    }
    return null;
  }

  /// Whether photo-derived stays are kept.
  bool get hasPhotos => stays.any((s) => s.fromPhotos);

  /// The earliest photo-derived stay's arrival.
  DateTime? get photosSince {
    for (final PlaceStay s in stays) {
      if (s.fromPhotos) return s.arrival;
    }
    return null;
  }

  int get _nextId => places.fold<int>(lastId, (m, p) => max(m, p.id)) + 1;

  String labelOf(int placeId) =>
      <int, String>{for (final Place p in places) p.id: p.label}[placeId] ??
      'Place $placeId';

  /// [visits] added: each to the nearest place within [placeRadiusMeters],
  /// moving its centre, or to a new place; a departure joins the stay its
  /// arrival began.
  PlaceStore withVisits(Iterable<PlaceVisit> visits) {
    final List<Place> places = List<Place>.of(this.places);
    final List<PlaceStay> stays = List<PlaceStay>.of(this.stays);
    for (final PlaceVisit v in visits) {
      if (v.accuracy > placeMaxAccuracyMeters || v.accuracy < 0) continue;
      int? nearest;
      double best = placeRadiusMeters;
      for (int i = 0; i < places.length; i++) {
        final double d = distanceMeters(
          places[i].latitude,
          places[i].longitude,
          v.latitude,
          v.longitude,
        );
        if (d <= best) {
          best = d;
          nearest = i;
        }
      }
      final DateTime? arrival = v.arrival;
      if (arrival == null) {
        // Only a departure: it closes the last open stay at that place.
        if (nearest == null || v.departure == null) continue;
        final int open = stays.lastIndexWhere(
          (s) =>
              !s.fromPhotos &&
              s.placeId == places[nearest!].id &&
              s.departure == null,
        );
        if (open >= 0 && stays[open].arrival.isBefore(v.departure!)) {
          stays[open] = PlaceStay(
            stays[open].placeId,
            stays[open].arrival,
            v.departure,
          );
        }
        continue;
      }
      if (v.departure != null && !v.departure!.isAfter(arrival)) continue;
      final int seen = stays.indexWhere(
        (s) =>
            !s.fromPhotos && s.arrival.difference(arrival).abs() <= _sameVisit,
      );
      if (seen >= 0) {
        if (v.departure != null) {
          stays[seen] = PlaceStay(
            stays[seen].placeId,
            stays[seen].arrival,
            v.departure,
          );
        }
        continue;
      }
      final int placeId;
      if (nearest == null) {
        placeId = places.fold<int>(lastId, (m, p) => max(m, p.id)) + 1;
        places.add(
          Place(
            id: placeId,
            latitude: v.latitude,
            longitude: v.longitude,
            visits: 1,
          ),
        );
      } else {
        final Place p = places[nearest];
        final int n = p.visits + 1;
        places[nearest] = p.copyWith(
          latitude: p.latitude + (v.latitude - p.latitude) / n,
          longitude: p.longitude + (v.longitude - p.longitude) / n,
          visits: n,
        );
        placeId = p.id;
      }
      stays.add(PlaceStay(placeId, arrival, v.departure));
    }
    stays.sort((a, b) => a.arrival.compareTo(b.arrival));
    return PlaceStore(
      places: places,
      stays: stays,
      lastId: lastId,
      photosRead: photosRead,
    );
  }

  /// The photo-derived stays replaced by [runs], read from [photos] photos:
  /// each run to the nearest place within [placeRadiusMeters], or to a new
  /// one. Photos never move a place a visit has placed, and a place that
  /// only photos placed sits at the mean of its runs; ids and names stay.
  PlaceStore withPhotoRuns(Iterable<PhotoRun> runs, {required int photos}) {
    final PlaceStore base = withoutPhotos(keepPlaces: true);
    final List<Place> places = <Place>[
      for (final Place p in base.places) p.copyWith(photoStays: 0),
    ];
    final List<PlaceStay> stays = List<PlaceStay>.of(base.stays);
    int next = base._nextId;
    for (final PhotoRun r in runs) {
      if (!r.to.isAfter(r.from)) continue;
      int? nearest;
      double best = placeRadiusMeters;
      for (int i = 0; i < places.length; i++) {
        final double d = distanceMeters(
          places[i].latitude,
          places[i].longitude,
          r.latitude,
          r.longitude,
        );
        if (d <= best) {
          best = d;
          nearest = i;
        }
      }
      final int placeId;
      if (nearest == null) {
        placeId = next++;
        places.add(
          Place(
            id: placeId,
            latitude: r.latitude,
            longitude: r.longitude,
            visits: 0,
            photoStays: 1,
          ),
        );
      } else {
        final Place p = places[nearest];
        final int n = p.photoStays + 1;
        places[nearest] = p.visits > 0
            ? p.copyWith(photoStays: n)
            : p.copyWith(
                latitude: p.latitude + (r.latitude - p.latitude) / n,
                longitude: p.longitude + (r.longitude - p.longitude) / n,
                photoStays: n,
              );
        placeId = p.id;
      }
      stays.add(PlaceStay(placeId, r.from, r.to, source: PlaceSource.photos));
    }
    stays.sort((a, b) => a.arrival.compareTo(b.arrival));
    return PlaceStore(
      places: <Place>[
        for (final Place p in places)
          if (p.visits > 0 || p.photoStays > 0) p,
      ],
      stays: stays,
      lastId: max(next - 1, base.lastId),
      photosRead: photos,
    );
  }

  /// Every photo-derived stay removed, and the places only photos gave
  /// unless [keepPlaces].
  PlaceStore withoutPhotos({bool keepPlaces = false}) => PlaceStore(
    places: <Place>[
      for (final Place p in places)
        if (keepPlaces || p.visits > 0) p.copyWith(photoStays: 0),
    ],
    stays: <PlaceStay>[
      for (final PlaceStay s in stays)
        if (!s.fromPhotos) s,
    ],
    lastId: _nextId - 1,
  );

  /// [placeId] named [name], trimmed; an empty name clears it.
  PlaceStore renamed(int placeId, String name) {
    final String trimmed = name.trim();
    final String? kept = trimmed.isEmpty
        ? null
        : trimmed.substring(0, min(trimmed.length, placeNameMaxLength));
    return PlaceStore(
      places: <Place>[
        for (final Place p in places)
          p.id == placeId ? p.copyWith(name: () => kept) : p,
      ],
      stays: stays,
      lastId: lastId,
      photosRead: photosRead,
    );
  }

  List<int> encode() => utf8.encode(
    jsonEncode(<String, Object?>{
      'format': format,
      'lastId': _nextId - 1,
      if (photosRead > 0) 'photosRead': photosRead,
      'places': <Object?>[
        for (final Place p in places)
          <String, Object?>{
            'id': p.id,
            'lat': p.latitude,
            'lon': p.longitude,
            'visits': p.visits,
            if (p.name != null) 'name': p.name,
            if (p.photoStays > 0) 'photoStays': p.photoStays,
          },
      ],
      'stays': <Object?>[
        for (final PlaceStay s in stays)
          <Object?>[
            s.placeId,
            s.arrival.microsecondsSinceEpoch,
            s.departure?.microsecondsSinceEpoch,
            if (s.fromPhotos) PlaceSource.photos.index,
          ],
      ],
    }),
  );

  /// Null when [bytes] are not a store this build wrote.
  static PlaceStore? decode(List<int> bytes) {
    try {
      final Map<String, Object?> m =
          jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      if (m['format'] != 1 && m['format'] != format) return null;
      return PlaceStore(
        lastId: (m['lastId'] as int?) ?? 0,
        photosRead: (m['photosRead'] as int?) ?? 0,
        places: <Place>[
          for (final Object? o in m['places']! as List<Object?>)
            if (o case final Map<String, Object?> p)
              Place(
                id: p['id']! as int,
                latitude: (p['lat']! as num).toDouble(),
                longitude: (p['lon']! as num).toDouble(),
                visits: p['visits']! as int,
                name: p['name'] as String?,
                photoStays: (p['photoStays'] as int?) ?? 0,
              )
            else
              throw const FormatException(),
        ],
        stays: <PlaceStay>[
          for (final Object? o in m['stays']! as List<Object?>)
            if (o case [final int id, final int arrival, final int? departure])
              PlaceStay(
                id,
                DateTime.fromMicrosecondsSinceEpoch(arrival),
                departure == null
                    ? null
                    : DateTime.fromMicrosecondsSinceEpoch(departure),
              )
            else if (o case [
              final int id,
              final int arrival,
              final int departure,
              final int source,
            ] when source == PlaceSource.photos.index)
              PlaceStay(
                id,
                DateTime.fromMicrosecondsSinceEpoch(arrival),
                DateTime.fromMicrosecondsSinceEpoch(departure),
                source: PlaceSource.photos,
              )
            else
              throw const FormatException(),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}

/// The hours of a day counted as waking, from this hour...
const int placeWakingFromHour = 7;

/// ...to this one.
const int placeWakingToHour = 23;

/// A day counts for a place when at least this long of its waking hours was
/// spent there, and as long elsewhere.
const int placeMinMinutes = 60;

/// The fewest days a comparison needs.
const int placeMinDays = 14;

/// How many places are judged, those with the most waking time first.
const int placeMaxPlaces = 5;

/// The smallest difference between the share of entries and the share of
/// time worth showing, as a fraction.
const double placeFloor = 0.10;

/// Whether a habit's entries are logged at a place more or less often than
/// the time spent there would give: a finding when [refusal] is null.
class AtPlace {
  const AtPlace({
    required this.habitId,
    required this.placeId,
    required this.days,
    required this.useShare,
    required this.timeShare,
    this.effect,
    this.interval,
    this.pValue,
    this.refusal,
  });

  final String habitId;
  final int placeId;

  /// Days with an entry in waking hours and time both at the place and
  /// elsewhere.
  final int days;

  /// Over [days], the mean share of a day's waking entries logged at the
  /// place.
  final double useShare;

  /// Over [days], the mean share of a day's waking hours spent there.
  final double timeShare;

  /// [useShare] less [timeShare], fitted.
  final double? effect;
  final Interval? interval;
  final double? pValue;
  final RefusalReason? refusal;

  bool get found => refusal == null;

  AtPlace refused(RefusalReason reason) => AtPlace(
    habitId: habitId,
    placeId: placeId,
    days: days,
    useShare: useShare,
    timeShare: timeShare,
    effect: effect,
    interval: interval,
    pValue: pValue,
    refusal: reason,
  );
}

Duration _overlap(DateTime a0, DateTime a1, DateTime b0, DateTime b1) {
  final DateTime from = a0.isAfter(b0) ? a0 : b0;
  final DateTime to = a1.isBefore(b1) ? a1 : b1;
  return to.isAfter(from) ? to.difference(from) : Duration.zero;
}

/// For each habit not in [skip] and each of the [placeMaxPlaces] places with
/// the most waking time, whether its entries are logged there more or less
/// often than the time spent there would give.
///
/// The unit is the day, from the first stay's day to [through] (the last
/// whole day) within the habit's span, between [placeWakingFromHour] and
/// [placeWakingToHour]: the share of the day's entries logged during a stay
/// at the place, less the share of those hours spent there, on days with an
/// entry and at least [placeMinMinutes] both at the place and elsewhere.
/// Time not at a known place, travelling included, counts as elsewhere. An
/// intercept-only fit gives the mean difference and its interval.
///
/// Only Core Location's visits count. Photo-derived stays
/// ([PlaceSource.photos]) are left out: time outside them is unknown, not
/// elsewhere, and photos are taken on occasions that go with some habits.
/// Restricting a day to the hours its photo stays cover still let photos set
/// off by a habit raise false cards above the family's rate in simulation,
/// and left too few days to find a real difference.
List<AtPlace> atPlace({
  required List<HabitUse> uses,
  required List<PlaceStay> stays,
  required DateTime through,
  Set<String> skip = const <String>{},
  InsightGates gates = const InsightGates(),
}) {
  final List<PlaceStay> closed = <PlaceStay>[
    for (final PlaceStay s in stays)
      if (s.departure != null && !s.fromPhotos) s,
  ]..sort((a, b) => a.arrival.compareTo(b.arrival));
  if (closed.isEmpty) return const <AtPlace>[];
  final DateTime first = startOfDay(closed.first.arrival);
  final DateTime last = startOfDay(through);
  if (last.isBefore(first)) return const <AtPlace>[];

  // Per day, minutes of waking time at each place.
  final Map<DateTime, Map<int, int>> minutesAt = <DateTime, Map<int, int>>{};
  final Map<int, int> totals = <int, int>{};
  for (DateTime d = first; !d.isAfter(last); d = addDays(d, 1)) {
    final DateTime w0 = DateTime(d.year, d.month, d.day, placeWakingFromHour);
    final DateTime w1 = DateTime(d.year, d.month, d.day, placeWakingToHour);
    final Map<int, int> day = <int, int>{};
    for (final PlaceStay s in closed) {
      if (!s.arrival.isBefore(w1)) break;
      final int m = _overlap(s.arrival, s.departure!, w0, w1).inMinutes;
      if (m > 0) day[s.placeId] = (day[s.placeId] ?? 0) + m;
    }
    minutesAt[d] = day;
    for (final MapEntry<int, int> e in day.entries) {
      totals[e.key] = (totals[e.key] ?? 0) + e.value;
    }
  }
  final List<int> placeIds = totals.keys.toList()
    ..sort((a, b) {
      final int byTime = totals[b]!.compareTo(totals[a]!);
      return byTime != 0 ? byTime : a.compareTo(b);
    });
  final List<int> judged = placeIds.take(placeMaxPlaces).toList()..sort();

  int? placeAt(DateTime at) {
    for (final PlaceStay s in closed) {
      if (s.arrival.isAfter(at)) break;
      if (s.departure!.isAfter(at)) return s.placeId;
    }
    return null;
  }

  final Map<String, List<DateTime>> usesOf = <String, List<DateTime>>{};
  for (final HabitUse u in uses) {
    if (u.amount > 0) usesOf.putIfAbsent(u.habitId, () => []).add(u.at);
  }
  final List<String> ids =
      usesOf.keys.where((id) => !skip.contains(id)).toList()..sort();
  final int least = max(placeMinDays, gates.minExposedDays);
  final List<AtPlace> results = <AtPlace>[];
  for (final String id in ids) {
    final List<DateTime> times = usesOf[id]!..sort();
    final DateTime start = startOfDay(times.first);
    final DateTime lastUse = startOfDay(times.last);
    final DateTime end = lastUse.isBefore(last) ? lastUse : last;
    // Per day, the place of each waking entry (null: elsewhere).
    final Map<DateTime, List<int?>> logged = <DateTime, List<int?>>{};
    for (final DateTime t in times) {
      final DateTime d = startOfDay(t);
      if (d.isBefore(first) || d.isBefore(start) || d.isAfter(end)) continue;
      if (t.hour < placeWakingFromHour || t.hour >= placeWakingToHour) {
        continue;
      }
      logged.putIfAbsent(d, () => <int?>[]).add(placeAt(t));
    }
    for (final int placeId in judged) {
      final List<double> useShares = <double>[], timeShares = <double>[];
      for (final MapEntry<DateTime, List<int?>> e in logged.entries) {
        final DateTime d = e.key;
        final int waking = DateTime(d.year, d.month, d.day, placeWakingToHour)
            .difference(DateTime(d.year, d.month, d.day, placeWakingFromHour))
            .inMinutes;
        final int there = minutesAt[d]?[placeId] ?? 0;
        if (there < placeMinMinutes || waking - there < placeMinMinutes) {
          continue;
        }
        useShares.add(
          e.value.where((p) => p == placeId).length / e.value.length,
        );
        timeShares.add(there / waking);
      }
      final List<double> y = <double>[
        for (int i = 0; i < useShares.length; i++) useShares[i] - timeShares[i],
      ];
      AtPlace result({
        RefusalReason? refusal,
        double? effect,
        Interval? interval,
        double? pValue,
      }) => AtPlace(
        habitId: id,
        placeId: placeId,
        days: y.length,
        useShare: useShares.isEmpty ? 0 : mean(useShares),
        timeShare: timeShares.isEmpty ? 0 : mean(timeShares),
        effect: effect,
        interval: interval,
        pValue: pValue,
        refusal: refusal,
      );
      if (y.length < least) {
        results.add(result(refusal: RefusalReason.tooFewDays));
        continue;
      }
      if (sampleVariance(y) < 1e-12) {
        results.add(result(refusal: RefusalReason.withinNoise));
        continue;
      }
      final LinearFit? fit = fitLeastSquares(<List<double>>[
        for (int r = 0; r < y.length; r++) const <double>[1],
      ], y);
      if (fit == null) {
        results.add(result(refusal: RefusalReason.tooFewDays));
        continue;
      }
      final Interval interval = fit.interval(0, level: gates.level);
      results.add(
        result(
          refusal: interval.crossesZero ? RefusalReason.withinNoise : null,
          effect: fit.coefficients[0],
          interval: interval,
          pValue: fit.pValue(0),
        ),
      );
    }
  }
  return results;
}

/// [results] judged as one family with the comparisons whose p-values are
/// [alongside]: Benjamini-Hochberg at [InsightGates.falseDiscoveryRate], then
/// [placeFloor].
List<AtPlace> judgeAtPlace(
  List<AtPlace> results, {
  required List<double> alongside,
  InsightGates gates = const InsightGates(),
}) {
  final List<int> tested = <int>[
    for (int i = 0; i < results.length; i++)
      if (results[i].pValue != null) i,
  ];
  final List<bool> kept = benjaminiHochberg(<double>[
    for (final int i in tested) results[i].pValue!,
    ...alongside,
  ], gates.falseDiscoveryRate);
  final Set<int> chance = <int>{
    for (int k = 0; k < tested.length; k++)
      if (!kept[k]) tested[k],
  };
  return <AtPlace>[
    for (int i = 0; i < results.length; i++)
      if (!results[i].found)
        results[i]
      else if (chance.contains(i))
        results[i].refused(RefusalReason.chance)
      else if (results[i].effect!.abs() < placeFloor)
        results[i].refused(RefusalReason.tooSmall)
      else
        results[i],
  ];
}
