import 'dart:math';

double mean(List<double> values) =>
    values.fold<double>(0, (sum, v) => sum + v) / values.length;

// The n - 1 (sample) variance; 0 for fewer than two values.
double sampleVariance(List<double> values) {
  if (values.length < 2) return 0;
  final double m = mean(values);
  return values.fold<double>(0, (sum, v) => sum + (v - m) * (v - m)) /
      (values.length - 1);
}

// The [q] quantile by linear interpolation between order statistics (R's
// type 7: the sorted value at fractional index (n - 1) * q, so the 10th
// percentile is q = 0.1). [values] must not be empty.
double quantile(List<double> values, double q) {
  final List<double> sorted = values.toList()..sort();
  final double h = (sorted.length - 1) * q;
  final int lo = h.floor();
  final int hi = min(lo + 1, sorted.length - 1);
  return sorted[lo] + (h - lo) * (sorted[hi] - sorted[lo]);
}

// [quantile]'s interquartile range; 0 for fewer than two values.
double interquartileRange(List<double> values) =>
    values.length < 2 ? 0 : quantile(values, 0.75) - quantile(values, 0.25);

double median(List<double> values) {
  final List<double> sorted = values.toList()..sort();
  final int mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

class Interval {
  const Interval(this.low, this.high);

  final double low;
  final double high;

  bool get crossesZero => low <= 0 && high >= 0;

  @override
  String toString() => '[$low, $high]';
}

// Lanczos approximation (g = 7, n = 9), accurate to about 15 digits for x > 0.
double _logGamma(double x) {
  const List<double> c = <double>[
    0.99999999999980993,
    676.5203681218851,
    -1259.1392167224028,
    771.32342877765313,
    -176.61502916214059,
    12.507343278686905,
    -0.13857109526572012,
    9.9843695780195716e-6,
    1.5056327351493116e-7,
  ];
  if (x < 0.5) {
    return log(pi / sin(pi * x)) - _logGamma(1 - x);
  }
  final double z = x - 1;
  double a = c[0];
  final double t = z + 7.5;
  for (int i = 1; i < 9; i++) {
    a += c[i] / (z + i);
  }
  return 0.5 * log(2 * pi) + (z + 0.5) * log(t) - t + log(a);
}

// Continued fraction for the incomplete beta function, by the modified Lentz
// method (Numerical Recipes, betacf).
double _betaContinuedFraction(double a, double b, double x) {
  const double tiny = 1e-300;
  final double qab = a + b, qap = a + 1, qam = a - 1;
  double c = 1, d = 1 - qab * x / qap;
  if (d.abs() < tiny) d = tiny;
  d = 1 / d;
  double h = d;
  for (int m = 1; m <= 300; m++) {
    final int m2 = 2 * m;
    double aa = m * (b - m) * x / ((qam + m2) * (a + m2));
    d = 1 + aa * d;
    if (d.abs() < tiny) d = tiny;
    c = 1 + aa / c;
    if (c.abs() < tiny) c = tiny;
    d = 1 / d;
    h *= d * c;
    aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2));
    d = 1 + aa * d;
    if (d.abs() < tiny) d = tiny;
    c = 1 + aa / c;
    if (c.abs() < tiny) c = tiny;
    d = 1 / d;
    final double del = d * c;
    h *= del;
    if ((del - 1).abs() < 1e-14) break;
  }
  return h;
}

double _regularizedIncompleteBeta(double a, double b, double x) {
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  final double front = exp(
    _logGamma(a + b) -
        _logGamma(a) -
        _logGamma(b) +
        a * log(x) +
        b * log(1 - x),
  );
  return x < (a + 1) / (a + b + 2)
      ? front * _betaContinuedFraction(a, b, x) / a
      : 1 - front * _betaContinuedFraction(b, a, 1 - x) / b;
}

double studentTCdf(double t, double degreesOfFreedom) {
  final double tail =
      0.5 *
      _regularizedIncompleteBeta(
        degreesOfFreedom / 2,
        0.5,
        degreesOfFreedom / (degreesOfFreedom + t * t),
      );
  return t >= 0 ? 1 - tail : tail;
}

// P(|T| >= |t|), from the incomplete beta directly so that small values keep
// their digits.
double studentTTwoSided(double t, double degreesOfFreedom) =>
    _regularizedIncompleteBeta(
      degreesOfFreedom / 2,
      0.5,
      degreesOfFreedom / (degreesOfFreedom + t * t),
    );

/// Which of [pValues] Benjamini-Hochberg keeps at false-discovery rate [q]:
/// with the values sorted, every one at or below the largest p(k) <= k q / m.
List<bool> benjaminiHochberg(List<double> pValues, double q) {
  final int m = pValues.length;
  final List<double> sorted = pValues.toList()..sort();
  double? cutoff;
  for (int k = m; k >= 1; k--) {
    if (sorted[k - 1] <= k * q / m) {
      cutoff = sorted[k - 1];
      break;
    }
  }
  return <bool>[for (final double p in pValues) cutoff != null && p <= cutoff];
}

// The t value below which a fraction [p] of the distribution lies, for p in
// [0.5, 1), found by bisection on the CDF.
double studentTQuantile(double p, double degreesOfFreedom) {
  double low = 0, high = 1;
  while (studentTCdf(high, degreesOfFreedom) < p) {
    high *= 2;
  }
  for (int i = 0; i < 200; i++) {
    final double mid = (low + high) / 2;
    if (studentTCdf(mid, degreesOfFreedom) < p) {
      low = mid;
    } else {
      high = mid;
    }
  }
  return (low + high) / 2;
}

// Inverts a symmetric positive semi-definite matrix by Gauss-Jordan
// elimination with partial pivoting; null when a pivot falls below a
// relative tolerance, which is how exactly collinear columns show up.
List<List<double>>? invert(List<List<double>> matrix) {
  final int n = matrix.length;
  final List<List<double>> a = <List<double>>[
    for (int i = 0; i < n; i++)
      <double>[...matrix[i], for (int j = 0; j < n; j++) i == j ? 1.0 : 0.0],
  ];
  double scale = 0;
  for (int i = 0; i < n; i++) {
    scale = max(scale, matrix[i][i].abs());
  }
  final double tolerance = 1e-10 * (scale == 0 ? 1 : scale);
  for (int col = 0; col < n; col++) {
    int pivot = col;
    for (int row = col + 1; row < n; row++) {
      if (a[row][col].abs() > a[pivot][col].abs()) pivot = row;
    }
    if (a[pivot][col].abs() < tolerance) return null;
    final List<double> swap = a[col];
    a[col] = a[pivot];
    a[pivot] = swap;
    final double p = a[col][col];
    for (int j = 0; j < 2 * n; j++) {
      a[col][j] /= p;
    }
    for (int row = 0; row < n; row++) {
      if (row == col) continue;
      final double f = a[row][col];
      if (f == 0) continue;
      for (int j = 0; j < 2 * n; j++) {
        a[row][j] -= f * a[col][j];
      }
    }
  }
  return <List<double>>[for (final List<double> row in a) row.sublist(n)];
}

List<List<double>> gram(List<List<double>> rows) {
  final int p = rows.first.length;
  final List<List<double>> g = List<List<double>>.generate(
    p,
    (_) => List<double>.filled(p, 0),
  );
  for (final List<double> row in rows) {
    for (int i = 0; i < p; i++) {
      for (int j = 0; j < p; j++) {
        g[i][j] += row[i] * row[j];
      }
    }
  }
  return g;
}

class LinearFit {
  const LinearFit({
    required this.coefficients,
    required this.inverseGram,
    required this.residualVariance,
    required this.degreesOfFreedom,
  });

  final List<double> coefficients;
  final List<List<double>> inverseGram;
  final double residualVariance;
  final int degreesOfFreedom;

  double standardError(int j) => sqrt(residualVariance * inverseGram[j][j]);

  Interval interval(int j, {double level = 0.95}) {
    final double half =
        studentTQuantile(1 - (1 - level) / 2, degreesOfFreedom.toDouble()) *
        standardError(j);
    return Interval(coefficients[j] - half, coefficients[j] + half);
  }

  /// Two-sided, for the hypothesis that coefficient [j] is zero.
  double pValue(int j) {
    final double se = standardError(j);
    if (se == 0) return coefficients[j] == 0 ? 1 : 0;
    return studentTTwoSided(coefficients[j] / se, degreesOfFreedom.toDouble());
  }

  /// This fit judged as [inflation] times fewer rows than it has (see
  /// [serialInflation]): the variance that many times larger, and the degrees
  /// of freedom those of the smaller sample, never under one.
  LinearFit judgedAs(double inflation) {
    if (inflation <= 1) return this;
    final int columns = coefficients.length;
    return LinearFit(
      coefficients: coefficients,
      inverseGram: inverseGram,
      residualVariance: residualVariance * inflation,
      degreesOfFreedom: max(
        1,
        ((degreesOfFreedom + columns) / inflation).floor() - columns,
      ),
    );
  }
}

/// One coefficient of a fit with every other column taken out of both sides
/// (Frisch-Waugh): per row, what is left of the column, and of the outcome
/// once the whole fit is taken out. The coefficient is the sum of
/// own × (own × coefficient + residual) over the sum of own squared.
typedef Partialled = ({List<double> own, List<double> residual});

Partialled partialOut(
  List<List<double>> rows,
  List<double> y,
  LinearFit fit,
  int column,
) {
  final List<double> toward = fit.inverseGram[column];
  final double scale = toward[column];
  final List<double> own = <double>[], residual = <double>[];
  for (int r = 0; r < rows.length; r++) {
    final List<double> row = rows[r];
    double part = 0, fitted = 0;
    for (int j = 0; j < row.length; j++) {
      part += toward[j] * row[j];
      fitted += fit.coefficients[j] * row[j];
    }
    own.add(scale == 0 ? 0 : part / scale);
    residual.add(y[r] - fitted);
  }
  return (own: own, residual: residual);
}

// The correlation of [values] with themselves a day earlier, over the rows
// whose day in [at] follows the row before's; null under [minPairs] of them.
double? _lagOne(List<double> values, List<int> at, int minPairs) {
  int pairs = 0;
  double lagged = 0, now = 0, before = 0;
  for (int r = 1; r < values.length; r++) {
    if (at[r] - at[r - 1] != 1) continue;
    pairs++;
    lagged += values[r] * values[r - 1];
    now += values[r] * values[r];
    before += values[r - 1] * values[r - 1];
  }
  if (pairs < minPairs) return null;
  return now == 0 || before == 0 ? 0 : lagged / sqrt(now * before);
}

/// How many times fewer independent rows than rows a coefficient rests on
/// when neighbouring days resemble each other: n / n_eff = (1 + r) / (1 - r),
/// r being the lag-1 autocorrelation of the column times that of the
/// residuals (Bartlett's effective sample size). [at] is each row's day,
/// counted from any fixed day, in order; only rows a day apart are compared,
/// and with fewer than [minPairs] such pairs nothing is corrected. r is
/// clamped to [0, maxCorrelation]: a negative one would narrow the interval.
double serialInflation(
  Partialled parts,
  List<int> at, {
  required int minPairs,
  required double maxCorrelation,
}) {
  final double? own = _lagOne(parts.own, at, minPairs);
  final double? residual = _lagOne(parts.residual, at, minPairs);
  if (own == null || residual == null) return 1;
  final double r = (own * residual).clamp(0.0, maxCorrelation);
  return (1 + r) / (1 - r);
}

/// A moving-block bootstrap percentile interval at [level] for a coefficient
/// (Künsch 1989): the rows are redrawn in whole blocks of [blockDays]
/// calendar days, so a stretch of days that resemble each other stays
/// together, and the coefficient is recomputed from [parts] each time, the
/// other columns' fit held as it was. A block is the rows from one row's day
/// up to [blockDays] days later, however many of those days have a row;
/// blocks are drawn until they hold as many rows as there are. The draws are
/// seeded, so the same rows always give the same interval. Null when no block
/// fits or [replicates] is under 1.
Interval? blockBootstrapInterval(
  Partialled parts,
  double coefficient,
  List<int> at, {
  required int blockDays,
  required int replicates,
  required double level,
}) {
  final int n = at.length;
  if (replicates < 1 || n == 0) return null;
  // Running sums, so a block's share of each is a difference of two.
  final List<double> cross = List<double>.filled(n + 1, 0);
  final List<double> squares = List<double>.filled(n + 1, 0);
  for (int r = 0; r < n; r++) {
    final double x = parts.own[r];
    cross[r + 1] = cross[r] + x * (x * coefficient + parts.residual[r]);
    squares[r + 1] = squares[r] + x * x;
  }
  final List<int> starts = <int>[], ends = <int>[];
  int end = 0;
  for (int r = 0; r < n && at[r] + blockDays - 1 <= at.last; r++) {
    while (end < n && at[end] < at[r] + blockDays) {
      end++;
    }
    starts.add(r);
    ends.add(end);
  }
  if (starts.isEmpty) return null;
  final Random random = Random(_bootstrapSeed);
  final List<double> estimates = <double>[];
  for (int b = 0; b < replicates; b++) {
    double xy = 0, xx = 0;
    for (int drawn = 0; drawn < n;) {
      final int k = random.nextInt(starts.length);
      xy += cross[ends[k]] - cross[starts[k]];
      xx += squares[ends[k]] - squares[starts[k]];
      drawn += ends[k] - starts[k];
    }
    if (xx > 0) estimates.add(xy / xx);
  }
  if (estimates.isEmpty) return null;
  return Interval(
    quantile(estimates, (1 - level) / 2),
    quantile(estimates, 1 - (1 - level) / 2),
  );
}

const int _bootstrapSeed = 20261111;

// Ordinary least squares by the normal equations. Null when the design is
// singular or leaves no residual degrees of freedom.
LinearFit? fitLeastSquares(List<List<double>> rows, List<double> y) {
  final int n = rows.length, p = rows.first.length;
  if (n <= p) return null;
  final List<List<double>>? inverse = invert(gram(rows));
  if (inverse == null) return null;
  final List<double> xty = List<double>.filled(p, 0);
  for (int r = 0; r < n; r++) {
    for (int j = 0; j < p; j++) {
      xty[j] += rows[r][j] * y[r];
    }
  }
  final List<double> beta = <double>[
    for (int i = 0; i < p; i++)
      <double>[
        for (int j = 0; j < p; j++) inverse[i][j] * xty[j],
      ].fold<double>(0, (s, v) => s + v),
  ];
  double rss = 0;
  for (int r = 0; r < n; r++) {
    double fitted = 0;
    for (int j = 0; j < p; j++) {
      fitted += rows[r][j] * beta[j];
    }
    rss += (y[r] - fitted) * (y[r] - fitted);
  }
  return LinearFit(
    coefficients: beta,
    inverseGram: inverse,
    residualVariance: rss / (n - p),
    degreesOfFreedom: n - p,
  );
}

double correlation(List<double> x, List<double> y) {
  final double mx = mean(x), my = mean(y);
  double sxy = 0, sxx = 0, syy = 0;
  for (int i = 0; i < x.length; i++) {
    sxy += (x[i] - mx) * (y[i] - my);
    sxx += (x[i] - mx) * (x[i] - mx);
    syy += (y[i] - my) * (y[i] - my);
  }
  return sxx == 0 || syy == 0 ? 0 : sxy / sqrt(sxx * syy);
}
