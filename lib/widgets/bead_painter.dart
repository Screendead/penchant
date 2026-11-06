import 'dart:math';

import 'package:flutter/material.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';

// One habit mark: a filled disc for habits 1-5, a ring for 6-10 and a dotted
// ring for 11-15, and a pending entry's a turning dashed rim. [fill] grows a
// filled mark from its centre. A filled mark holds 3:1 against its ground by
// its inner rim in light and by its own fill in dark, where it also glows.
void paintHabitMark(
  Canvas canvas,
  Offset centre,
  double radius,
  HabitMark mark,
  DialColors colors, {
  double fill = 1,
  bool pending = false,
  double rotation = 0,
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
  _paintFilled(canvas, centre, radius * fill, hue, ink, bead);
}

void _paintFilled(
  Canvas canvas,
  Offset centre,
  double radius,
  Color hue,
  Color ink,
  BeadTreatment bead,
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
  if (bead.rimWidth > 0 && radius > bead.rimWidth) {
    canvas.drawCircle(
      centre,
      radius - bead.rimWidth / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bead.rimWidth
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

// A pip: the habit's mark at a fixed size, for rows and keys.
class HabitPip extends StatelessWidget {
  const HabitPip({super.key, required this.mark, this.size = 10});

  final HabitMark mark;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _PipPainter(mark, DialColors.of(context))),
  );
}

class _PipPainter extends CustomPainter {
  _PipPainter(this.mark, this.colors);

  final HabitMark mark;
  final DialColors colors;

  @override
  void paint(Canvas canvas, Size size) => paintHabitMark(
    canvas,
    size.center(Offset.zero),
    size.shortestSide / 2,
    mark,
    colors,
  );

  @override
  bool shouldRepaint(_PipPainter old) =>
      old.mark != mark || old.colors != colors;
}
