import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:tracker/insights/photo_stays.dart';

// The Swift side is ios/Runner/PhotosChannel.swift. It reads each photo's
// creation time and location alone, never the picture, and nothing read
// here leaves the device.

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
}

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
