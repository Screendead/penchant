import 'dart:async';
import 'dart:typed_data';

import 'package:tracker/insights/photo_stays.dart';
import 'package:tracker/insights/photos_source.dart';
import 'package:tracker/insights/places.dart';
import 'package:tracker/insights/places_source.dart';

/// A [PlacesSource] whose visits wait in [pending] as the Swift side's do.
class FakePlaces implements PlacesSource {
  FakePlaces(this.state, [List<PlaceVisit>? pending])
    : pending = pending ?? <PlaceVisit>[];

  PlacesAccess state;
  final List<PlaceVisit> pending;
  int starts = 0;
  int asked = 0;
  bool failTake = false;
  final StreamController<void> _reported = StreamController<void>.broadcast();

  void report(PlaceVisit visit) {
    pending.add(visit);
    _reported.add(null);
  }

  @override
  Future<PlacesAccess> access() async => state;

  @override
  Future<PlacesAccess> requestAccess() async {
    asked++;
    state = PlacesAccess.always;
    return state;
  }

  @override
  Future<void> start() async => starts++;

  @override
  Future<List<PlaceVisit>> take() async {
    if (failTake) throw StateError('no');
    return List<PlaceVisit>.of(pending);
  }

  @override
  Future<void> ack(int count) async => pending.removeRange(0, count);

  @override
  Stream<void> get reported => _reported.stream;

  /// What [mapSnapshot] answers.
  Uint8List? map;
  int maps = 0;

  @override
  Future<Uint8List?> mapSnapshot({
    required double latitude,
    required double longitude,
    required double span,
    required double width,
    required double height,
    required double scale,
    required bool dark,
  }) async {
    maps++;
    return map;
  }
}

/// A [PhotosSource] whose library holds [photos] near every place.
class FakePhotos implements PhotosSource {
  FakePhotos(this.state, [this.photos = const <PlacePhoto>[]]);

  PhotosAccess state;
  final List<PlacePhoto> photos;
  int asked = 0;
  int nears = 0;

  @override
  Future<PhotosAccess> access() async => state;

  @override
  Future<PhotosAccess> requestAccess() async {
    asked++;
    return state;
  }

  @override
  Future<List<PhotoPoint>> read({
    void Function(int done, int total)? onProgress,
  }) async => const <PhotoPoint>[];

  @override
  Future<List<PlacePhoto>> near({
    required double latitude,
    required double longitude,
    required double radius,
    required int limit,
    required int pixels,
  }) async {
    nears++;
    return photos;
  }
}

/// A 1×1 transparent PNG, for a thumbnail or map that must decode.
final Uint8List onePixelPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);
