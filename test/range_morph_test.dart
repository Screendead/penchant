import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/trends/trends_chart.dart';

void main() {
  test('resampleSeries keeps the ends and joins neighbours with lines', () {
    expect(resampleSeries(<double>[0, 10], 5), <double>[0, 2.5, 5, 7.5, 10]);
    expect(resampleSeries(<double>[3], 4), <double>[3, 3, 3, 3]);
    final List<double> week = <double>[1, 4, 2, 0, 5, 3, 6];
    final List<double> out = resampleSeries(week, RangeMorph.samples);
    expect(out, hasLength(RangeMorph.samples));
    expect(out.first, 1);
    expect(out.last, 6);
    // 221 points over 6 gaps put one on every bucket.
    expect(out[110], week[3]);
  });

  group('a change of range', () {
    final List<MorphFrame?> frames = <MorphFrame?>[];
    final List<bool> tweens = <bool>[];

    Widget morph(int days, List<double> totals, {bool reduced = false}) =>
        MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: RangeMorph(
            shape: (days: days, stepDays: 1),
            totals: totals,
            smoothed: null,
            top: totals.reduce((double a, double b) => a > b ? a : b),
            builder: (BuildContext context, MorphFrame? frame, bool tween) {
              frames.add(frame);
              tweens.add(tween);
              return const SizedBox();
            },
          ),
        );

    setUp(() {
      frames.clear();
      tweens.clear();
    });

    testWidgets('eases one shape into the other over 450 ms', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(morph(7, List<double>.filled(7, 2)));
      expect(frames.last, isNull);
      await tester.pumpWidget(morph(30, List<double>.filled(30, 6)));
      await tester.pump(const Duration(milliseconds: 225));
      final MorphFrame mid = frames.last!;
      expect(mid.totals, hasLength(RangeMorph.samples));
      expect(mid.totals.first, inExclusiveRange(2, 6));
      expect(mid.top, inExclusiveRange(2, 6));
      expect(tweens.last, isFalse);
      await tester.pump(const Duration(milliseconds: 230));
      await tester.pump();
      expect(frames.last, isNull);
      // The swap to the range's own 30 spots must not tween from 221.
      expect(tweens.last, isFalse);
    });

    testWidgets('a change within the same range is left to fl_chart', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(morph(7, List<double>.filled(7, 2)));
      await tester.pumpWidget(morph(7, List<double>.filled(7, 4)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(frames.last, isNull);
    });

    testWidgets('jumps under reduce motion', (WidgetTester tester) async {
      await tester.pumpWidget(
        morph(7, List<double>.filled(7, 2), reduced: true),
      );
      await tester.pumpWidget(
        morph(30, List<double>.filled(30, 6), reduced: true),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(frames.last, isNull);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}
