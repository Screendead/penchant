import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/crypto/journal_field_sealer.dart';
import 'package:tracker/crypto/sealed_files.dart';
import 'package:tracker/crypto/sealer.dart';
import 'package:tracker/insights/photo_stays.dart';
import 'package:tracker/insights/photos_source.dart';
import 'package:tracker/insights/places.dart';
import 'package:tracker/insights/places_source.dart';
import 'package:tracker/providers/device_files_provider.dart';
import 'package:tracker/providers/photos_provider.dart';
import 'package:tracker/providers/places_provider.dart';

import 'fake_places.dart';

PlaceVisit _visit(int day, {double lat = 0}) => PlaceVisit(
  arrival: DateTime(2026, 3, day, 9),
  departure: DateTime(2026, 3, day, 17),
  latitude: lat,
  longitude: 0,
  accuracy: 30,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory caches;
  late SealedFiles files;

  setUp(() async {
    caches = await Directory.systemTemp.createTemp('places');
    files = DeviceFiles(caches: () async => caches).forUser(
      'u1',
      JournalFieldSealer(
        Sealer(aes: AesGcm.with256bits(), key: List<int>.filled(32, 7)),
      ),
    );
  });
  tearDown(() => caches.delete(recursive: true));

  ProviderContainer container(FakePlaces source) {
    final ProviderContainer c = ProviderContainer(
      overrides: [
        placesSourceProvider.overrideWithValue(source),
        sealedFilesProvider.overrideWithValue(files),
      ],
    );
    addTearDown(c.dispose);
    c.listen(placesProvider, (_, _) {});
    return c;
  }

  Future<PlacesState> settled(ProviderContainer c) async {
    for (int i = 0; i < 50 && !c.read(placesProvider).ready; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await c.read(placesProvider.notifier).drain();
    return c.read(placesProvider);
  }

  test(
    'with access, visits are started, kept sealed and acknowledged',
    () async {
      final FakePlaces source = FakePlaces(PlacesAccess.always, <PlaceVisit>[
        _visit(2),
        _visit(3, lat: 0.0002),
      ]);
      final ProviderContainer c = container(source);
      final PlacesState state = await settled(c);

      expect(state.store.places.single.visits, 2);
      expect(source.starts, 1);
      expect(source.pending, isEmpty);

      source.report(_visit(4, lat: 0.02));
      await settled(c);
      expect(c.read(placesProvider).store.places.length, 2);

      expect(await c.read(placesProvider.notifier).rename(2, 'Gym'), isTrue);
      final ProviderContainer again = container(
        FakePlaces(PlacesAccess.always),
      );
      final PlaceStore kept = (await settled(again)).store;
      expect(kept.stays.length, 3);
      expect(kept.labelOf(2), 'Gym');
      final List<int> onDisk = <int>[
        for (final FileSystemEntity e in caches.listSync(recursive: true))
          if (e is File) ...e.readAsBytesSync(),
      ];
      expect(String.fromCharCodes(onDisk), isNot(contains('Gym')));
    },
  );

  test('without access nothing is started or taken', () async {
    final FakePlaces source = FakePlaces(
      PlacesAccess.notDetermined,
      <PlaceVisit>[_visit(2)],
    );
    final ProviderContainer c = container(source);
    final PlacesState state = await settled(c);
    expect(state.ready, isTrue);
    expect(source.starts, 0);
    expect(source.pending.length, 1);
  });

  test('a failed take keeps the visits for the next drain', () async {
    final FakePlaces source = FakePlaces(PlacesAccess.always, <PlaceVisit>[
      _visit(2),
    ])..failTake = true;
    final ProviderContainer c = container(source);
    expect((await settled(c)).store.places, isEmpty);
    source.failTake = false;
    await c.read(placesProvider.notifier).drain();
    expect(c.read(placesProvider).store.places.length, 1);
    expect(source.pending, isEmpty);
  });
  test('re-reading access keeps the places loaded', () async {
    final FakePlaces source = FakePlaces(PlacesAccess.whenInUse, <PlaceVisit>[
      _visit(2),
    ]);
    final ProviderContainer c = container(source);
    expect((await settled(c)).store.places.length, 1);
    final List<bool> seen = <bool>[];
    c.listen(placesProvider, (_, PlacesState s) => seen.add(s.ready));

    // What the Insights page does on every resume short of Always.
    c.invalidate(placesAccessProvider);
    await c.read(placesAccessProvider.future);
    await settled(c);

    expect(seen, isNot(contains(false)));
    expect(c.read(placesProvider).store.places.length, 1);
  });

  test('access granted later starts visits and drains them', () async {
    final FakePlaces source = FakePlaces(
      PlacesAccess.notDetermined,
      <PlaceVisit>[_visit(2)],
    );
    final ProviderContainer c = container(source);
    await settled(c);
    expect(source.starts, 0);

    expect(await connectPlaces(c), PlacesAccess.always);
    await c.read(placesAccessProvider.future);
    await settled(c);

    expect(source.starts, 1);
    expect(c.read(placesProvider).store.places.length, 1);
    expect(source.pending, isEmpty);
  });

  test('an import from photos adds photo stays to the sealed file, and '
      'removing them leaves the visits', () async {
    final ProviderContainer c = ProviderContainer(
      overrides: [
        placesSourceProvider.overrideWithValue(FakePlaces(PlacesAccess.always)),
        sealedFilesProvider.overrideWithValue(files),
        photosSourceProvider.overrideWithValue(_FakePhotos()),
      ],
    );
    addTearDown(c.dispose);
    c.listen(placesProvider, (_, _) {});
    await settled(c);
    final List<(int, int)> progress = <(int, int)>[];
    final PhotosImport outcome = await importPlacesFromPhotos(
      c,
      onProgress: (int done, int total) => progress.add((done, total)),
    );
    expect(outcome, isA<PhotosImported>());
    final PhotosImported imported = outcome as PhotosImported;
    expect(imported.places, 1);
    expect(imported.photos, 2);
    expect(imported.since, DateTime(2025, 6, 1, 19));
    expect(imported.limited, isTrue);
    expect(progress, <(int, int)>[(2, 2)]);
    final PlaceStore kept = PlaceStore.decode(
      (await files.read(placesFileName))!,
    )!;
    expect(kept.stays.single.fromPhotos, isTrue);

    expect(await removePlacesFromPhotos(c), isTrue);
    final PlaceStore removed = PlaceStore.decode(
      (await files.read(placesFileName))!,
    )!;
    expect(removed.stays, isEmpty);
    expect(removed.places, isEmpty);
  });
}

class _FakePhotos implements PhotosSource {
  @override
  Future<PhotosAccess> access() async => PhotosAccess.notDetermined;

  @override
  Future<PhotosAccess> requestAccess() async => PhotosAccess.limited;

  @override
  Future<List<PhotoPoint>> read({
    void Function(int done, int total)? onProgress,
  }) async {
    onProgress?.call(2, 2);
    return <PhotoPoint>[
      for (final int minute in <int>[0, 40])
        PhotoPoint(
          at: DateTime(2025, 6, 1, 19, minute),
          latitude: 51.5,
          longitude: 0,
          accuracy: 10,
        ),
    ];
  }

  @override
  Future<List<PlacePhoto>> near({
    required double latitude,
    required double longitude,
    required double radius,
    required int limit,
    required int pixels,
  }) async => const <PlacePhoto>[];
}
