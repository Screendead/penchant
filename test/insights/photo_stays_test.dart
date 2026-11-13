import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/photo_stays.dart';
import 'package:tracker/insights/photos_source.dart';
import 'package:tracker/insights/places.dart';

// Synthetic coordinates near 51.5°, 0°: about 1.1 km per 0.01° of latitude.
final DateTime _day = DateTime(2025, 3, 4);

DateTime _at(int hour, [int minute = 0, DateTime? day]) {
  final DateTime d = day ?? _day;
  return DateTime(d.year, d.month, d.day, hour, minute);
}

PhotoPoint _photo(DateTime at, {double lat = 51.5, double accuracy = 10}) =>
    PhotoPoint(at: at, latitude: lat, longitude: 0, accuracy: accuracy);

PlaceVisit _visit(DateTime arrival, DateTime departure, {double lat = 51.5}) =>
    PlaceVisit(
      arrival: arrival,
      departure: departure,
      latitude: lat,
      longitude: 0,
      accuracy: 30,
    );

void main() {
  test('a run of photos at one place is a stay from first to last; a lone '
      'photo, a burst and a long gap give nothing', () {
    final List<PhotoRun> runs = photoRuns(<PhotoPoint>[
      _photo(_at(19, 40)),
      _photo(_at(19)),
      _photo(_at(19, 20), lat: 51.5005), // 55 m away: the same place.
      _photo(_at(21), lat: 51.52), // Elsewhere, alone: nothing.
      _photo(_at(21, 30)), // Back, then a burst of two minutes: nothing.
      _photo(_at(21, 32)),
      _photo(_at(9, 0, addDays(_day, 1))), // 90 minutes and more apart.
      _photo(_at(10, 31, addDays(_day, 1))),
      _photo(_at(12, 0, addDays(_day, 1)), accuracy: 500), // Too vague.
    ]);
    expect(runs, hasLength(1));
    expect(runs.single.from, _at(19));
    expect(runs.single.to, _at(19, 40));
    expect(runs.single.photos, 3);
  });

  test('a run never crosses midnight', () {
    final List<PhotoRun> runs = photoRuns(<PhotoPoint>[
      _photo(_at(23, 30)),
      _photo(_at(0, 20, addDays(_day, 1))),
    ]);
    expect(runs, isEmpty);
  });

  test('photo stays join a visited place without moving it, make new places '
      'otherwise, and come off again with those places', () {
    final PlaceStore visited = const PlaceStore().withVisits(<PlaceVisit>[
      _visit(_at(9), _at(17)),
    ]);
    final List<PhotoRun> runs = photoRuns(<PhotoPoint>[
      _photo(_at(19, 0, addDays(_day, -30)), lat: 51.5008),
      _photo(_at(19, 30, addDays(_day, -30)), lat: 51.5008),
      _photo(_at(12, 0, addDays(_day, -20)), lat: 51.53),
      _photo(_at(13, 0, addDays(_day, -20)), lat: 51.53),
    ]);
    final PlaceStore store = visited.withPhotoRuns(runs, photos: 4);
    expect(store.places, hasLength(2));
    final Place home = store.places.firstWhere((p) => p.id == 1);
    expect(home.latitude, 51.5);
    expect(home.visits, 1);
    expect(home.photoStays, 1);
    final Place other = store.places.firstWhere((p) => p.id == 2);
    expect(other.visits, 0);
    expect(other.photoStays, 1);
    expect(store.stays.where((s) => s.fromPhotos), hasLength(2));
    expect(store.since, _at(9), reason: 'since is the first visit');
    expect(store.photosSince, _at(19, 0, addDays(_day, -30)));
    expect(store.photosRead, 4);

    // Named, then read again: the same ids and the name stay.
    final PlaceStore again = store
        .renamed(2, 'Park')
        .withPhotoRuns(runs, photos: 4);
    expect(again.places.firstWhere((p) => p.id == 2).name, 'Park');
    expect(again.stays.where((s) => s.fromPhotos), hasLength(2));

    final PlaceStore removed = again.withoutPhotos();
    expect(removed.places.map((p) => p.id), <int>[1]);
    expect(removed.stays.every((s) => !s.fromPhotos), isTrue);
    expect(removed.places.single.photoStays, 0);
    // A removed place's id is never given again.
    final PlaceStore next = removed.withVisits(<PlaceVisit>[
      _visit(
        _at(9, 0, addDays(_day, 1)),
        _at(10, 0, addDays(_day, 1)),
        lat: 51.56,
      ),
    ]);
    expect(next.places.map((p) => p.id), <int>[1, 3]);
  });

  test('a visit is never taken for the photo stay that began with it', () {
    final PlaceStore store = const PlaceStore()
        .withPhotoRuns(<PhotoRun>[
          PhotoRun(
            from: _at(9),
            to: _at(10),
            latitude: 51.5,
            longitude: 0,
            photos: 2,
          ),
        ], photos: 2)
        .withVisits(<PlaceVisit>[_visit(_at(9), _at(17))]);
    expect(store.stays, hasLength(2));
    expect(store.places.single.visits, 1);
    expect(store.places.single.latitude, 51.5);
  });

  test(
    'the file keeps each stay’s source, and a format 1 file still opens',
    () {
      final PlaceStore store = const PlaceStore()
          .withVisits(<PlaceVisit>[_visit(_at(9), _at(17))])
          .withPhotoRuns(<PhotoRun>[
            PhotoRun(
              from: _at(19),
              to: _at(20),
              latitude: 51.53,
              longitude: 0,
              photos: 3,
            ),
          ], photos: 3);
      final PlaceStore read = PlaceStore.decode(store.encode())!;
      expect(read.stays, store.stays);
      expect(read.places.map((p) => (p.id, p.visits, p.photoStays)), <Object>[
        (1, 1, 0),
        (2, 0, 1),
      ]);
      expect(read.photosRead, 3);

      final PlaceStore old = PlaceStore.decode(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'format': 1,
            'places': <Object?>[
              <String, Object?>{
                'id': 4,
                'lat': 51.5,
                'lon': 0,
                'visits': 2,
                'name': 'Home',
              },
            ],
            'stays': <Object?>[
              <Object?>[4, _at(9).microsecondsSinceEpoch, null],
            ],
          }),
        ),
      )!;
      expect(old.places.single.label, 'Home');
      expect(old.stays.single.source, PlaceSource.visits);
      expect(old.hasPhotos, isFalse);
    },
  );

  test('the comparison leaves photo-derived stays out', () {
    final List<PlaceStay> stays = <PlaceStay>[];
    final List<HabitUse> uses = <HabitUse>[];
    for (int i = 0; i < 40; i++) {
      final DateTime d = addDays(_day, i);
      stays
        ..add(
          PlaceStay(1, _at(9, 0, d), _at(17, 0, d), source: PlaceSource.photos),
        )
        ..add(
          PlaceStay(
            2,
            _at(18, 0, d),
            _at(22, 0, d),
            source: PlaceSource.photos,
          ),
        );
      uses
        ..add(HabitUse(habitId: 'h', at: _at(10, 0, d), amount: 1))
        ..add(HabitUse(habitId: 'h', at: _at(11, 0, d), amount: 1));
    }
    expect(
      atPlace(uses: uses, stays: stays, through: addDays(_day, 40)),
      isEmpty,
    );
  });

  test('the channel’s rows become photos', () {
    final List<PhotoPoint> points = photoPointsFrom(
      Float64List.fromList(<double>[
        _at(9).microsecondsSinceEpoch.toDouble(),
        51.5,
        -0.1,
        12,
        double.nan,
        1,
        2,
        3,
      ]),
    );
    expect(points, hasLength(1));
    expect(points.single.at, _at(9));
    expect(points.single.longitude, -0.1);
    expect(points.single.accuracy, 12);
  });
}
