import 'dart:math';

/// The fewest days a measure must hold a level on each side of a shift.
const int minShiftSideDays = 14;

/// The most shifts looked for in one measure.
const int maxLevelShifts = 3;

/// A shift enters the habit models when its search's p-value is under this.
const double shiftSignificance = 0.05;

/// A lasting change in a measure's level: from [before] on the days back to
/// the previous shift (or the start) to [after] from [at] to the next one (or
/// the end).
class LevelShift {
  const LevelShift({
    required this.at,
    required this.before,
    required this.after,
    required this.daysBefore,
    required this.daysAfter,
    required this.pValue,
  });

  /// The first day with a value at the new level.
  final DateTime at;
  final double before;
  final double after;
  final int daysBefore;
  final int daysAfter;

  /// For no shift anywhere in the stretch searched, allowing for every place
  /// one was looked for and for each day resembling the one before.
  final double pValue;

  double get change => after - before;
}

class LevelShifts {
  const LevelShifts(this.shifts, this.pValue);

  static const LevelShifts none = LevelShifts(<LevelShift>[], null);

  /// By date.
  final List<LevelShift> shifts;

  /// The search over the whole series, whether or not it found a shift: one
  /// comparison in a report's family. Null when the series is too short to
  /// search.
  final double? pValue;
}

/// The lasting shifts in a measure's daily [values].
///
/// Each search splits a stretch of days in two at every place that leaves
/// [minShiftSideDays] on each side, and takes the split whose two means differ
/// most. Its t statistic is shrunk by the lag-1 autocorrelation of what the
/// split leaves, since a measure that wanders day to day makes levels of its
/// own; its p-value is Miller and Siegmund's for the largest of the statistics
/// over all the splits tried (Biometrics 38, 1982), not one split's. A stretch
/// that a straight line fits at least as well as the two levels is a drift,
/// not a shift. The clearest shift is taken first, then each side is searched
/// again, up to [maxLevelShifts].
LevelShifts levelShifts(Map<DateTime, double> values) {
  final List<DateTime> dates = values.keys.toList()..sort();
  final List<double> y = <double>[for (final DateTime d in dates) values[d]!];
  final _Split? whole = _clearestSplit(dates, y, 0, y.length);
  if (whole == null) return LevelShifts.none;

  final List<_Split> open = <_Split>[whole];
  final List<_Split> taken = <_Split>[];
  while (taken.length < maxLevelShifts && open.isNotEmpty) {
    open.sort((a, b) => a.pValue.compareTo(b.pValue));
    final _Split best = open.removeAt(0);
    if (best.pValue >= shiftSignificance) break;
    taken.add(best);
    for (final (int lo, int hi) in <(int, int)>[
      (best.lo, best.at),
      (best.at, best.hi),
    ]) {
      final _Split? next = _clearestSplit(dates, y, lo, hi);
      if (next != null) open.add(next);
    }
  }
  taken.sort((a, b) => a.at.compareTo(b.at));
  final List<int> edges = <int>[
    0,
    for (final _Split s in taken) s.at,
    y.length,
  ];
  double level(int lo, int hi) {
    double sum = 0;
    for (int i = lo; i < hi; i++) {
      sum += y[i];
    }
    return sum / (hi - lo);
  }

  return LevelShifts(<LevelShift>[
    for (int k = 0; k < taken.length; k++)
      LevelShift(
        at: dates[taken[k].at],
        before: level(edges[k], edges[k + 1]),
        after: level(edges[k + 1], edges[k + 2]),
        daysBefore: edges[k + 1] - edges[k],
        daysAfter: edges[k + 2] - edges[k + 1],
        pValue: taken[k].pValue,
      ),
  ], whole.pValue);
}

class _Split {
  const _Split(this.lo, this.at, this.hi, this.pValue);

  // The stretch searched is [lo, hi); the new level starts at [at].
  final int lo;
  final int at;
  final int hi;
  final double pValue;
}

// The clearest split of y[lo, hi), or null when the stretch is too short or
// flat.
_Split? _clearestSplit(List<DateTime> dates, List<double> y, int lo, int hi) {
  final int n = hi - lo;
  if (n < 2 * minShiftSideDays) return null;
  double sum = 0;
  for (int i = lo; i < hi; i++) {
    sum += y[i];
  }
  final double m = sum / n;
  double total = 0;
  for (int i = lo; i < hi; i++) {
    total += (y[i] - m) * (y[i] - m);
  }
  if (total <= 0) return null;

  int at = -1;
  double between = 0, left = 0;
  for (int k = lo + 1; k <= hi - minShiftSideDays; k++) {
    left += y[k - 1];
    if (k < lo + minShiftSideDays) continue;
    final int nl = k - lo, nr = hi - k;
    final double gap = (sum - left) / nr - left / nl;
    final double b = nl * nr / n * gap * gap;
    if (b > between) {
      between = b;
      at = k;
    }
  }
  if (at < 0 || between >= total) return _Split(lo, max(at, lo), hi, 1);

  // What a straight line over the dates explains.
  final double t0 = dates[lo].millisecondsSinceEpoch.toDouble();
  double st = 0;
  for (int i = lo; i < hi; i++) {
    st += dates[i].millisecondsSinceEpoch - t0;
  }
  final double mt = st / n;
  double sxx = 0, sxy = 0;
  for (int i = lo; i < hi; i++) {
    final double t = dates[i].millisecondsSinceEpoch - t0 - mt;
    sxx += t * t;
    sxy += t * (y[i] - m);
  }
  if (sxx > 0 && sxy * sxy / sxx >= between) return _Split(lo, at, hi, 1);

  double leftMean = 0, rightMean = 0;
  for (int i = lo; i < hi; i++) {
    if (i < at) {
      leftMean += y[i];
    } else {
      rightMean += y[i];
    }
  }
  leftMean /= at - lo;
  rightMean /= hi - at;
  double lagged = 0, squares = 0, previous = 0;
  for (int i = lo; i < hi; i++) {
    final double e = y[i] - (i < at ? leftMean : rightMean);
    squares += e * e;
    if (i > lo) lagged += e * previous;
    previous = e;
  }
  // Clamped as in unevenHalves: a negative value would sharpen the test, and
  // one near 1 leaves no evidence at all.
  final double rho = squares == 0 ? 0 : (lagged / squares).clamp(0.0, 0.9);
  final int df = n - 2;
  final double t =
      sqrt(between / ((total - between) / df)) * sqrt((1 - rho) / (1 + rho));
  // Student's t as a normal deviate, the form Miller and Siegmund's
  // approximation takes.
  final double z = t * (1 - 1 / (4 * df)) / sqrt(1 + t * t / (2 * df));
  return _Split(lo, at, hi, _largestOfSplits(z, minShiftSideDays / n));
}

// The chance that the largest standardised difference over every split
// leaving a share [trim] of the days on each side exceeds [z] when there is
// no shift.
double _largestOfSplits(double z, double trim) {
  if (z <= 1) return 1;
  final double density = exp(-z * z / 2) / sqrt(2 * pi);
  final double reach = 2 * log((1 - trim) / trim);
  return min(1, 4 * density / z + density * (z - 1 / z) * reach);
}
