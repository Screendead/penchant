import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/crypto/journal_field_sealer.dart';
import 'package:tracker/crypto/sealed_files.dart';
import 'package:tracker/crypto/sealer.dart';
import 'package:tracker/insights/places.dart';
import 'package:tracker/insights/places_source.dart';
import 'package:tracker/providers/device_files_provider.dart';
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
}
