import 'package:flutter/widgets.dart';
import 'package:tracker/design/tokens.dart';

// The app icon as the header draws it: the five habit colours as a pentagon of
// wedges on a paper tile, with ink spokes. Paper in both themes, as the icon
// itself is. Points are the mock-up's, on a 100-unit tile.
class PenchantMark extends StatelessWidget {
  const PenchantMark({super.key, this.size = 26});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: _MarkPainter()),
    ),
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter();

  static const List<Offset> _rim = <Offset>[
    Offset(50, 14),
    Offset(80.8, 40),
    Offset(65.5, 71.4),
    Offset(31.7, 75.2),
    Offset(29.5, 43.3),
  ];
  static const List<Offset> _spokes = <Offset>[
    Offset(50, 10),
    Offset(88, 37.6),
    Offset(73.5, 82.4),
    Offset(26.5, 82.4),
    Offset(12, 37.6),
  ];
  static const Offset _centre = Offset(50, 50);

  @override
  void paint(Canvas canvas, Size size) {
    final DialPalette light = DialPalette.light;
    canvas
      ..save()
      ..clipRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(size.width * 7 / 26),
        ),
      )
      ..scale(size.width / 100, size.height / 100)
      ..drawRect(
        const Rect.fromLTWH(0, 0, 100, 100),
        Paint()..color = light.bg,
      );
    for (int i = 0; i < 5; i++) {
      canvas.drawPath(
        Path()
          ..moveTo(_centre.dx, _centre.dy)
          ..lineTo(_rim[i].dx, _rim[i].dy)
          ..lineTo(_rim[(i + 1) % 5].dx, _rim[(i + 1) % 5].dy)
          ..close(),
        Paint()..color = light.data[i],
      );
    }
    final Paint spoke = Paint()
      ..color = light.text.withValues(alpha: 0.45)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    for (final Offset end in _spokes) {
      canvas.drawLine(_centre, end, spoke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) => false;
}
