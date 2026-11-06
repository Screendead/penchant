import 'dart:math';

import 'package:flutter/widgets.dart';

// The design system's line icons: 24-unit SVG paths drawn with a 2-unit
// round-capped stroke in the ambient icon colour, as the mock-up draws them.
enum DialGlyph {
  left(<String>['M15 18l-6-6 6-6']),
  right(<String>['M9 18l6-6-6-6']),
  down(<String>['M6 9l6 6 6-6']),
  plus(<String>['M12 5v14M5 12h14']),
  close(<String>['M6 6l12 12M18 6L6 18']),
  mail(<String>[
    'M6 5h12a3 3 0 013 3v8a3 3 0 01-3 3H6a3 3 0 01-3-3V8a3 3 0 013-3z',
    'M4 7l8 6 8-6',
  ]),
  lock(<String>[
    'M7.5 10.5h9a3 3 0 013 3v4a3 3 0 01-3 3h-9a3 3 0 01-3-3v-4a3 3 0 013-3z',
    'M8 10.5V7a4 4 0 018 0v3.5',
  ]),
  eye(<String>[
    'M2 12C2 12 5.6 5 12 5C18.4 5 22 12 22 12C22 12 18.4 19 12 19C5.6 19 2 12 '
        '2 12z',
    'M12 9a3 3 0 110 6 3 3 0 010-6z',
  ]),
  eyeOff(<String>[
    'M2 12C2 12 5.6 5 12 5C18.4 5 22 12 22 12C22 12 18.4 19 12 19C5.6 19 2 12 '
        '2 12z',
    'M12 9a3 3 0 110 6 3 3 0 010-6z',
    'M4 4l16 16',
  ]),
  check(<String>['M5 12.5l4.5 4.5L19 7.5']),
  alert(<String>['M12 3a9 9 0 110 18 9 9 0 010-18z', 'M12 7.5v5M12 16.2v.3']),
  shield(<String>[
    'M12 3l8 3v6C20 16.5 16.6 20.2 12 21C7.4 20.2 4 16.5 4 12V6z',
  ]),
  share(<String>[
    'M12 3v12M7.5 7.5L12 3l4.5 4.5',
    'M5 12v7a2 2 0 002 2h10a2 2 0 002-2v-7',
  ]),
  cloudOk(<String>[
    'M7 18a4.5 4.5 0 01-.6-8.96A6 6 0 0118 9.5a4 4 0 01-1 8.5z',
    'M9.5 13.5l2 2 3.5-3.5',
  ]),
  cloudOff(<String>[
    'M3 3l18 18',
    'M9.3 5.4A6 6 0 0118 9.5a4 4 0 012.3 7.2M17 18H7a4.5 4.5 0 01-1.7-8.66',
  ]),
  cloudUp(<String>[
    'M7 18a4.5 4.5 0 01-.6-8.96A6 6 0 0118 9.5a4 4 0 01-1 8.5',
    'M12 12v7M9.5 14.5L12 12l2.5 2.5',
  ]),
  habits(<String>[
    'M12 4a8 8 0 110 16 8 8 0 010-16z',
    'M12 4v4M20 12h-4M12 20v-4M4 12h4',
  ]),
  gear(<String>[
    'M12 9a3 3 0 110 6 3 3 0 010-6z',
    'M19.4 15a1.7 1.7 0 00.3 1.8l.1.1a2 2 0 11-2.8 2.8l-.1-.1a1.7 1.7 0 00-1.8-.3 '
        '1.7 1.7 0 00-1 1.5V21a2 2 0 11-4 0v-.1a1.7 1.7 0 00-1.1-1.5 1.7 1.7 0 '
        '00-1.8.3l-.1.1a2 2 0 11-2.8-2.8l.1-.1a1.7 1.7 0 00.3-1.8 1.7 1.7 0 '
        '00-1.5-1H3a2 2 0 110-4h.1a1.7 1.7 0 001.5-1.1 1.7 1.7 0 00-.3-1.8l-.1-.1a2 '
        '2 0 112.8-2.8l.1.1a1.7 1.7 0 001.8.3H9a1.7 1.7 0 001-1.5V3a2 2 0 114 '
        '0v.1a1.7 1.7 0 001 1.5 1.7 1.7 0 001.8-.3l.1-.1a2 2 0 112.8 2.8l-.1.1a1.7 '
        '1.7 0 00-.3 1.8V9a1.7 1.7 0 001.5 1H21a2 2 0 110 4h-.1a1.7 1.7 0 00-1.5 1z',
  ]);

  const DialGlyph(this.paths);

  final List<String> paths;
}

class StrokeIcon extends StatelessWidget {
  const StrokeIcon(this.glyph, {super.key, this.size, this.color});

  final DialGlyph glyph;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final IconThemeData theme = IconTheme.of(context);
    final double side = size ?? theme.size ?? 24;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: side,
        child: CustomPaint(
          painter: _StrokePainter(
            glyph,
            color ?? theme.color ?? const Color(0xFF000000),
          ),
        ),
      ),
    );
  }
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.glyph, this.color);

  final DialGlyph glyph;
  final Color color;

  static final Map<DialGlyph, Path> _cache = <DialGlyph, Path>{};

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = _cache[glyph] ??= _combine(glyph.paths);
    canvas
      ..save()
      ..scale(size.width / 24, size.height / 24)
      ..drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_StrokePainter old) =>
      old.glyph != glyph || old.color != color;
}

Path _combine(List<String> paths) {
  final Path out = Path();
  for (final String d in paths) {
    out.addPath(parseSvgPath(d), Offset.zero);
  }
  return out;
}

// The subset of SVG path data the glyphs use: M L H V A C Z, absolute and
// relative.
Path parseSvgPath(String d) {
  final List<String> tokens = RegExp(
    r'[MmLlHhVvAaCcZz]|-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?',
  ).allMatches(d).map((Match m) => m[0]!).toList();
  final Path path = Path();
  double x = 0;
  double y = 0;
  double startX = 0;
  double startY = 0;
  String command = 'M';
  int i = 0;

  bool isCommand(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  double next() => double.parse(tokens[i++]);
  // Arc flags may run into what follows with no separator: "0118" is the
  // flags 0 and 1 then 18, "00.3" the flags 0 and 0 then .3.
  int flag() {
    final String t = tokens[i];
    if (t.length > 1) {
      tokens[i] = t.substring(1);
      return int.parse(t[0]);
    }
    i++;
    return int.parse(t);
  }

  while (i < tokens.length) {
    if (isCommand(tokens[i])) {
      command = tokens[i++];
    }
    final bool rel = command == command.toLowerCase();
    switch (command.toUpperCase()) {
      case 'M':
        final double nx = next() + (rel ? x : 0);
        final double ny = next() + (rel ? y : 0);
        path.moveTo(nx, ny);
        x = startX = nx;
        y = startY = ny;
        command = rel ? 'l' : 'L';
      case 'L':
        x = next() + (rel ? x : 0);
        y = next() + (rel ? y : 0);
        path.lineTo(x, y);
      case 'H':
        x = next() + (rel ? x : 0);
        path.lineTo(x, y);
      case 'V':
        y = next() + (rel ? y : 0);
        path.lineTo(x, y);
      case 'C':
        final double x1 = next() + (rel ? x : 0);
        final double y1 = next() + (rel ? y : 0);
        final double x2 = next() + (rel ? x : 0);
        final double y2 = next() + (rel ? y : 0);
        x = next() + (rel ? x : 0);
        y = next() + (rel ? y : 0);
        path.cubicTo(x1, y1, x2, y2, x, y);
      case 'A':
        final double rx = next();
        final double ry = next();
        final double rotation = next();
        final int large = flag();
        final int sweep = flag();
        x = next() + (rel ? x : 0);
        y = next() + (rel ? y : 0);
        path.arcToPoint(
          Offset(x, y),
          radius: Radius.elliptical(rx, ry),
          rotation: rotation * pi / 180,
          largeArc: large == 1,
          clockwise: sweep == 1,
        );
      case 'Z':
        path.close();
        x = startX;
        y = startY;
      default:
        throw FormatException('unsupported path command $command in $d');
    }
  }
  return path;
}
