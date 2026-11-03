import 'dart:math';

import 'package:flutter/material.dart';

// One palette for every candidate, so the comparison is between marks.
abstract final class IconPalette {
  static const Color inkLight = Color(0xFF2E2338);
  static const Color inkDark = Color(0xFF15111B);
  static const Color cream = Color(0xFFF5EBDD);
  static const Color coral = Color(0xFFF08A72);
  static const Color coralDeep = Color(0xFFD9604A);
}

enum Brand {
  penchant('Penchant', 'a habitual liking', 'A'),
  kenning('Kenning', 'Old English for knowing', 'B'),
  sounding('Sounding', 'a depth reading', 'B');

  const Brand(this.label, this.meaning, this._leadLetter);

  final String label;
  final String meaning;
  final String _leadLetter;

  /// The candidate the store listing shows.
  IconCandidate get lead => candidates.firstWhere(
    (IconCandidate candidate) => candidate.letter == _leadLetter,
  );

  List<IconCandidate> get candidates => IconCandidate.values
      .where((IconCandidate candidate) => candidate.brand == this)
      .toList();
}

enum IconCandidate {
  penchantLean(
    Brand.penchant,
    'A',
    'Lean',
    'One stroke leaning off the upright',
  ),
  penchantMonogram(
    Brand.penchant,
    'B',
    'Tilted p',
    'A geometric p, tipped forward',
  ),
  penchantDrift(
    Brand.penchant,
    'C',
    'Drift',
    'Strokes that lean further over time',
  ),
  kenningMonogram(
    Brand.kenning,
    'A',
    'k and a point',
    'A k whose arms meet at a point',
  ),
  kenningOverlap(
    Brand.kenning,
    'B',
    'Overlap',
    'Where two things meet, you learn',
  ),
  kenningRadar(Brand.kenning, 'C', 'Shape', 'The Today radar as a mark'),
  soundingPlumb(
    Brand.sounding,
    'A',
    'Plumb line',
    'A line dropped to find the depth',
  ),
  soundingSonar(
    Brand.sounding,
    'B',
    'Sonar',
    'Rings spreading down from a point',
  ),
  soundingProfile(
    Brand.sounding,
    'C',
    'Depth profile',
    'Soundings hung from a waterline',
  );

  const IconCandidate(this.brand, this.letter, this.title, this.description);

  final Brand brand;
  final String letter;
  final String title;
  final String description;

  String get id => '${brand.name}-${letter.toLowerCase()}';

  CustomPainter get painter => switch (this) {
    penchantLean => const _PenchantLean(),
    penchantMonogram => const _PenchantMonogram(),
    penchantDrift => const _PenchantDrift(),
    kenningMonogram => const _KenningMonogram(),
    kenningOverlap => const _KenningOverlap(),
    kenningRadar => const _KenningRadar(),
    soundingPlumb => const _SoundingPlumb(),
    soundingSonar => const _SoundingSonar(),
    soundingProfile => const _SoundingProfile(),
  };
}

/// The square, unmasked artwork: what App Store Connect takes at 1024 px.
class IconArt extends StatelessWidget {
  const IconArt(this.candidate, {super.key, required this.size});

  final IconCandidate candidate;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: candidate.painter),
    );
  }
}

/// The artwork under the iOS home-screen mask.
class MaskedIcon extends StatelessWidget {
  const MaskedIcon({super.key, required this.size, required this.child});

  MaskedIcon.candidate(
    IconCandidate candidate, {
    Key? key,
    required double size,
  }) : this(
         key: key,
         size: size,
         child: IconArt(candidate, size: size),
       );

  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: ClipRSuperellipse(
        borderRadius: BorderRadius.circular(size * 0.225),
        child: child,
      ),
    );
  }
}

// Each painter draws in a unit square: (0, 0) top left, (1, 1) bottom right.
abstract class _UnitPainter extends CustomPainter {
  const _UnitPainter();

  void paintUnit(Canvas canvas);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width, size.height);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 1, 1),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [IconPalette.inkLight, IconPalette.inkDark],
        ).createShader(const Rect.fromLTWH(0, 0, 1, 1)),
    );
    paintUnit(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Paint _stroke(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..isAntiAlias = true;

Paint _fill(Color color) => Paint()
  ..color = color
  ..isAntiAlias = true;

Shader _coralShader(Rect rect) => const LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [IconPalette.coral, IconPalette.coralDeep],
).createShader(rect);

void _rotateAbout(Canvas canvas, Offset pivot, double degrees) {
  canvas.translate(pivot.dx, pivot.dy);
  canvas.rotate(degrees * pi / 180);
  canvas.translate(-pivot.dx, -pivot.dy);
}

class _PenchantLean extends _UnitPainter {
  const _PenchantLean();

  @override
  void paintUnit(Canvas canvas) {
    const double radius = 0.075;
    const Offset pivot = Offset(0.44, 0.76 - radius);
    final RRect capsule = RRect.fromRectAndRadius(
      Rect.fromLTRB(pivot.dx - radius, 0.22, pivot.dx + radius, 0.76),
      const Radius.circular(radius),
    );

    canvas.drawLine(
      const Offset(0.26, 0.80),
      const Offset(0.74, 0.80),
      _stroke(IconPalette.cream.withValues(alpha: 0.35), 0.03),
    );
    canvas.drawRRect(
      capsule,
      _stroke(IconPalette.cream.withValues(alpha: 0.22), 0.014),
    );
    canvas.save();
    _rotateAbout(canvas, pivot, 20);
    canvas.drawRRect(
      capsule,
      Paint()..shader = _coralShader(capsule.outerRect),
    );
    canvas.restore();
  }
}

class _PenchantMonogram extends _UnitPainter {
  const _PenchantMonogram();

  @override
  void paintUnit(Canvas canvas) {
    const double weight = 0.1;
    const Offset bowl = Offset(0.55, 0.43);
    const double radius = 0.15;

    canvas.save();
    _rotateAbout(canvas, const Offset(0.5, 0.5), 14);
    canvas.drawLine(
      const Offset(0.40, 0.28),
      const Offset(0.40, 0.80),
      _stroke(IconPalette.cream, weight),
    );
    canvas.drawCircle(
      bowl,
      radius,
      _stroke(IconPalette.coral, weight)..strokeCap = StrokeCap.butt,
    );
    canvas.restore();
  }
}

class _PenchantDrift extends _UnitPainter {
  const _PenchantDrift();

  @override
  void paintUnit(Canvas canvas) {
    const List<double> stops = [0.25, 0.4167, 0.5833, 0.75];

    for (int row = 0; row < stops.length; row++) {
      for (int column = 0; column < stops.length; column++) {
        final int step = row + column;
        final bool last = step == 2 * (stops.length - 1);
        final Offset centre = Offset(stops[column], stops[row]);

        canvas.save();
        _rotateAbout(canvas, centre, step * 5.0);
        canvas.drawLine(
          centre.translate(0, -0.055),
          centre.translate(0, 0.055),
          _stroke(
            last
                ? IconPalette.coral
                : IconPalette.cream.withValues(alpha: 0.3 + step * 0.1),
            0.05,
          ),
        );
        canvas.restore();
      }
    }
  }
}

class _KenningMonogram extends _UnitPainter {
  const _KenningMonogram();

  @override
  void paintUnit(Canvas canvas) {
    const double weight = 0.09;
    const Offset joint = Offset(0.48, 0.55);
    final Paint cream = _stroke(IconPalette.cream, weight);

    canvas.drawLine(const Offset(0.34, 0.22), const Offset(0.34, 0.78), cream);
    canvas.drawLine(const Offset(0.68, 0.34), joint, cream);
    canvas.drawLine(joint, const Offset(0.68, 0.78), cream);
    canvas.drawCircle(joint, 0.085, _fill(IconPalette.inkLight));
    canvas.drawCircle(joint, 0.065, _fill(IconPalette.coral));
  }
}

class _KenningOverlap extends _UnitPainter {
  const _KenningOverlap();

  @override
  void paintUnit(Canvas canvas) {
    const double radius = 0.21;
    const Offset left = Offset(0.39, 0.5);
    const Offset right = Offset(0.61, 0.5);
    final Path lens = Path.combine(
      PathOperation.intersect,
      Path()..addOval(Rect.fromCircle(center: left, radius: radius)),
      Path()..addOval(Rect.fromCircle(center: right, radius: radius)),
    );

    canvas.drawPath(lens, Paint()..shader = _coralShader(lens.getBounds()));
    canvas.drawCircle(left, radius, _stroke(IconPalette.cream, 0.04));
    canvas.drawCircle(right, radius, _stroke(IconPalette.cream, 0.04));
  }
}

class _KenningRadar extends _UnitPainter {
  const _KenningRadar();

  static const Offset _centre = Offset(0.5, 0.52);
  static const double _outer = 0.32;

  Offset _vertex(int index, double radius) {
    final double angle = -pi / 2 + index * pi / 3;
    return _centre + Offset(cos(angle), sin(angle)) * radius;
  }

  Path _polygon(List<double> radii) {
    final Path path = Path()
      ..moveTo(_vertex(0, radii[0]).dx, _vertex(0, radii[0]).dy);
    for (int i = 1; i < radii.length; i++) {
      path.lineTo(_vertex(i, radii[i]).dx, _vertex(i, radii[i]).dy);
    }
    return path..close();
  }

  @override
  void paintUnit(Canvas canvas) {
    final Paint grid = _stroke(IconPalette.cream.withValues(alpha: 0.3), 0.012)
      ..strokeJoin = StrokeJoin.round;

    for (final double ring in const [1 / 3, 2 / 3, 1]) {
      canvas.drawPath(_polygon(List.filled(6, _outer * ring)), grid);
    }
    for (int i = 0; i < 6; i++) {
      canvas.drawLine(_centre, _vertex(i, _outer), grid);
    }

    const List<double> values = [0.9, 0.45, 0.75, 0.35, 0.95, 0.55];
    final List<double> radii = [for (final double v in values) v * _outer];
    final Path shape = _polygon(radii);

    canvas.drawPath(shape, _fill(IconPalette.coral.withValues(alpha: 0.35)));
    canvas.drawPath(
      shape,
      _stroke(IconPalette.coral, 0.028)..strokeJoin = StrokeJoin.round,
    );
    for (int i = 0; i < 6; i++) {
      canvas.drawCircle(_vertex(i, radii[i]), 0.025, _fill(IconPalette.cream));
    }
  }
}

class _SoundingPlumb extends _UnitPainter {
  const _SoundingPlumb();

  @override
  void paintUnit(Canvas canvas) {
    final Paint faint = _stroke(
      IconPalette.cream.withValues(alpha: 0.35),
      0.025,
    );

    canvas.drawLine(
      const Offset(0.22, 0.25),
      const Offset(0.78, 0.25),
      _stroke(IconPalette.cream, 0.035),
    );
    for (final double depth in const [0.37, 0.48, 0.59]) {
      canvas.drawLine(Offset(0.30, depth), Offset(0.38, depth), faint);
    }
    canvas.drawLine(
      const Offset(0.5, 0.25),
      const Offset(0.5, 0.60),
      _stroke(IconPalette.cream, 0.02),
    );

    const Offset bob = Offset(0.5, 0.66);
    const double radius = 0.075;
    final double side = radius * sin(pi / 3);
    final Path drop = Path.combine(
      PathOperation.union,
      Path()
        ..moveTo(bob.dx - side, bob.dy + radius / 2)
        ..lineTo(bob.dx, 0.82)
        ..lineTo(bob.dx + side, bob.dy + radius / 2)
        ..close(),
      Path()..addOval(Rect.fromCircle(center: bob, radius: radius)),
    );

    canvas.drawPath(drop, Paint()..shader = _coralShader(drop.getBounds()));
  }
}

class _SoundingSonar extends _UnitPainter {
  const _SoundingSonar();

  @override
  void paintUnit(Canvas canvas) {
    const Offset source = Offset(0.5, 0.24);
    const List<double> radii = [0.15, 0.28, 0.41, 0.54];
    const List<double> alphas = [0.95, 0.65, 0.4, 0.2];

    for (int i = 0; i < radii.length; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: source, radius: radii[i]),
        25 * pi / 180,
        130 * pi / 180,
        false,
        _stroke(IconPalette.cream.withValues(alpha: alphas[i]), 0.04),
      );
    }
    canvas.drawCircle(source, 0.055, _fill(IconPalette.coral));
  }
}

class _SoundingProfile extends _UnitPainter {
  const _SoundingProfile();

  @override
  void paintUnit(Canvas canvas) {
    const List<double> depths = [0.20, 0.30, 0.42, 0.34, 0.50, 0.38, 0.26];
    const double top = 0.31;
    const double pitch = 0.085;
    final double first = 0.5 - pitch * (depths.length - 1) / 2;
    final double deepest = depths.reduce(max);

    canvas.drawLine(
      const Offset(0.2, 0.25),
      const Offset(0.8, 0.25),
      _stroke(IconPalette.cream.withValues(alpha: 0.5), 0.025),
    );
    for (int i = 0; i < depths.length; i++) {
      final double x = first + i * pitch;
      canvas.drawLine(
        Offset(x, top),
        Offset(x, top + depths[i]),
        _stroke(
          depths[i] == deepest ? IconPalette.coral : IconPalette.cream,
          0.05,
        ),
      );
    }
  }
}
