import 'dart:math';
import 'dart:ui' show PathMetric, Tangent;

import 'package:flutter/material.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';

// One habit mark: a filled disc for habits 1-5, a ring for 6-10 and a dotted
// ring for 11-15, and a pending entry's a turning dashed rim. [fill] grows a
// filled mark from its centre. A filled mark holds 3:1 against its ground by
// its inner rim in light and by its own fill in dark, where it also glows. A
// [dim] filled mark (a zero tally's pip) is its fill at 40% inside a 1 pt rim
// of its ink at 70%, which holds 3:1 in both themes (contrast-pairs.json).
void paintHabitMark(
  Canvas canvas,
  Offset centre,
  double radius,
  HabitMark mark,
  DialColors colors, {
  double fill = 1,
  bool pending = false,
  double rotation = 0,
  double? rimWidth,
  bool dim = false,
}) {
  final Color hue = colors.habit(mark);
  final Color ink = colors.habitInk(mark);
  final BeadTreatment bead = colors.bead;

  if (pending || mark.style != HabitMarkStyle.filled) {
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = ink;
    if (pending) {
      _paintDashed(
        canvas,
        centre,
        radius - 1,
        stroke..strokeWidth = 2,
        dash: 3.2,
        gap: 2.6,
        rotation: rotation,
      );
    } else if (mark.style == HabitMarkStyle.ring) {
      canvas.drawCircle(centre, radius - 1.2, stroke..strokeWidth = 2.4);
    } else {
      _paintDashed(
        canvas,
        centre,
        radius - 1.2,
        stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round,
        dash: 0.01,
        gap: 4,
      );
    }
    return;
  }
  if (dim) {
    canvas
      ..drawCircle(centre, radius, Paint()..color = hue.withValues(alpha: 0.4))
      ..drawCircle(
        centre,
        radius - 0.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = ink.withValues(alpha: 0.7),
      );
    return;
  }
  _paintFilled(
    canvas,
    centre,
    radius * fill,
    hue,
    ink,
    bead,
    rimWidth ?? bead.rimWidth,
  );
}

// A habit's mark drawn over a shape rather than a circle, for its share of a
// dense hour's arc: filled with the bead's rim or glow, or the ring's or the
// dotted ring's outline, each kept inside the shape. A [pending] share is
// hollow with a dashed rim, as a pending bead, its dashes moved along by
// [rotation].
void paintHabitBand(
  Canvas canvas,
  Path shape,
  HabitMark mark,
  DialColors colors, {
  bool pending = false,
  double rotation = 0,
}) {
  final Color hue = colors.habit(mark);
  final Color ink = colors.habitInk(mark);
  final BeadTreatment bead = colors.bead;
  if (pending) {
    const double dash = 3.2;
    const double period = dash + 2.6;
    final double phase = (rotation / (2 * pi) * period * 4) % period;
    final Path dashes = Path();
    for (final PathMetric metric in shape.computeMetrics()) {
      for (double d = phase - period; d < metric.length; d += period) {
        dashes.addPath(
          metric.extractPath(max(0, d), min(metric.length, d + dash)),
          Offset.zero,
        );
      }
    }
    _strokeInside(
      canvas,
      shape,
      Paint()
        ..strokeWidth = 2 * 2
        ..color = ink,
      dashes,
    );
    return;
  }
  switch (mark.style) {
    case HabitMarkStyle.filled:
      if (bead.glowAlpha > 0) {
        canvas.drawPath(
          shape,
          Paint()
            ..color = hue.withValues(alpha: bead.glowAlpha)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, bead.glowBlur / 2),
        );
      }
      canvas.drawPath(shape, Paint()..color = hue);
      if (bead.rimWidth > 0) {
        _strokeInside(
          canvas,
          shape,
          Paint()
            ..strokeWidth = bead.rimWidth * 2
            ..color = ink.withValues(alpha: bead.rimAlpha),
        );
      }
    case HabitMarkStyle.ring:
      _strokeInside(
        canvas,
        shape,
        Paint()
          ..strokeWidth = 2.4 * 2
          ..color = ink,
      );
    case HabitMarkStyle.dotted:
      final Paint dot = Paint()..color = ink;
      for (final PathMetric metric in shape.computeMetrics()) {
        for (double d = 0; d < metric.length; d += 4.01) {
          if (metric.getTangentForOffset(d) case final Tangent t) {
            // A quarter-turn of the tangent, whichever way points inside.
            final Offset normal = Offset(-t.vector.dy, t.vector.dx) * 1.2;
            canvas.drawCircle(
              shape.contains(t.position + normal)
                  ? t.position + normal
                  : t.position - normal,
              1.2,
              dot,
            );
          }
        }
      }
  }
}

void _strokeInside(Canvas canvas, Path shape, Paint paint, [Path? stroke]) {
  canvas
    ..save()
    ..clipPath(shape)
    ..drawPath(stroke ?? shape, paint..style = PaintingStyle.stroke)
    ..restore();
}

void _paintFilled(
  Canvas canvas,
  Offset centre,
  double radius,
  Color hue,
  Color ink,
  BeadTreatment bead,
  double rimWidth,
) {
  if (bead.glowAlpha > 0 && radius > 0) {
    canvas.drawCircle(
      centre,
      radius + bead.glowRadius / 4,
      Paint()
        ..color = hue.withValues(alpha: bead.glowAlpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, bead.glowBlur / 2),
    );
  }
  canvas.drawCircle(centre, radius, Paint()..color = hue);
  if (rimWidth > 0 && radius > rimWidth) {
    canvas.drawCircle(
      centre,
      radius - rimWidth / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rimWidth
        ..color = ink.withValues(alpha: bead.rimAlpha),
    );
  }
}

void _paintDashed(
  Canvas canvas,
  Offset centre,
  double radius,
  Paint paint, {
  required double dash,
  required double gap,
  double rotation = 0,
}) {
  if (radius <= 0) {
    return;
  }
  final double circumference = 2 * pi * radius;
  final int count = max(1, (circumference / (dash + gap)).floor());
  final double step = 2 * pi / count;
  final double sweep = step * dash / (dash + gap);
  final Rect rect = Rect.fromCircle(center: centre, radius: radius);
  for (int i = 0; i < count; i++) {
    canvas.drawArc(rect, rotation + i * step, sweep, false, paint);
  }
}

// A pip: the habit's mark at a fixed size, for rows and keys. Its rim is
// 1 pt, so a 10 pt pip reads as a solid dot. [dim] fades a zero row's.
class HabitPip extends StatelessWidget {
  const HabitPip({
    super.key,
    required this.mark,
    this.size = 10,
    this.dim = false,
  });

  final HabitMark mark;
  final double size;
  final bool dim;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _PipPainter(mark, DialColors.of(context), dim: dim),
    ),
  );
}

class _PipPainter extends CustomPainter {
  _PipPainter(this.mark, this.colors, {required this.dim});

  final HabitMark mark;
  final DialColors colors;
  final bool dim;

  @override
  void paint(Canvas canvas, Size size) => paintHabitMark(
    canvas,
    size.center(Offset.zero),
    size.shortestSide / 2,
    mark,
    colors,
    rimWidth: 1,
    dim: dim,
  );

  @override
  bool shouldRepaint(_PipPainter old) =>
      old.mark != mark || old.colors != colors || old.dim != dim;
}
