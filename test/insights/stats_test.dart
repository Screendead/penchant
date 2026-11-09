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
}
