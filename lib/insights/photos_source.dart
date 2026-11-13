import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:tracker/insights/photo_stays.dart';

// The Swift side is ios/Runner/PhotosChannel.swift. The import reads each
// photo's creation time and location alone. [PhotosSource.near] reads small
// thumbnails of one place's photos when the person opens it to name it, held
// in memory only. Nothing read here leaves the device, and no error or log
// may carry a coordinate.

/// What the photo library lets the app read: [limited] is only the photos
/// the person chose to share.
enum PhotosAccess { full, limited, denied, restricted, notDetermined }

abstract interface class PhotosSource {
  Future<PhotosAccess> access();

  /// Shows the system's prompt where it has not been answered. Answers the
  /// access after it.
  Future<PhotosAccess> requestAccess();

  /// When and where each readable photo or video with a location was taken.
  /// [onProgress] hears how many of the library's assets have been looked at
  /// out of how many.
  Future<List<PhotoPoint>> read({
    void Function(int done, int total)? onProgress,
  });

  /// Up to [limit] photos taken in one of the spans [during] and within
  /// [radius] metres of [latitude], [longitude], newest first, each about [pixels] on its longer side. Empty
  /// without access or on any failure; never throws.
  Future<List<PlacePhoto>> near({
    required double latitude,
    required double longitude,
    required double radius,
    required List<(DateTime, DateTime)> during,
    required int limit,
    required int pixels,
  });
}

/// A thumbnail of a photo taken at a place, and when.
class PlacePhoto {
  const PlacePhoto(this.at, this.jpeg);

  final DateTime at;
  final Uint8List jpeg;
}

class ChannelPhotosSource implements PhotosSource {
  ChannelPhotosSource({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('com.screendead.penchant/photos') {
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.arguments case [
        final int done,
        final int total,
      ] when call.method == 'progress') {
        _progress?.call(done, total);
      }
    });
  }

  final MethodChannel _channel;
  void Function(int done, int total)? _progress;

  static PhotosAccess _parse(String? name) => PhotosAccess.values.firstWhere(
    (a) => a.name == name,
    orElse: () => PhotosAccess.denied,
  );

  @override
  Future<PhotosAccess> access() async =>
      _parse(await _channel.invokeMethod<String>('access'));

  @override
  Future<PhotosAccess> requestAccess() async =>
      _parse(await _channel.invokeMethod<String>('requestAccess'));

  @override
  Future<List<PhotoPoint>> read({
    void Function(int done, int total)? onProgress,
  }) async {
    _progress = onProgress;
    try {
      return photoPointsFrom(
        await _channel.invokeMethod<Float64List>('read') ?? Float64List(0),
      );
    } finally {
      _progress = null;
    }
  }

  @override
  Future<List<PlacePhoto>> near({
    required double latitude,
    required double longitude,
    required double radius,
    required List<(DateTime, DateTime)> during,
    required int limit,
    required int pixels,
  }) async {
    try {
      return placePhotosFrom(
        await _channel.invokeMethod<Object?>('near', <String, Object>{
          'lat': latitude,
          'lon': longitude,
          'radius': radius,
          'spans': <int>[
            for (final (DateTime from, DateTime to) in during) ...<int>[
              from.microsecondsSinceEpoch,
              to.microsecondsSinceEpoch,
            ],
          ],
          'limit': limit,
          'pixels': pixels,
        }),
      );
    } catch (_) {
      return const <PlacePhoto>[];
    }
  }
}

/// The channel's answer to `near`: maps of `at`, microseconds since 1970, and
/// `jpeg`. Anything malformed is left out.
List<PlacePhoto> placePhotosFrom(Object? answer) => <PlacePhoto>[
  if (answer is List<Object?>)
    for (final Object? o in answer)
      if (o case {
        'at': final int at,
        'jpeg': final Uint8List jpeg,
      } when jpeg.isNotEmpty)
        PlacePhoto(DateTime.fromMicrosecondsSinceEpoch(at), jpeg),
];

/// The channel's answer, four numbers a photo: creation time in microseconds
/// since 1970, latitude, longitude and accuracy in metres.
List<PhotoPoint> photoPointsFrom(Float64List flat) => <PhotoPoint>[
  for (int i = 0; i + 3 < flat.length; i += 4)
    if (flat[i].isFinite)
      PhotoPoint(
        at: DateTime.fromMicrosecondsSinceEpoch(flat[i].round()),
        latitude: flat[i + 1],
        longitude: flat[i + 2],
        accuracy: flat[i + 3],
      ),
];
