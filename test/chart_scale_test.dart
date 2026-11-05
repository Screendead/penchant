import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/chart_scale.dart';

void main() {
  group('roundScale', () {
    test('ends on a multiple of a round step', () {
      expect(roundScale(1, 4), (top: 1, step: 1));
      expect(roundScale(2, 4), (top: 2, step: 1));
      expect(roundScale(5, 4), (top: 6, step: 2));
      expect(roundScale(1380, 4), (top: 1500, step: 500));
      expect(roundScale(0, 4), (top: 1, step: 1));
    });

    test('never needs fl_chart to add a label at the maximum', () {
      for (final int maxSteps in const [1, 2, 3, 4, 5]) {
        for (int largest = 0; largest <= 2000; largest++) {
          final ({int top, int step}) scale = roundScale(largest, maxSteps);
          expect(scale.top, greaterThanOrEqualTo(largest));
          expect(scale.top % scale.step, 0);
          expect(scale.top ~/ scale.step, inInclusiveRange(1, maxSteps));
        }
      }
    });
  });

  group('labelIndices', () {
    test('always labels the newest point', () {
      for (int count = 1; count <= 365; count++) {
        for (final int maxLabels in const [1, 2, 3, 5, 8]) {
          final List<int> indices = labelIndices(count, maxLabels);
          expect(indices.last, count - 1);
          expect(indices.first, greaterThanOrEqualTo(0));
          expect(indices.length, lessThanOrEqualTo(maxLabels));
          final Set<int> gaps = <int>{
            for (int i = 1; i < indices.length; i++)
              indices[i] - indices[i - 1],
          };
          expect(gaps.length, lessThanOrEqualTo(1), reason: '$indices');
        }
      }
    });

    test('a month of days at five labels', () {
      // fl_chart's own interval labelled 0, 7, 14, 21, 28 and then 29.
      expect(labelIndices(30, 5), [5, 13, 21, 29]);
    });

    test('nothing to label', () {
      expect(labelIndices(0, 5), isEmpty);
      expect(labelIndices(1, 5), [0]);
    });
  });

  test('labelsThatFit leaves room for the edge labels to move inward', () {
    expect(labelsThatFit(300, 40), 1 + 300 ~/ 68);
    expect(labelsThatFit(10, 40), 1);
    // Centres this far apart keep a label shifted by half its width clear.
    final int n = labelsThatFit(300, 40);
    expect(300 / (n - 1), greaterThanOrEqualTo(1.5 * 40 + 8));
  });

  test('radarTitleWidth is the chord between neighbouring titles', () {
    const Size size = Size(300, 300);
    // Radius 120, titles at 144: three axes are 144 * sqrt(3) apart.
    expect(radarTitleWidth(size, 3, 0.2), closeTo(249.4, 0.1));
    expect(radarTitleWidth(size, 12, 0.2), closeTo(74.5, 0.1));
    expect(radarTitleWidth(const Size(200, 1000), 3, 0.2), closeTo(166.3, 0.1));
  });
}
