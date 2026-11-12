import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:tracker/insights/daylight.dart';
import 'package:tracker/providers/places_provider.dart';

/// The device's time zone, as an IANA name; null when it cannot be read.
final FutureProvider<String?> deviceTimeZoneProvider = FutureProvider<String?>((
  ref,
) async {
  try {
    return (await FlutterTimezone.getLocalTimezone()).identifier;
  } catch (_) {
    return null;
  }
});

/// Where Daylight's sunrise and sunset are worked out: the place with the
/// most time, else the time zone's city, to whole degrees; null when neither
/// is known. Loading until the time zone answers.
final Provider<AsyncValue<RoughLocation?>> roughLocationProvider =
    Provider<AsyncValue<RoughLocation?>>((ref) {
      final PlacesState places = ref.watch(placesProvider);
      if (!places.ready) return const AsyncLoading<RoughLocation?>();
      if (roughLocationOfPlaces(places.store) case final RoughLocation at) {
        return AsyncData<RoughLocation?>(at);
      }
      return ref.watch(deviceTimeZoneProvider).whenData(roughLocationOfZone);
    });
