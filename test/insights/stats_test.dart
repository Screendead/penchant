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
