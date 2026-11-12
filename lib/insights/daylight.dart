import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/places.dart';
import 'package:tracker/insights/zone_locations.dart';

// A rough location stays in memory on the device: never stored, logged,
// reported or sent anywhere.

/// [DayCondition.id] of the day's length, and what a finding's `heldFixed`
/// names when its comparison held it.
const String dayLengthId = 'dayLength';

/// A location rounded to whole degrees, about 100 km: enough for sunrise and
/// sunset to within a few minutes, too coarse to place a person.
class RoughLocation {
  RoughLocation(double latitude, double longitude)
    : latitude = latitude.clamp(-90, 90).roundToDouble(),
      longitude = longitude.clamp(-180, 180).roundToDouble();

  final double latitude;

  /// East positive.
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is RoughLocation &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

/// The place with the most time spent there, rounded; null with none.
RoughLocation? roughLocationOfPlaces(PlaceStore store) {
  final Map<int, int> minutes = <int, int>{};
  for (final PlaceStay s in store.stays) {
    final DateTime? left = s.departure;
    if (left == null) continue;
    minutes[s.placeId] =
        (minutes[s.placeId] ?? 0) + left.difference(s.arrival).inMinutes;
  }
  Place? most;
  for (final Place p in store.places) {
    if ((minutes[p.id] ?? 0) <= 0) continue;
    if (most == null || minutes[p.id]! > minutes[most.id]!) most = p;
  }
  return most == null ? null : RoughLocation(most.latitude, most.longitude);
}

/// The representative city of time zone [zoneId] (an IANA name), rounded;
/// null for a zone not in the table.
RoughLocation? roughLocationOfZone(String? zoneId) {
  final (int, int)? at = zoneLocations[zoneId];
  return at == null ? null : RoughLocation(at.$1.toDouble(), at.$2.toDouble());
}

/// Sunrise and sunset on local calendar day [day] at [at], as UTC instants,
/// and the hours between. Null times on a day the sun stays up (24 hours) or
/// down (0). The sunrise equation with NOAA's terms: the Sun's upper limb on
/// the horizon, with refraction (-0.833°); good to a minute or two away from
/// the poles.
({DateTime? sunrise, DateTime? sunset, double hours}) sunTimes(
  DateTime day,
  RoughLocation at,
) {
  double rad(double d) => d * pi / 180;
  double deg(double r) => r * 180 / pi;
  final int n = DateTime.utc(
    day.year,
    day.month,
    day.day,
  ).difference(DateTime.utc(2000, 1, 1)).inDays;
  final double meanNoon = n - at.longitude / 360;
  final double m = (357.5291 + 0.98560028 * meanNoon) % 360;
  final double centre =
      1.9148 * sin(rad(m)) + 0.02 * sin(rad(2 * m)) + 0.0003 * sin(rad(3 * m));
  final double lambda = (m + centre + 180 + 102.9372) % 360;
  final double transit =
      2451545 + meanNoon + 0.0053 * sin(rad(m)) - 0.0069 * sin(rad(2 * lambda));
  final double sinDecl = sin(rad(lambda)) * sin(rad(23.4397));
  final double cosDecl = sqrt(1 - sinDecl * sinDecl);
  final double phi = rad(at.latitude);
  final double cosHour =
      (sin(rad(-0.833)) - sin(phi) * sinDecl) / (cos(phi) * cosDecl);
  if (cosHour <= -1) return (sunrise: null, sunset: null, hours: 24);
  if (cosHour >= 1) return (sunrise: null, sunset: null, hours: 0);
  final double hourAngle = deg(acos(cosHour));
  DateTime instant(double julian) => DateTime.fromMillisecondsSinceEpoch(
    ((julian - 2440587.5) * Duration.millisecondsPerDay).round(),
    isUtc: true,
  );
  return (
    sunrise: instant(transit - hourAngle / 360),
    sunset: instant(transit + hourAngle / 360),
    hours: hourAngle / 7.5,
  );
}

/// Each day's hours of daylight at [at], [from] through [through], held fixed
/// in the day-after comparisons where it adds what the month terms miss.
DayCondition dayLengths(
  RoughLocation at, {
  required DateTime from,
  required DateTime through,
}) => DayCondition.measure(
  id: dayLengthId,
  value: <DateTime, double>{
    for (DateTime d = startOfDay(from); !d.isAfter(through); d = addDays(d, 1))
      d: sunTimes(d, at).hours,
  },
);
