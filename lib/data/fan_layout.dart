import 'dart:math';
import 'dart:ui' show Offset, Path, PathFillType, Rect;

// The Log fan's geometry in points, about its centre, which sits [lift] above
// the Log button's.
abstract final class FanGeometry {
  static const double lift = 157;
  static const double inner = 44;
  static const double outer = 152;
  static const double label = 84;
  // A drag counts as over a wedge a little beyond its edges.
  static const double reachInner = 40;
  static const double reachOuter = 160;
  static const int maxWedges = 8;
}

// The habits the fan offers in order, and whether a More wedge follows them
// for the rest.
({List<T> shown, bool more}) fanSlots<T>(List<T> habits) =>
    habits.length <= FanGeometry.maxWedges
    ? (shown: habits, more: false)
    : (shown: habits.take(FanGeometry.maxWedges - 1).toList(), more: true);

// Wedge [k] of [n] spans this angle onward, clockwise from the top.
double wedgeStart(int k, int n) => -pi / 2 + 2 * pi * k / n;

double wedgeMiddle(int k, int n) => -pi / 2 + 2 * pi * (k + 0.5) / n;

Offset wedgeLabelPoint(int k, int n, double scale) {
  final double a = wedgeMiddle(k, n);
  return Offset(cos(a), sin(a)) * FanGeometry.label * scale;
}

// Which wedge a point [fromCentre] the fan's centre is over, or null.
int? wedgeAt(Offset fromCentre, int n, {double scale = 1}) {
  final double r = fromCentre.distance;
  if (n == 0 ||
      r < FanGeometry.reachInner * scale ||
      r > FanGeometry.reachOuter * scale) {
    return null;
  }
  final double turn =
      ((atan2(fromCentre.dy, fromCentre.dx) + pi / 2) / (2 * pi)) % 1;
  return (turn * n).floor() % n;
}

// A wedge with straight outer edges between the polygon's corners, as the
// icon draws them, and an arc inside. Below four, a polygon's edge passes
// inside the labels, so the outer edge is an arc too.
Path wedgePath(int k, int n, double scale) {
  if (n == 1) {
    // One habit's wedge is the whole ring.
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(
        Rect.fromCircle(center: Offset.zero, radius: FanGeometry.outer * scale),
      )
      ..addOval(
        Rect.fromCircle(center: Offset.zero, radius: FanGeometry.inner * scale),
      );
  }
  final double a0 = wedgeStart(k, n);
  final double a1 = wedgeStart(k + 1, n);
  final double ri = FanGeometry.inner * scale;
  final double ro = FanGeometry.outer * scale;
  Offset at(double a, double r) => Offset(cos(a), sin(a)) * r;
  final Path path = Path()..moveTo(at(a0, ri).dx, at(a0, ri).dy);
  if (n >= 4) {
    path
      ..lineTo(at(a0, ro).dx, at(a0, ro).dy)
      ..lineTo(at(a1, ro).dx, at(a1, ro).dy);
  } else {
    path
      ..lineTo(at(a0, ro).dx, at(a0, ro).dy)
      ..arcTo(
        Rect.fromCircle(center: Offset.zero, radius: ro),
        a0,
        a1 - a0,
        false,
      );
  }
  return path
    ..lineTo(at(a1, ri).dx, at(a1, ri).dy)
    ..arcTo(
      Rect.fromCircle(center: Offset.zero, radius: ri),
      a1,
      a0 - a1,
      false,
    )
    ..close();
}
