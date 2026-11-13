import 'dart:math';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:tracker/data/dial_layout.dart';
import 'package:tracker/design/dial_theme.dart';

// The dial's disc, spokes and numerals, which Today's dial and the amount
// sheet's time dial share.
class DialFacePainter extends CustomPainter {
  DialFacePainter({
    required this.colors,
    required this.surface,
    required this.numeralStyle,
    required this.textScaler,
    required this.clear,
    required this.shadows,
    required this.ringAlpha,
    this.shadeFromMinute,
  });

  final int? shadeFromMinute;

  final List<BoxShadow> shadows;
  final double ringAlpha;
  final DialColors colors;
  final Color surface;
  final TextStyle numeralStyle;
  final TextScaler textScaler;
  // 0 with entries, 1 on a clear day; between while the ring draws on.
  final double clear;

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.shortestSide / DialFace.side;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);

    for (final BoxShadow shadow in shadows) {
      canvas.drawCircle(
        shadow.offset,
        DialFace.disc + shadow.spreadRadius,
        shadow.toPaint(),
      );
    }
    canvas.drawCircle(Offset.zero, DialFace.disc, Paint()..color = surface);
    canvas.drawCircle(
      Offset.zero,
      DialFace.disc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = colors.line,
    );

    if (shadeFromMinute case final int from) {
      final double start = dialAngle(from.toDouble());
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: DialFace.disc),
        start,
        dialAngle(minutesPerDay.toDouble()) - start,
        true,
        Paint()..color = colors.surface2.withValues(alpha: 0.9),
      );
    }

    if (clear > 0) {
      canvas.drawCircle(
        Offset.zero,
        DialFace.clearRing,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = DialFace.clearBand
          ..color = colors.clear.withValues(
            alpha: colors.clear.a * min(1, clear * 2),
          ),
      );
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: DialFace.clearRing),
        -pi / 2,
        2 * pi * clear,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = colors.clearInk.withValues(alpha: ringAlpha),
      );
    }

    for (int i = 0; i < 24; i++) {
      final bool major = i % 3 == 0;
      final double a = dialAngle(i * 60.0);
      final Paint paint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = major ? 1.4 : 1
        ..color = colors.spoke.withValues(
          alpha: colors.spoke.a * spokeOpacity(major: major, clear: clear),
        );
      canvas.drawLine(
        dialPoint(
          a,
          major ? DialFace.majorSpokeInner : DialFace.minorSpokeInner,
        ),
        dialPoint(
          a,
          major ? DialFace.majorSpokeOuter : DialFace.minorSpokeOuter,
        ),
        paint,
      );
    }

    for (final int hour in const <int>[0, 6, 12, 18]) {
      final TextPainter numeral = TextPainter(
        text: TextSpan(
          text: hour.toString().padLeft(2, '0'),
          style: numeralStyle.copyWith(color: colors.muted),
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      final Offset at = dialPoint(dialAngle(hour * 60.0), DialFace.numerals);
      numeral.paint(canvas, at - Offset(numeral.width / 2, numeral.height / 2));
      numeral.dispose();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(DialFacePainter old) =>
      old.clear != clear ||
      old.shadeFromMinute != shadeFromMinute ||
      old.ringAlpha != ringAlpha ||
      !listEquals(old.shadows, shadows) ||
      old.colors != colors ||
      old.surface != surface ||
      old.numeralStyle != numeralStyle ||
      old.textScaler != textScaler;
}
