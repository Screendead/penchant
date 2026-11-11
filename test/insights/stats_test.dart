import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/insights/stats.dart';

void main() {
  test('the t quantile matches published tables', () {
    expect(studentTQuantile(0.975, 1), closeTo(12.706, 0.001));
    expect(studentTQuantile(0.975, 10), closeTo(2.228, 0.001));
    expect(studentTQuantile(0.975, 30), closeTo(2.042, 0.001));
    expect(studentTQuantile(0.995, 5), closeTo(4.032, 0.001));
    expect(studentTQuantile(0.975, 1000), closeTo(1.962, 0.001));
    expect(studentTCdf(0, 7), closeTo(0.5, 1e-12));
  });

  test('the two-sided p-value matches the same tables', () {
    expect(studentTTwoSided(12.706, 1), closeTo(0.05, 1e-4));
    expect(studentTTwoSided(-2.228, 10), closeTo(0.05, 1e-4));
    expect(studentTTwoSided(4.032, 5), closeTo(0.01, 1e-4));
    expect(studentTTwoSided(0, 7), closeTo(1, 1e-12));
    expect(
      studentTTwoSided(1.3, 12),
      closeTo(2 * (1 - studentTCdf(1.3, 12)), 1e-12),
    );
    expect(studentTTwoSided(40, 100), greaterThan(0));
  });

  test('Benjamini-Hochberg keeps the 1995 paper\'s four of fifteen', () {
    const List<double> p = <double>[
      0.0001, 0.0004, 0.0019, 0.0095, 0.0201, 0.0278, 0.0298, 0.0344, //
      0.0459, 0.3240, 0.4262, 0.5719, 0.6528, 0.7590, 1.000,
    ];
    final List<bool> kept = benjaminiHochberg(p.reversed.toList(), 0.05);

    expect(kept.reversed.toList(), <bool>[
      for (int i = 0; i < p.length; i++) i < 4,
    ]);
  });

  test('Benjamini-Hochberg steps up: a value over its own line can pass', () {
    // 0.03 is above 1 x 0.05 / 2, but 0.04 is under 2 x 0.05 / 2.
    expect(benjaminiHochberg(<double>[0.04, 0.03], 0.05), <bool>[true, true]);
    expect(benjaminiHochberg(<double>[0.04, 0.6], 0.05), <bool>[false, false]);
    expect(benjaminiHochberg(<double>[], 0.05), isEmpty);
  });

  test('one 0/1 predictor gives the difference of means and the pooled SE', () {
    final List<double> on = <double>[5, 7, 6, 9, 8];
    final List<double> off = <double>[3, 4, 2, 5, 4, 3];
    final List<List<double>> rows = <List<double>>[
      for (final _ in on) <double>[1, 1],
      for (final _ in off) <double>[1, 0],
    ];
    final LinearFit fit = fitLeastSquares(rows, <double>[...on, ...off])!;

    expect(fit.coefficients[1], closeTo(mean(on) - mean(off), 1e-12));
    final int n1 = on.length, n2 = off.length;
    final double pooled =
        ((n1 - 1) * sampleVariance(on) + (n2 - 1) * sampleVariance(off)) /
        (n1 + n2 - 2);
    expect(
      fit.standardError(1),
      closeTo(sqrt(pooled * (1 / n1 + 1 / n2)), 1e-12),
    );
    expect(fit.degreesOfFreedom, n1 + n2 - 2);

    // The interval at level 1 - p ends at zero.
    final double p = fit.pValue(1);
    expect(p, inExclusiveRange(0, 0.05));
    expect(fit.interval(1, level: 1 - p).low, closeTo(0, 1e-9));
  });

  test('two identical columns make the design singular', () {
    final List<List<double>> rows = <List<double>>[
      for (int i = 0; i < 10; i++)
        <double>[1, i.isEven ? 1 : 0, i.isEven ? 1 : 0],
    ];

    expect(invert(gram(rows)), isNull);
    expect(
      fitLeastSquares(rows, List<double>.generate(10, (i) => i.toDouble())),
      isNull,
    );
  });
  double gaussian(Random r) =>
      sqrt(-2 * log(1 - r.nextDouble())) * cos(2 * pi * r.nextDouble());

  // Each value keeps [carry] of the one before.
  List<double> carrying(Random r, int n, double carry) {
    double last = 0;
    return <double>[
      for (int i = 0; i < n; i++) last = carry * last + gaussian(r),
    ];
  }

  List<int> everyDay(int n) => <int>[for (int i = 0; i < n; i++) i];

  test('partialling out gives back the coefficient and its variance', () {
    final Random random = Random(1);
    final List<List<double>> rows = <List<double>>[
      for (int i = 0; i < 80; i++)
        <double>[1, gaussian(random), i / 80, gaussian(random)],
    ];
    final List<double> y = <double>[
      for (final List<double> row in rows)
        3 + 2 * row[1] - row[2] + 0.5 * row[3] + gaussian(random),
    ];
    final LinearFit fit = fitLeastSquares(rows, y)!;
    final Partialled parts = partialOut(rows, y, fit, 1);
    double xy = 0, xx = 0;
    for (int r = 0; r < rows.length; r++) {
      xy +=
          parts.own[r] *
          (parts.own[r] * fit.coefficients[1] + parts.residual[r]);
      xx += parts.own[r] * parts.own[r];
    }
    expect(xy / xx, closeTo(fit.coefficients[1], 1e-9));
    expect(1 / xx, closeTo(fit.inverseGram[1][1], 1e-9));
  });

  test('days that resemble their neighbours count as fewer', () {
    final Random random = Random(2);
    final Partialled runs = (
      own: carrying(random, 400, 0.7),
      residual: carrying(random, 400, 0.7),
    );
    double inflation(Partialled parts, List<int> at) =>
        serialInflation(parts, at, minPairs: 14, maxCorrelation: 0.9);
    // (1 + 0.49) / (1 - 0.49) = 2.9 for the series themselves.
    expect(inflation(runs, everyDay(400)), inInclusiveRange(2.0, 4.2));
    final Partialled separate = (
      own: carrying(random, 400, 0),
      residual: carrying(random, 400, 0.7),
    );
    expect(inflation(separate, everyDay(400)), lessThan(1.3));
    // Rows two days apart are no neighbours, so nothing is corrected.
    expect(inflation(runs, <int>[for (int i = 0; i < 400; i++) 2 * i]), 1);
    // An alternating column against residuals that carry over would narrow
    // the interval: left alone.
    final Partialled alternating = (
      own: <double>[for (int i = 0; i < 400; i++) i.isEven ? 1 : -1],
      residual: runs.residual,
    );
    expect(inflation(alternating, everyDay(400)), 1);
  });

  test('a fit judged as fewer rows is wider, with fewer degrees of '
      'freedom', () {
    final Random random = Random(3);
    final List<List<double>> rows = <List<double>>[
      for (int i = 0; i < 60; i++) <double>[1, gaussian(random)],
    ];
    final LinearFit fit = fitLeastSquares(rows, <double>[
      for (final List<double> row in rows) row[1] + gaussian(random),
    ])!;
    expect(fit.judgedAs(1), same(fit));
    final LinearFit third = fit.judgedAs(3);
    expect(third.degreesOfFreedom, 60 ~/ 3 - 2);
    expect(
      third.standardError(1),
      closeTo(fit.standardError(1) * sqrt(3), 1e-12),
    );
    expect(third.pValue(1), greaterThan(fit.pValue(1)));
    expect(fit.judgedAs(100).degreesOfFreedom, 1);
  });

  Partialled through(List<double> own, List<double> y) {
    double xy = 0, xx = 0;
    for (int r = 0; r < own.length; r++) {
      xy += own[r] * y[r];
      xx += own[r] * own[r];
    }
    return (
      own: own,
      residual: <double>[
        for (int r = 0; r < own.length; r++) y[r] - own[r] * xy / xx,
      ],
    );
  }

  double slope(Partialled parts, List<double> y) {
    double xy = 0, xx = 0;
    for (int r = 0; r < y.length; r++) {
      xy += parts.own[r] * y[r];
      xx += parts.own[r] * parts.own[r];
    }
    return xy / xx;
  }

  Interval? redrawn(Partialled parts, double coefficient, List<int> at) =>
      blockBootstrapInterval(
        parts,
        coefficient,
        at,
        blockDays: 7,
        replicates: 2000,
        level: 0.95,
      );

  test('the block bootstrap interval covers a steady effect, the same '
      'every time', () {
    final Random random = Random(4);
    final List<double> own = carrying(random, 200, 0);
    final List<double> y = <double>[
      for (final double x in own) 0.5 * x + gaussian(random),
    ];
    final Partialled parts = through(own, y);
    final double coefficient = slope(parts, y);
    final Interval interval = redrawn(parts, coefficient, everyDay(200))!;
    expect(interval.low, lessThan(coefficient));
    expect(interval.high, greaterThan(coefficient));
    expect(interval.crossesZero, isFalse);
    // 2 x 1.96 / sqrt(200) = 0.28 for independent days.
    expect(interval.high - interval.low, inInclusiveRange(0.15, 0.45));
    final Interval again = redrawn(parts, coefficient, everyDay(200))!;
    expect(again.low, interval.low);
    expect(again.high, interval.high);
  });

  test('an effect that rests on one week does not survive redrawing the '
      'weeks', () {
    final Random random = Random(5);
    final List<double> own = <double>[
      for (int i = 0; i < 200; i++) random.nextBool() ? 1 : -1,
    ];
    final List<double> y = <double>[
      for (int i = 0; i < 200; i++)
        0.1 * gaussian(random) + (i >= 50 && i < 57 ? 8 * own[i] : 0),
    ];
    final Partialled parts = through(own, y);
    final double coefficient = slope(parts, y);
    expect(coefficient, greaterThan(0.2));
    expect(redrawn(parts, coefficient, everyDay(200))!.crossesZero, isTrue);
  });

  test('no block bootstrap when the days span less than a block', () {
    final Partialled parts = (
      own: <double>[1, -1, 1, -1],
      residual: <double>[0.1, 0.2, -0.1, 0],
    );
    expect(redrawn(parts, 1, <int>[0, 1, 2, 3]), isNull);
  });
}
