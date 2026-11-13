import 'package:tracker/data/day.dart';
import 'package:tracker/insights/places.dart';

// Photo times and coordinates stay on the device: only the stays derived
// here are kept, in the sealed device file `places`.

/// When and where one photo or video was taken, as the photo library says.
class PhotoPoint {
  const PhotoPoint({
    required this.at,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  });

  final DateTime at;
  final double latitude;
  final double longitude;

  /// In metres; zero or less when the library does not say.
  final double accuracy;
}

/// A run of photos at one place: evidence of a stay from its first photo to
/// its last.
class PhotoRun {
  const PhotoRun({
    required this.from,
    required this.to,
    required this.latitude,
    required this.longitude,
    required this.photos,
  });

  final DateTime from;
  final DateTime to;

  /// The mean of its photos' coordinates.
  final double latitude;
  final double longitude;
  final int photos;
}

/// The shortest run of photos taken as a stay: shots minutes apart are one
/// moment, not time spent somewhere.
const Duration photoStayMinSpan = Duration(minutes: 15);

/// The longest gap between two photos of one run: beyond it, nothing says
/// the person stayed rather than left and came back.
const Duration photoStayMaxGap = Duration(minutes: 90);

/// The stays [photos] give evidence of, oldest first: each run of two or more
/// photos taken one after another within [placeRadiusMeters] of the run's
/// first photo, on one local day, no more than [photoStayMaxGap] apart, and
/// spanning at least [photoStayMinSpan]. A photo elsewhere ends a run; a
/// lone photo, or a run shorter than that, gives nothing. Runs never overlap.
List<PhotoRun> photoRuns(Iterable<PhotoPoint> photos) {
  final List<PhotoPoint> sorted = <PhotoPoint>[
    for (final PhotoPoint p in photos)
      if (p.accuracy <= placeMaxAccuracyMeters &&
          p.latitude.isFinite &&
          p.longitude.isFinite &&
          p.latitude.abs() <= 90 &&
          p.longitude.abs() <= 180 &&
          !(p.latitude == 0 && p.longitude == 0))
        p,
  ]..sort((a, b) => a.at.compareTo(b.at));
  final List<PhotoRun> runs = <PhotoRun>[];
  List<PhotoPoint> run = <PhotoPoint>[];
  void close() {
    if (run.length >= 2 &&
        run.last.at.difference(run.first.at) >= photoStayMinSpan) {
      double lat = 0, lon = 0;
      for (final PhotoPoint p in run) {
        lat += p.latitude;
        lon += p.longitude;
      }
      runs.add(
        PhotoRun(
          from: run.first.at,
          to: run.last.at,
          latitude: lat / run.length,
          longitude: lon / run.length,
          photos: run.length,
        ),
      );
    }
    run = <PhotoPoint>[];
  }

  for (final PhotoPoint p in sorted) {
    if (run.isNotEmpty) {
      final PhotoPoint first = run.first;
      final bool joins =
          startOfDay(p.at) == startOfDay(first.at) &&
          p.at.difference(run.last.at) <= photoStayMaxGap &&
          distanceMeters(
                first.latitude,
                first.longitude,
                p.latitude,
                p.longitude,
              ) <=
              placeRadiusMeters;
      if (!joins) close();
    }
    run.add(p);
  }
  close();
  return runs;
}
