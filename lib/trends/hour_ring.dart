import 'dart:math';

import 'package:flutter/material.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';

// A small 24-hour face, midnight at the top like the dial, with a wedge per
// hour that grows with what was logged in it.
class HourRing extends StatelessWidget {
  const HourRing({
    super.key,
    required this.hours,
    required this.mark,
    this.size = 96,
  });

  final List<double> hours;
  final HabitMark mark;
  final double size;

  @override
  Widget build(BuildContext context) {
    final DialColors colors = DialColors.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _HourRingPainter(
            hours: hours,
            mark: mark,
            colors: colors,
            surface: scheme.surfaceContainerLow,
            label: DialTypeScale.dialNumeral.copyWith(
              color: colors.muted,
              fontSize: 9,
            ),
          ),
        ),
      ),
    );
  }
}

class _HourRingPainter extends CustomPainter {
  _HourRingPainter({
    required this.hours,
    required this.mark,
    required this.colors,
    required this.surface,
    required this.label,
  });

  final List<double> hours;
  final HabitMark mark;
  final DialColors colors;
  final Color surface;
  final TextStyle label;

  // On a face 100 across, as the mock-up draws it.
  static const double _face = 47;
  static const double _inner = 26;
  static const double _reach = 20;

  static double _angle(double minutes) => minutes / 1440 * 2 * pi - pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final double k = size.shortestSide / 100;
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(k);

    canvas.drawCircle(Offset.zero, _face, Paint()..color = surface);
    canvas.drawCircle(
      Offset.zero,
      _inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 / k
        ..color = colors.line,
    );
    final Paint tick = Paint()
      ..color = colors.spoke
      ..strokeWidth = 1 / k;
    for (final int h in const <int>[0, 6, 12, 18]) {
      final double a = _angle(h * 60);
      canvas.drawLine(
        Offset(cos(a), sin(a)) * 18,
        Offset(cos(a), sin(a)) * 48,
        tick,
      );
    }

    final double most = hours.fold<double>(1, max);
    final Paint fill = Paint()..color = colors.habit(mark);
    final BeadTreatment bead = colors.bead;
    final Paint rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * bead.rimWidth / k
      ..color = colors.habitInk(mark).withValues(alpha: bead.rimAlpha);
    for (int h = 0; h < 24; h++) {
      if (hours[h] <= 0) {
        continue;
      }
      final double a0 = _angle(h * 60 + 6);
      final double a1 = _angle(h * 60 + 54);
      final double outer = _inner + _reach * hours[h] / most;
      final Path wedge = Path()
        ..arcTo(
          Rect.fromCircle(center: Offset.zero, radius: outer),
          a0,
          a1 - a0,
          true,
        )
        ..arcTo(
          Rect.fromCircle(center: Offset.zero, radius: _inner),
          a1,
          a0 - a1,
          false,
        )
        ..close();
      canvas.drawPath(wedge, fill);
      if (bead.rimWidth > 0) {
        // The rim sits inside the wedge, like a filled bead's.
        canvas
          ..save()
          ..clipPath(wedge)
          ..drawPath(wedge, rim)
          ..restore();
      }
    }

    final TextPainter text = TextPainter(
      text: TextSpan(text: '24 h', style: label.copyWith(fontSize: 9)),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, Offset(-text.width / 2, -text.height / 2));
    text.dispose();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HourRingPainter old) =>
      old.hours != hours ||
      old.mark != mark ||
      old.colors != colors ||
      old.surface != surface;
}
