import 'dart:async';

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
}
