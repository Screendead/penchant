import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:tracker/insights/places.dart';

// The Swift side is ios/Runner/PlacesChannel.swift. Visits wait there in
// memory only until taken, and nothing read here leaves the device.

/// What Core Location says the app may do.
enum PlacesAccess { always, whenInUse, denied, restricted, notDetermined }

abstract interface class PlacesSource {
  Future<PlacesAccess> access();

  /// Shows the system's When In Use prompt where it has not been answered,
  /// then, once allowed, the prompt to upgrade to Always. Core Location
  /// shows each at most once. Answers the access after it.
  Future<PlacesAccess> requestAccess();

  /// Starts visit monitoring where allowed; the system then relaunches the
  /// app for visits while it is closed.
  Future<void> start();

  /// The visits reported since the last [take], oldest first. They are
  /// dropped on the Swift side only when [ack] names them.
  Future<List<PlaceVisit>> take();

  /// Drops the first [count] visits [take] gave.
  Future<void> ack(int count);

  /// An event each time Core Location reports a visit.
  Stream<void> get reported;

  /// A map [span] metres across centred on [latitude], [longitude], as a PNG
  /// of [width] by [height] points at [scale]. Drawing it sends the place's
  /// location to Apple. Null on any failure; never throws.
  Future<Uint8List?> mapSnapshot({
    required double latitude,
    required double longitude,
    required double span,
    required double width,
    required double height,
    required double scale,
    required bool dark,
  });
}

class ChannelPlacesSource implements PlacesSource {
  ChannelPlacesSource({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('com.screendead.penchant/places') {
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'reported') _reported.add(null);
    });
  }

  final MethodChannel _channel;
  final StreamController<void> _reported = StreamController<void>.broadcast();

  @override
  Stream<void> get reported => _reported.stream;

  static PlacesAccess _parse(String? name) => PlacesAccess.values.firstWhere(
    (a) => a.name == name,
    orElse: () => PlacesAccess.denied,
  );

  @override
  Future<PlacesAccess> access() async =>
      _parse(await _channel.invokeMethod<String>('access'));

  @override
  Future<PlacesAccess> requestAccess() async =>
      _parse(await _channel.invokeMethod<String>('requestAccess'));

  @override
  Future<void> start() => _channel.invokeMethod<void>('start');

  @override
  Future<List<PlaceVisit>> take() async => placeVisitsFrom(
    await _channel.invokeMethod<Float64List>('take') ?? Float64List(0),
  );

  @override
  Future<void> ack(int count) =>
      _channel.invokeMethod<void>('ack', <String, int>{'count': count});

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
    try {
      final Object? png = await _channel
          .invokeMethod<Object?>('mapSnapshot', <String, Object>{
            'lat': latitude,
            'lon': longitude,
            'span': span,
            'width': width,
            'height': height,
            'scale': scale,
            'dark': dark,
          });
      return png is Uint8List && png.isNotEmpty ? png : null;
    } catch (_) {
      return null;
    }
  }
}

/// The channel's answer, five numbers a visit: arrival and departure in
/// microseconds since 1970, each NaN when unknown, then latitude, longitude
/// and accuracy in metres.
List<PlaceVisit> placeVisitsFrom(Float64List flat) => <PlaceVisit>[
  for (int i = 0; i + 4 < flat.length; i += 5)
    PlaceVisit(
      arrival: flat[i].isNaN
          ? null
          : DateTime.fromMicrosecondsSinceEpoch(flat[i].round()),
      departure: flat[i + 1].isNaN
          ? null
          : DateTime.fromMicrosecondsSinceEpoch(flat[i + 1].round()),
      latitude: flat[i + 2],
      longitude: flat[i + 3],
      accuracy: flat[i + 4],
    ),
];
