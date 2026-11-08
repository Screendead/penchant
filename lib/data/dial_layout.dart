import 'dart:math';
import 'dart:ui' show Offset, Path, PathOperation, Radius, Rect;

// The Day Dial's face in the units of the design's 320-unit viewBox, centred
// on the origin; a painter scales by its side over [DialFace.side].
abstract final class DialFace {
  static const double side = 320;
  static const double disc = 124;
  static const double hub = 44;
  static const double numerals = 152;
  static const double majorSpokeInner = 54;
  static const double majorSpokeOuter = 140;
  static const double minorSpokeInner = 64;
  static const double minorSpokeOuter = 132;
  static const double hand = 140;
  static const double handDot = 3.2;
  static const double handTip = 3.6;
  static const double clearRing = 116;
  static const double clearBand = 16;
  // The first entry of a habit in an hour sits on the first track; later
  // ones in the same hour step out and in, then repeat.
  static const List<double> tracks = <double>[100, 116, 84, 68];
  static const double beadBase = 7.5;
  static const double beadMin = 5;
  static const double beadMax = 14;
  static const double beadGap = 1.5;
  static const double beadHitSlop = 6;
  // At this many entries or fewer each bead carries its time.
  static const int timedBeads = 4;
  // Above this many entries in a day, an hour holding more than one entry
  // draws them as one arc labelled with its count.
  static const int mergeAbove = 48;
}

// A spoke's opacity, as a fraction of the spoke token's, for [clear] from 0
// (entries) to 1 (a clear day). On a clear day the majors are decoration
// (Jack, r8-clear-spokes B, 2026-11-06): the 00/06/12/18 numerals give the
// time, so the majors drop below the 3:1 floor to the mock-up's 25% with the
// minors.
double spokeOpacity({required bool major, required double clear}) =>
    major ? 1 - 0.75 * clear : 0.45 - 0.2 * clear;

const int minutesPerDay = 24 * 60;

// The wall-clock minute, not the time elapsed since midnight: on a day that
// gains or loses an hour, 15:00 still sits where the face says 15.
double minuteOfDay(DateTime local) =>
    local.hour * 60 + local.minute + local.second / 60;

// Radians clockwise from 00 at the top, in screen coordinates (y down).
double dialAngle(double minute) => minute / minutesPerDay * 2 * pi - pi / 2;

Offset dialPoint(double angle, double radius) =>
    Offset(radius * cos(angle), radius * sin(angle));

// The middle of a habit's entries, so one unusual entry does not move it. A
// habit with no positive entry counts each as its own size.
double typicalQuantity(Iterable<num> quantities) {
  final List<num> sorted = quantities.where((num q) => q > 0).toList()..sort();
  if (sorted.isEmpty) {
    return 1;
  }
  final int mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid].toDouble()
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

// A bead's area grows with its quantity against the habit's typical entry.
double beadRadius(num quantity, double typical) {
  final double ratio = typical > 0 ? max(0, quantity) / typical : 1;
  return (DialFace.beadBase * sqrt(ratio)).clamp(
    DialFace.beadMin,
    DialFace.beadMax,
  );
}

class DialBeadInput {
  const DialBeadInput({
    required this.id,
    required this.habit,
    required this.minute,
    required this.radius,
  });

  final String id;
  final String habit;
  final double minute;
  final double radius;
}

class BeadPlacement {
  const BeadPlacement({
    required this.angle,
    required this.track,
    required this.radius,
  });

  final double angle;
  final double track;
  final double radius;

  Offset get position => dialPoint(angle, track);
}

// Where each bead sits, by id. Beads keep their time's angle except where
// neighbours on one track would touch: those are pushed apart along the arc
// until their edges are [DialFace.beadGap] apart, never off the track. The
// [arcs] hold still on their track and push its beads clear the same way.
// Between two arcs an hour has about 24.7 units of track; a bead too wide
// for that sits midway, overlapping both arcs equally.
Map<String, BeadPlacement> layoutBeads(
  Iterable<DialBeadInput> beads, {
  Iterable<HourArc> arcs = const <HourArc>[],
}) {
  final List<DialBeadInput> ordered = beads.toList()
    ..sort((DialBeadInput a, DialBeadInput b) {
      final int byTime = a.minute.compareTo(b.minute);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });

  final Map<String, int> perHour = <String, int>{};
  final Map<double, List<_Slot>> byTrack = <double, List<_Slot>>{};
  final List<_Slot> slots = <_Slot>[];
  for (final DialBeadInput bead in ordered) {
    final String key = '${bead.habit}:${bead.minute ~/ 60}';
    final int n = perHour[key] ?? 0;
    perHour[key] = n + 1;
    final _Slot slot = _Slot(
      bead.id,
      dialAngle(bead.minute),
      DialFace.tracks[n % DialFace.tracks.length],
      bead.radius,
    );
    slots.add(slot);
    (byTrack[slot.track] ??= <_Slot>[]).add(slot);
  }
  for (final HourArc arc in arcs) {
    (byTrack[HourArc.track] ??= <_Slot>[]).add(
      _Slot(
        'hour-${arc.hour}',
        arc.middle,
        HourArc.track,
        (arc.end - arc.start) / 2 * HourArc.track + HourArc.half,
        fixed: true,
      ),
    );
  }

  for (final MapEntry<double, List<_Slot>>(key: track, value: onTrack)
      in byTrack.entries) {
    onTrack.sort((_Slot a, _Slot b) => a.angle.compareTo(b.angle));
    void separate(_Slot p, _Slot q, double angleGap) {
      final double need = p.radius + q.radius + DialFace.beadGap;
      final double gap = angleGap * track;
      if (gap < need && !(p.fixed && q.fixed)) {
        final double push = (need - gap) / track;
        p.angle -= q.fixed ? push : (p.fixed ? 0 : push / 2);
        q.angle += p.fixed ? push : (q.fixed ? 0 : push / 2);
      }
    }

    for (int pass = 0; pass < 8; pass++) {
      for (int i = 0; i + 1 < onTrack.length; i++) {
        separate(
          onTrack[i],
          onTrack[i + 1],
          onTrack[i + 1].angle - onTrack[i].angle,
        );
      }
      // The face is a circle: the day's last bead neighbours its first
      // across 00.
      if (onTrack.length > 1) {
        separate(
          onTrack.last,
          onTrack.first,
          onTrack.first.angle + 2 * pi - onTrack.last.angle,
        );
      }
    }

    // A pass pushes a bead the whole way off each arc in turn, so one that
    // fits between neither would end up overlapping only the second.
    final int n = onTrack.length;
    for (int i = 0; n >= 3 && i < n; i++) {
      final _Slot s = onTrack[i];
      final _Slot before = onTrack[(i - 1 + n) % n];
      final _Slot after = onTrack[(i + 1) % n];
      if (s.fixed || !before.fixed || !after.fixed) {
        continue;
      }
      final double from =
          before.angle + before.radius / track - (i == 0 ? 2 * pi : 0);
      final double to =
          after.angle - after.radius / track + (i == n - 1 ? 2 * pi : 0);
      if ((to - from) * track < 2 * (s.radius + DialFace.beadGap)) {
        s.angle = (from + to) / 2;
      }
    }
  }

  return <String, BeadPlacement>{
    for (final _Slot s in slots)
      s.id: BeadPlacement(angle: s.angle, track: s.track, radius: s.radius),
  };
}

class _Slot {
  _Slot(this.id, this.angle, this.track, this.radius, {this.fixed = false});

  final String id;
  double angle;
  final double track;
  final double radius;
  final bool fixed;
}

// Where a bead's time label goes, relative to the bead's centre: toward the
// hub, so it never covers the rim. [align] is -1 when the label's right edge
// sits there, 0 when its centre does and 1 when its left edge does.
({Offset offset, int align}) beadLabelOffset(double angle, double radius) {
  final double dx = -cos(angle) * (radius + 8);
  final double dy = -sin(angle) * (radius + 10);
  return (
    offset: Offset(dx, dy),
    align: dx.abs() < 5
        ? 0
        : dx > 0
        ? 1
        : -1,
  );
}

// The hours, 0 to 23, whose entries merge into one arc: on a day of more than
// [DialFace.mergeAbove] entries, each hour that holds more than one.
Set<int> denseHours(Iterable<double> minutes) {
  final List<double> all = minutes.toList();
  if (all.length <= DialFace.mergeAbove) {
    return const <int>{};
  }
  final Map<int, int> perHour = <int, int>{};
  for (final double minute in all) {
    final int hour = minute ~/ 60;
    perHour[hour] = (perHour[hour] ?? 0) + 1;
  }
  return <int>{
    for (final MapEntry<int, int>(:key, :value) in perHour.entries)
      if (value > 1) key,
  };
}

// An hour's arc on the first track, a bead wide, with round ends. [start] and
// [end] are the angles of its ends' centres, inset so neighbouring hours'
// arcs stay [DialFace.beadGap] apart.
class HourArc {
  HourArc(this.hour)
    : start = dialAngle(hour * 60.0) + _inset,
      end = dialAngle((hour + 1) * 60.0) - _inset;

  static const double track = 100;
  static const double half = DialFace.beadBase;
  static const double _inset = (half + DialFace.beadGap / 2) / track;
  // The angle a round end adds beyond its centre.
  static const double _cap = half / track;

  final int hour;
  final double start;
  final double end;

  double get middle => (start + end) / 2;

  // The arc's outline at [radius] from the centre and [width] across, both
  // scaled from [track] and [half] as the dial contracts or the arc springs.
  Path outline({double radius = track, double width = half}) {
    final Path path = Path()..moveTo(0, 0);
    if (radius <= 0 || width <= 0) {
      return path;
    }
    final Offset outerStart = dialPoint(start, radius + width);
    return Path()
      ..moveTo(outerStart.dx, outerStart.dy)
      ..arcTo(
        Rect.fromCircle(center: Offset.zero, radius: radius + width),
        start,
        end - start,
        false,
      )
      ..arcToPoint(
        dialPoint(end, radius - width),
        radius: Radius.circular(width),
      )
      ..arcTo(
        Rect.fromCircle(center: Offset.zero, radius: radius - width),
        end,
        start - end,
        false,
      )
      ..arcToPoint(outerStart, radius: Radius.circular(width))
      ..close();
  }

  // The arc cut into consecutive pieces in proportion to [counts], from its
  // start clockwise.
  List<Path> shares(
    List<int> counts, {
    double radius = track,
    double width = half,
  }) {
    final Path whole = outline(radius: radius, width: width);
    final int total = counts.fold(0, (int sum, int n) => sum + n);
    if (total == 0 || radius <= 0 || width <= 0) {
      return <Path>[for (final int _ in counts) Path()];
    }
    final double from = start - _cap;
    final double span = end + _cap - from;
    final double reach = (radius + width) * 2;
    final List<Path> out = <Path>[];
    double at = from;
    for (final int n in counts) {
      final double next = at + span * n / total;
      final Offset a = dialPoint(at, reach);
      final Path wedge = Path()
        ..moveTo(0, 0)
        ..lineTo(a.dx, a.dy)
        ..arcTo(
          Rect.fromCircle(center: Offset.zero, radius: reach),
          at,
          next - at,
          false,
        )
        ..close();
      out.add(Path.combine(PathOperation.intersect, whole, wedge));
      at = next;
    }
    return out;
  }

  // The minute of the day a point on the face points at, for a tap.
  static double minuteAt(Offset point) {
    final double turn = ((atan2(point.dy, point.dx) + pi / 2) / (2 * pi)) % 1;
    return turn * minutesPerDay;
  }
}
