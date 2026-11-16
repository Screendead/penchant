import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:tracker/claude/claude_working.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/design/dial_theme.dart';

/// The theme's colours the looks draw with: ink on paper, and the habit
/// colours for entries only.
@immutable
class WorkingColors {
  const WorkingColors({
    required this.ink,
    required this.muted,
    required this.line,
    required this.paper,
    required this.data,
  });

  factory WorkingColors.of(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors dial = DialColors.of(context);
    return WorkingColors(
      ink: scheme.onSurface,
      muted: dial.muted,
      line: dial.line,
      paper: scheme.surface,
      data: dial.data,
    );
  }

  final Color ink;
  final Color muted;
  final Color line;
  final Color paper;
  final List<Color> data;

  @override
  bool operator ==(Object other) =>
      other is WorkingColors &&
      other.ink == ink &&
      other.muted == muted &&
      other.line == line &&
      other.paper == paper;

  @override
  int get hashCode => Object.hash(ink, muted, line, paper);
}

/// What a look draws from: the clock in seconds, how far it has drawn
/// together into the result's [plate], and the journal's marks.
class WorkingScene {
  WorkingScene({
    required this.clock,
    required this.resolve,
    required this.marks,
    required this.colors,
    required this.label,
    required this.today,
    required this.plate,
  });

  final ValueNotifier<double> clock;
  final Animation<double> resolve;
  final List<JournalMark> marks;
  final WorkingColors colors;
  final TextStyle label;
  final DateTime today;
  final Size plate;

  late final Listenable repaint = Listenable.merge(<Listenable>[
    clock,
    resolve,
  ]);
}

CustomPainter workingPainter(ClaudeWorkingLook look, WorkingScene scene) =>
    switch (look) {
      ClaudeWorkingLook.dial => DialReadPainter(scene),
      ClaudeWorkingLook.ink => InkTracePainter(scene),
      ClaudeWorkingLook.lens => LensPainter(scene),
    };

// Clockwise from the top, as the Day Dial: midnight up.
double _minuteAngle(num minute) => minute / 1440 * 2 * math.pi;

Offset _polar(double angle, double radius) =>
    Offset(math.sin(angle) * radius, -math.cos(angle) * radius);

double _hash(int n) {
  final double x = math.sin(n * 12.9898 + 78.233) * 43758.5453;
  return x - x.floorToDouble();
}

Color _alpha(Color c, double a) =>
    c.withValues(alpha: (c.a * a).clamp(0.0, 1.0));

final Paint _stroke = Paint()
  ..style = PaintingStyle.stroke
  ..isAntiAlias = true;
final Paint _fill = Paint()..isAntiAlias = true;

RRect _plateRect(Offset c, Size plate) => RRect.fromRectAndRadius(
  Rect.fromCenter(center: c, width: plate.width, height: plate.height),
  const Radius.circular(18),
);

/// The dial reads: the last four weeks as rings of one 24-hour face, today
/// outermost; a hand sweeps it with a hatched wake, and each entry swells and
/// rings in its habit's colour as the hand passes, then settles dimmer.
class DialReadPainter extends CustomPainter {
  DialReadPainter(this.scene) : super(repaint: scene.repaint);

  final WorkingScene scene;
  final Map<int, TextPainter> _numerals = <int, TextPainter>{};

  static const double period = 6;

  TextPainter _numeral(int h) => _numerals[h] ??= TextPainter(
    text: TextSpan(
      text: h.toString().padLeft(2, '0'),
      style: scene.label.copyWith(color: scene.colors.muted),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final double s = scene.clock.value;
    final double r = Curves.easeInCubic.transform(scene.resolve.value);
    final double fade = 1 - r;
    final WorkingColors k = scene.colors;
    final Offset c = size.center(Offset.zero);
    final double big = size.shortestSide / 2 * 0.92;
    final bool small = big < 60;
    final double radius = big * (1 - 0.35 * r);
    final double hub = radius * 0.3;
    double track(int daysAgo) =>
        radius *
        (0.36 + 0.56 * (1 - daysAgo / (claudeWorkingDays - 1))) *
        (1 - r);

    _stroke
      ..strokeCap = StrokeCap.butt
      ..strokeWidth = 1;
    canvas.drawCircle(c, radius, _stroke..color = _alpha(k.line, fade));
    for (int h = 0; h < 24; h++) {
      final double a = _minuteAngle(h * 60);
      final bool major = h % 6 == 0;
      final double len = (major ? 10 : 5) * (small ? 0.45 : 1);
      canvas.drawLine(
        c + _polar(a, radius - len),
        c + _polar(a, radius),
        _stroke
          ..strokeWidth = major ? 1.4 : 1
          ..color = _alpha(major ? k.ink : k.muted, fade * (major ? 0.8 : 0.5)),
      );
      if (major && !small && r == 0) {
        final TextPainter tp = _numeral(h);
        tp.paint(
          canvas,
          c + _polar(a, radius - 24) - Offset(tp.width / 2, tp.height / 2),
        );
      }
    }
    for (int w = 1; w < 4; w++) {
      canvas.drawCircle(
        c,
        track(w * 7) - (track(w * 7 - 1) - track(w * 7)) / 2,
        _stroke
          ..strokeWidth = 0.6
          ..color = _alpha(k.line, fade * 0.7),
      );
    }

    final double hand = s / period * 2 * math.pi;
    _stroke.strokeWidth = 1;
    for (int i = 1; i < 26; i++) {
      final double a = hand - i * 0.02;
      canvas.drawLine(
        c + _polar(a, hub),
        c + _polar(a, radius),
        _stroke..color = _alpha(k.ink, fade * 0.16 * (1 - i / 26)),
      );
    }

    for (final JournalMark m in scene.marks) {
      final double a = _minuteAngle(m.minute);
      final double since = (hand - a) % (2 * math.pi);
      final double lit = math.exp(-since * 1.4);
      final double bead = (small ? 1.1 : 2.2) + m.weight * (small ? 0.5 : 1.5);
      final Offset at = c + _polar(a, track(m.daysAgo));
      final Color col = k.data[m.slot % k.data.length];
      canvas.drawCircle(
        at,
        bead * (1 + 0.6 * math.exp(-since * 9)),
        _fill..color = _alpha(col, fade * (0.3 + 0.7 * lit)),
      );
      if (since < 1.2 && !small) {
        final double t = since / 1.2;
        canvas.drawCircle(
          at,
          bead + 3 + t * 14,
          _stroke
            ..strokeWidth = 1
            ..color = _alpha(col, fade * (1 - t) * 0.85),
        );
      }
    }

    canvas.drawCircle(
      c,
      hub,
      _stroke
        ..strokeWidth = 1
        ..color = _alpha(k.line, fade),
    );
    canvas.drawLine(
      c + _polar(hand, hub),
      c + _polar(hand, radius + (small ? 2 : 6)),
      _stroke
        ..strokeWidth = small ? 1.2 : 1.8
        ..strokeCap = StrokeCap.round
        ..color = _alpha(k.ink, fade),
    );
    canvas.drawCircle(
      c + _polar(hand, radius + (small ? 2 : 6)),
      small ? 1.6 : 3,
      _fill..color = _alpha(k.ink, fade),
    );
    if (r > 0 && !scene.plate.isEmpty) {
      _tracePlate(canvas, c, scene.plate, r, k.ink);
    }
  }

  @override
  bool shouldRepaint(DialReadPainter old) =>
      old.scene.marks != scene.marks || old.scene.colors != scene.colors;
}

// The result's outline drawn in as everything else draws together.
void _tracePlate(Canvas canvas, Offset c, Size plate, double r, Color ink) {
  final Path outline = Path()..addRRect(_plateRect(c, plate));
  for (final ui.PathMetric metric in outline.computeMetrics()) {
    canvas.drawPath(
      metric.extractPath(0, metric.length * r),
      _stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round
        ..color = _alpha(ink, 0.8),
    );
  }
}

/// Ink: fine lines trace out from the person's words at the centre across a
/// field of their entries, which light as a line's head passes; each line
/// grows, then withdraws from its root, and is drawn again elsewhere. At the
/// end the lines withdraw and the answer's outline is drawn in.
class InkTracePainter extends CustomPainter {
  InkTracePainter(this.scene) : super(repaint: scene.repaint);

  final WorkingScene scene;
  static const int lines = 56;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = scene.clock.value;
    final double r = Curves.easeInCubic.transform(scene.resolve.value);
    final double fade = 1 - r;
    final WorkingColors k = scene.colors;
    final Offset c = size.center(Offset.zero);
    final bool small = size.shortestSide < 120;
    final double ax = small ? 6 : math.min(size.width * 0.33, 150);
    final double ay = small ? 6 : 52;
    final double reach = size.shortestSide / 2;
    final double speed = reach * 0.2;
    final double step = small ? 1.5 : 3;

    final List<Offset> heads = <Offset>[];
    final Path path = Path();
    _stroke
      ..strokeWidth = small ? 0.7 : 0.9
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < lines; i++) {
      final double life = 6.5 + 2 * _hash(i);
      final double t = s + _hash(i + 101) * life;
      final int cycle = (t / life).floor();
      final double age = t - cycle * life;
      final double grow = life * 0.55;
      final double head = math.min(age, grow) * speed;
      final double tail = math.max(0, age - grow) * speed * 1.35;
      if (tail >= head) continue;
      final double theta = 2 * math.pi * _hash(i * 7 + cycle * 13);
      final double phase = 6 * _hash(i * 3 + cycle);
      Offset p = c + Offset(math.cos(theta) * ax, math.sin(theta) * ay);
      final double out = math.atan2(ax * math.sin(theta), ay * math.cos(theta));
      path.reset();
      bool started = false;
      for (double d = 0; d < head; d += step) {
        final double dir =
            out +
            0.75 * math.sin(p.dx * 0.011 + phase) +
            0.55 * math.cos(p.dy * 0.014 - phase * 1.3);
        p += Offset(math.cos(dir), math.sin(dir)) * step;
        if (d < tail) continue;
        if (!started) {
          path.moveTo(p.dx, p.dy);
          started = true;
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      final double alive = 1 - age / life;
      canvas.drawPath(
        path,
        _stroke..color = _alpha(k.ink, fade * 0.55 * (0.4 + 0.6 * alive)),
      );
      if (age < grow) {
        heads.add(p);
        canvas.drawCircle(
          p,
          small ? 0.9 : 1.5,
          _fill..color = _alpha(k.ink, fade * 0.85),
        );
      }
    }

    final double rx = size.width / 2 * 0.94;
    final double ry = size.height / 2 * 0.94;
    for (final JournalMark m in scene.marks) {
      final double a = _minuteAngle(m.minute);
      final double f = 0.5 + 0.5 * (1 - m.daysAgo / (claudeWorkingDays - 1));
      final Offset at = c + Offset(math.sin(a) * rx * f, -math.cos(a) * ry * f);
      double near = double.infinity;
      for (final Offset h in heads) {
        near = math.min(near, (h - at).distanceSquared);
      }
      final double lit = (1 - math.sqrt(near) / (small ? 8 : 26)).clamp(
        0.0,
        1.0,
      );
      final double bead = (small ? 0.9 : 1.8) + m.weight * (small ? 0.4 : 1.2);
      final Color col = k.data[m.slot % k.data.length];
      canvas.drawCircle(
        at,
        bead * (1 + 0.5 * lit),
        _fill..color = _alpha(col, fade * (0.32 + 0.68 * lit)),
      );
      if (lit > 0 && !small) {
        canvas.drawCircle(
          at,
          bead + 2 + 7 * lit,
          _stroke
            ..strokeWidth = 0.8
            ..color = _alpha(col, fade * lit * 0.7),
        );
      }
    }
    if (r > 0 && !scene.plate.isEmpty) {
      _tracePlate(canvas, c, scene.plate, r, k.ink);
    }
  }

  @override
  bool shouldRepaint(InkTracePainter old) =>
      old.scene.marks != scene.marks || old.scene.colors != scene.colors;
}

/// The lens: the last four weeks as a field of hours, today at the top, the
/// entries in their habits' colours, all held back; a loupe glides over it,
/// drawing the cells beneath into focus at more than twice the size with the
/// day and hour it is over, and leaves the cells it has passed darkened for
/// a while.
class LensPainter extends CustomPainter {
  LensPainter(this.scene) : super(repaint: scene.repaint);

  final WorkingScene scene;
  final Float32List _seen = Float32List(claudeWorkingDays * 24);
  final Map<String, TextPainter> _labels = <String, TextPainter>{};

  static const List<String> _weekdays = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  TextPainter _label(String text) {
    if (_labels.length > 64) _labels.clear();
    return _labels[text] ??= TextPainter(
      text: TextSpan(
        text: text,
        style: scene.label.copyWith(color: scene.colors.ink),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double s = scene.clock.value;
    final double r = Curves.easeInOutCubic.transform(scene.resolve.value);
    final double fade = 1 - r;
    final WorkingColors k = scene.colors;
    final Offset c = size.center(Offset.zero);
    final bool small = size.shortestSide < 120;
    final double pad = small ? 4 : 6;
    const int cols = 24;
    const int rows = claudeWorkingDays;
    final double cw = (size.width - 2 * pad) / cols;
    final double ch = math.min(cw * 1.25, (size.height - 2 * pad) / rows);
    final double top = c.dy - ch * rows / 2;
    Offset cell(int day, double hour) =>
        Offset(pad + (hour + 0.5) * cw, top + (day + 0.5) * ch);

    final double lensR0 = small
        ? size.shortestSide * 0.3
        : math.min(size.width * 0.21, 84);
    Offset lensAt(double t) => Offset(
      c.dx + (size.width / 2 - pad - lensR0 * 0.7) * math.sin(t * 0.29 + 0.7),
      c.dy + (ch * rows / 2 - lensR0 * 0.55) * math.sin(t * 0.43),
    );
    final Offset lens = Offset.lerp(lensAt(s), c, r)!;
    final double lensR = lensR0 + r * size.longestSide;

    _seen.fillRange(0, _seen.length, 0);
    for (int i = 1; i <= 36; i++) {
      final Offset p = lensAt(s - i * 0.12);
      final double recency = 1 - i / 36;
      final int c0 = ((p.dx - lensR0 - pad) / cw).floor().clamp(0, cols - 1);
      final int c1 = ((p.dx + lensR0 - pad) / cw).ceil().clamp(0, cols - 1);
      final int r0 = ((p.dy - lensR0 - top) / ch).floor().clamp(0, rows - 1);
      final int r1 = ((p.dy + lensR0 - top) / ch).ceil().clamp(0, rows - 1);
      for (int d = r0; d <= r1; d++) {
        for (int h = c0; h <= c1; h++) {
          if ((cell(d, h.toDouble()) - p).distance < lensR0 * 0.9) {
            final int at = d * cols + h;
            if (recency > _seen[at]) _seen[at] = recency;
          }
        }
      }
    }

    for (int d = 0; d < rows; d++) {
      for (int h = 0; h < cols; h++) {
        final double seen = _seen[d * cols + h];
        canvas.drawCircle(
          cell(d, h.toDouble()),
          (small ? 0.5 : 0.9) + seen * (small ? 0.3 : 0.7),
          _fill
            ..color = seen > 0
                ? _alpha(k.ink, fade * (0.2 + 0.45 * seen))
                : _alpha(k.line, fade),
        );
      }
    }
    for (final JournalMark m in scene.marks) {
      canvas.drawCircle(
        cell(m.daysAgo, m.minute / 60 - 0.5),
        (small ? 0.8 : 1.3) + m.weight * (small ? 0.3 : 0.6),
        _fill..color = _alpha(k.data[m.slot % k.data.length], fade * 0.45),
      );
    }

    const double zoom = 2.4;
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: lens, radius: lensR)),
    );
    canvas.drawCircle(lens, lensR, _fill..color = k.paper);
    canvas.translate(lens.dx, lens.dy);
    canvas.scale(zoom);
    canvas.translate(-lens.dx, -lens.dy);
    for (int h = 0; h <= cols; h += 1) {
      final double x = pad + h * cw;
      canvas.drawLine(
        Offset(x, top),
        Offset(x, top + ch * rows),
        _stroke
          ..strokeWidth = (h % 6 == 0 ? 0.5 : 0.25)
          ..color = _alpha(k.line, fade),
      );
    }
    for (int d = 0; d < rows; d++) {
      for (int h = 0; h < cols; h++) {
        canvas.drawCircle(
          cell(d, h.toDouble()),
          0.7,
          _stroke
            ..strokeWidth = 0.3
            ..color = _alpha(k.muted, fade * 0.8),
        );
      }
    }
    for (final JournalMark m in scene.marks) {
      final Offset at = cell(m.daysAgo, m.minute / 60 - 0.5);
      final double bead = 1.1 + m.weight * 0.7;
      final Color col = k.data[m.slot % k.data.length];
      canvas.drawCircle(at, bead, _fill..color = _alpha(col, fade));
      canvas.drawCircle(
        at,
        bead + 0.9,
        _stroke
          ..strokeWidth = 0.35
          ..color = _alpha(col, fade * 0.7),
      );
    }
    canvas.restore();

    _stroke
      ..strokeWidth = small ? 1 : 1.5
      ..strokeCap = StrokeCap.round
      ..color = _alpha(k.ink, fade);
    canvas.drawCircle(lens, lensR, _stroke);
    if (!small) {
      canvas.drawCircle(
        lens,
        lensR + 5,
        _stroke
          ..strokeWidth = 0.6
          ..color = _alpha(k.line, fade),
      );
      for (int q = 0; q < 4; q++) {
        final double a = q * math.pi / 2 + s * 0.05;
        canvas.drawLine(
          lens + _polar(a, lensR + 1),
          lens + _polar(a, lensR + 9),
          _stroke
            ..strokeWidth = 1.2
            ..color = _alpha(k.ink, fade),
        );
      }
      if (r == 0) {
        final int day = ((lens.dy - top) / ch).floor().clamp(0, rows - 1);
        final int hour = ((lens.dx - pad) / cw).floor().clamp(0, cols - 1);
        final DateTime date = addDays(startOfDay(scene.today), -day);
        final TextPainter tp = _label(
          '${_weekdays[date.weekday - 1]} ${date.day} · '
          '${hour.toString().padLeft(2, '0')}:00',
        );
        final Offset at = lens + Offset(-tp.width / 2, lensR + 12);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(at.dx - 6, at.dy - 2, tp.width + 12, tp.height + 4),
            const Radius.circular(999),
          ),
          _fill..color = k.paper,
        );
        tp.paint(canvas, at);
      }
    }
    if (r > 0 && !scene.plate.isEmpty) {
      _tracePlate(canvas, c, scene.plate, r, k.ink);
    }
  }

  @override
  bool shouldRepaint(LensPainter old) =>
      old.scene.marks != scene.marks || old.scene.colors != scene.colors;
}
