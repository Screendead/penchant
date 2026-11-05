import 'dart:math';
import 'dart:ui' show Size;

// An axis that ends on a round number of units: [top] is a multiple of [step],
// at least [largest], in at most [maxSteps] steps of 1, 2 or 5 times a power
// of ten. fl_chart labels the axis maximum as well as each interval, so a top
// that is not a multiple of the step prints a second, colliding label.
({int top, int step}) roundScale(int largest, int maxSteps) {
  assert(maxSteps >= 1);
  for (int magnitude = 1; ; magnitude *= 10) {
    for (final int multiple in const [1, 2, 5]) {
      final int step = multiple * magnitude;
      final int steps = (largest + step - 1) ~/ step;

      if (steps <= maxSteps) {
        return (top: max(steps, 1) * step, step: step);
      }
    }
  }
}

// How many labels fit along [extent] when each takes [labelExtent] and the
// outermost are pushed inside the axis: a label shifted inward by half its
// extent still clears its neighbour when centres are 1.5 labels apart.
int labelsThatFit(double extent, double labelExtent, {double gap = 8}) =>
    max(1, 1 + extent ~/ (1.5 * labelExtent + gap));

// The indices of [count] evenly spaced points to label, at most [maxLabels] of
// them, counted back from the last so the newest point is always labelled.
List<int> labelIndices(int count, int maxLabels) {
  if (count <= 0) {
    return const <int>[];
  }
  if (count == 1 || maxLabels <= 1) {
    return <int>[count - 1];
  }

  final int step = ((count - 1) / (maxLabels - 1)).ceil();
  return <int>[for (int i = (count - 1) % step; i < count; i += step) i];
}

// The length a radar title may take. fl_chart draws each title tangent to a
// circle [titleOffset] beyond the radar's radius (0.8 of the shorter half
// side), so a title is bounded by the chord to its neighbours' positions and by
// the chart's width.
double radarTitleWidth(Size size, int axes, double titleOffset) {
  final double radius = min(size.width, size.height) / 2 * 0.8;
  final double titleRadius = radius * (1 + titleOffset);
  if (axes <= 1) {
    return size.width;
  }
  return min(size.width, 2 * titleRadius * sin(pi / axes));
}
