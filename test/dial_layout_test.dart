import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/dial_layout.dart';
import 'package:tracker/data/fan_layout.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/widgets/day_dial.dart';

import 'dst.dart';
import 'fakes.dart';

void main() {
  group('spokes', () {
    test('majors are full strength with entries, minors at 45%', () {
      expect(spokeOpacity(major: true, clear: 0), 1);
      expect(spokeOpacity(major: false, clear: 0), closeTo(0.45, 1e-9));
    });

    test('both fade to the mock-up\'s 25% on a clear day', () {
      expect(spokeOpacity(major: true, clear: 1), closeTo(0.25, 1e-9));
      expect(spokeOpacity(major: false, clear: 1), closeTo(0.25, 1e-9));
    });

    test('fade with the clear ring as it draws on', () {
      expect(spokeOpacity(major: true, clear: 0.5), closeTo(0.625, 1e-9));
      expect(spokeOpacity(major: false, clear: 0.5), closeTo(0.35, 1e-9));
    });
  });

  group('time on the face', () {
    test('runs clockwise from 00 at the top', () {
      Offset at(int hour) => dialPoint(dialAngle(hour * 60.0), 100);
      expect(at(0).dx, closeTo(0, 1e-9));
      expect(at(0).dy, closeTo(-100, 1e-9));
      expect(at(6).dx, closeTo(100, 1e-9));
      expect(at(12).dy, closeTo(100, 1e-9));
      expect(at(18).dx, closeTo(-100, 1e-9));
    });

    test('is the wall-clock minute, seconds included', () {
      expect(minuteOfDay(DateTime(2026, 11, 5, 21, 10, 30)), 21 * 60 + 10.5);
      expect(minuteOfDay(DateTime(2026, 11, 5)), 0);
    });

    final DateTime? transition = firstDstTransitionDay(2026);
    test('puts an entry on a day that gains or loses an hour where its clock '
        'time is', () {
      final DateTime day = transition!;
      final DateTime afternoon = DateTime(day.year, day.month, day.day, 14);
      // The time since midnight is an hour off on such a day.
      expect(afternoon.difference(day).inMinutes, isNot(14 * 60));
      expect(minuteOfDay(afternoon), 14 * 60);
      expect(dialAngle(minuteOfDay(afternoon)), closeTo(pi * 2 / 3, 1e-9));
      expect(daysBetween(day, addDays(day, 1)), 1);
    }, skip: transition == null ? noDstSkipReason : false);
  });

  group('bead size', () {
    test("is the middle of the habit's entries", () {
      expect(typicalQuantity(<int>[1, 1, 9]), 1);
      expect(typicalQuantity(<int>[10, 20, 35, 15]), 17.5);
      expect(typicalQuantity(<int>[]), 1);
      // Legacy zero quantities say nothing about a typical entry.
      expect(typicalQuantity(<int>[0, 0, 4]), 4);
      expect(typicalQuantity(<int>[0]), 1);
    });

    test('grows in area with the quantity, within 5 to 14', () {
      expect(beadRadius(1, 1), DialFace.beadBase);
      expect(beadRadius(4, 2), closeTo(7.5 * sqrt(2), 1e-9));
      expect(beadRadius(100, 1), DialFace.beadMax);
      expect(beadRadius(1, 100), DialFace.beadMin);
      expect(beadRadius(0, 3), DialFace.beadMin);
    });
  });

  group('bead layout', () {
    DialBeadInput bead(String id, String habit, double minute) =>
        DialBeadInput(id: id, habit: habit, minute: minute, radius: 7.5);

    test("a habit's later entries in one hour step out and in from the "
        'first track, then repeat', () {
      final Map<String, BeadPlacement> layout = layoutBeads(<DialBeadInput>[
        for (int i = 0; i < 5; i++) bead('c$i', 'coffee', 600.0 + 10 * i),
      ]);
      expect(
        <double>[for (int i = 0; i < 5; i++) layout['c$i']!.track],
        <double>[100, 116, 84, 68, 100],
      );
    });

    test('other habits in the same hour start on the first track too', () {
      final Map<String, BeadPlacement> layout = layoutBeads(<DialBeadInput>[
        bead('a', 'coffee', 600),
        bead('b', 'tea', 601),
        bead('c', 'coffee', 661),
      ]);
      expect(layout['a']!.track, 100);
      expect(layout['b']!.track, 100);
      expect(layout['c']!.track, 100);
    });

    test('neighbours on a track are pushed apart along the arc, keeping '
        'their order', () {
      final Map<String, BeadPlacement> layout = layoutBeads(<DialBeadInput>[
        bead('a', 'coffee', 600),
        bead('b', 'tea', 601),
        bead('c', 'cake', 602),
      ]);
      final List<BeadPlacement> p = <BeadPlacement>[
        layout['a']!,
        layout['b']!,
        layout['c']!,
      ];
      for (int i = 0; i + 1 < p.length; i++) {
        expect(p[i].angle, lessThan(p[i + 1].angle));
        final double gap =
            (p[i + 1].position - p[i].position).distance -
            p[i].radius -
            p[i + 1].radius;
        expect(gap, greaterThan(DialFace.beadGap - 0.2));
      }
      // The middle one stays on its time; the pushes are symmetric.
      expect(p[1].angle, closeTo(dialAngle(601), 0.01));
    });

    test('beads either side of midnight are pushed apart across 00', () {
      final Map<String, BeadPlacement> layout = layoutBeads(<DialBeadInput>[
        bead('late', 'nights', 23 * 60 + 58),
        bead('early', 'nights', 2),
      ]);
      final BeadPlacement late = layout['late']!;
      final BeadPlacement early = layout['early']!;
      expect(late.track, early.track);
      final double gap =
          (late.position - early.position).distance -
          late.radius -
          early.radius;
      expect(gap, greaterThan(DialFace.beadGap - 0.2));
      // Each keeps its side of 00.
      expect(late.position.dx, lessThan(0));
      expect(early.position.dx, greaterThan(0));
    });

    test('beads far apart stay exactly on their times', () {
      final Map<String, BeadPlacement> layout = layoutBeads(<DialBeadInput>[
        bead('a', 'coffee', 60),
        bead('b', 'coffee', 600),
      ]);
      expect(layout['a']!.angle, dialAngle(60));
      expect(layout['b']!.angle, dialAngle(600));
    });

    test("a time label sits on the hub's side of its bead", () {
      for (final int hour in <int>[0, 3, 6, 9, 12, 15, 18, 21]) {
        final double a = dialAngle(hour * 60.0);
        final Offset bead = dialPoint(a, 100);
        final ({Offset offset, int align}) label = beadLabelOffset(a, 7.5);
        expect(
          (bead + label.offset).distance,
          lessThan(bead.distance),
          reason: '$hour:00',
        );
      }
      expect(beadLabelOffset(dialAngle(0), 7.5).align, 0);
      expect(beadLabelOffset(dialAngle(360), 7.5).align, -1);
      expect(beadLabelOffset(dialAngle(1080), 7.5).align, 1);
    });
  });

  group('a dense hour', () {
    List<double> minutes(int n, double first, double step) => <double>[
      for (int i = 0; i < n; i++) first + step * i,
    ];

    test('merges nothing at 48 entries or fewer', () {
      expect(denseHours(minutes(48, 480, 2)), isEmpty);
    });

    test("above 48, merges each hour holding more than one entry", () {
      expect(
        denseHours(<double>[...minutes(48, 480, 2), 900, 1200, 1210]),
        <int>{8, 9, 20},
      );
    });

    test("neighbouring hours' arcs are a bead's gap apart", () {
      final double gap =
          (HourArc(9).start - HourArc(8).end) * HourArc.track -
          2 * HourArc.half;
      expect(gap, closeTo(DialFace.beadGap, 1e-9));
      expect(HourArc(8).middle, closeTo(dialAngle(510), 1e-9));
    });

    test("pushes a lone bead clear of the next and the previous hour's arc, "
        'across 00 too', () {
      const double cap = HourArc.half / HourArc.track;
      final Map<String, BeadPlacement> placed = layoutBeads(
        const <DialBeadInput>[
          DialBeadInput(id: 'a', habit: 'h', minute: 538, radius: 10),
          DialBeadInput(id: 'b', habit: 'h', minute: 605, radius: 10),
          DialBeadInput(id: 'c', habit: 'h', minute: 2, radius: 10),
        ],
        arcs: <HourArc>[HourArc(9), HourArc(23)],
      );
      double clearance(double from, double to) =>
          (to - from) * HourArc.track - 10;
      expect(
        clearance(placed['a']!.angle, HourArc(9).start - cap),
        closeTo(DialFace.beadGap, 1e-6),
      );
      expect(
        clearance(HourArc(9).end + cap, placed['b']!.angle),
        closeTo(DialFace.beadGap, 1e-6),
      );
      expect(
        clearance(HourArc(23).end + cap, placed['c']!.angle + 2 * pi),
        closeTo(DialFace.beadGap, 1e-6),
      );
      for (final BeadPlacement p in placed.values) {
        expect(p.track, HourArc.track);
      }
    });

    test('a point on the face reads as its minute, across 00 too', () {
      expect(
        HourArc.minuteAt(dialPoint(dialAngle(510), 50)),
        closeTo(510, 1e-6),
      );
      expect(
        HourArc.minuteAt(dialPoint(dialAngle(minutesPerDay - 1), 100)),
        closeTo(minutesPerDay - 1, 1e-6),
      );
      expect(HourArc.minuteAt(dialPoint(dialAngle(1), 100)), closeTo(1, 1e-6));
    });

    test('is shared out clockwise in proportion to the counts', () {
      // At 06 the face runs straight down.
      final List<Rect> pieces = <Rect>[
        for (final Path p in HourArc(6).shares(<int>[1, 3])) p.getBounds(),
      ];
      final Rect whole = HourArc(6).outline().getBounds();
      expect(pieces[0].top, closeTo(whole.top, 0.2));
      expect(pieces[1].bottom, closeTo(whole.bottom, 0.2));
      expect(pieces[0].center.dy, lessThan(pieces[1].center.dy));
      // Three times the share, less the round end the first one holds.
      expect(pieces[1].height, greaterThan(pieces[0].height * 2.5));
    });
  });

  group('the summary', () {
    final DateTime today = DateTime(2026, 11, 5);
    final List<Vice> habits = <Vice>[
      Vice(
        id: 'c',
        name: 'Coffee',
        unit: Unit.drink,
        ownerID: ownerID,
        createdAt: fakeVice('c').createdAt,
        archived: false,
      ),
      Vice(
        id: 'l',
        name: 'Late nights',
        unit: Unit.time,
        ownerID: ownerID,
        createdAt: fakeVice('l').createdAt,
        archived: false,
      ),
    ];

    test('names the day, each total, and the first and last entry', () {
      expect(
        DayDial.summary(
          today,
          today,
          habits,
          <int>[5, 1],
          <DateTime>[
            DateTime(2026, 11, 5, 20, 50),
            DateTime(2026, 11, 5, 0, 40),
          ],
          alwaysUse24HourFormat: true,
        ),
        'Today, ${dayPillDate(today, today)}. Coffee 5 drinks, '
        'Late nights 1 time. First entry 00:40, last 20:50.',
      );
    });

    test('says one entry once, and a clear day as nothing recorded', () {
      final DateTime yesterday = addDays(today, -1);
      expect(
        DayDial.summary(
          yesterday,
          today,
          habits,
          <int>[1, 0],
          <DateTime>[DateTime(2026, 11, 4, 8, 10)],
          alwaysUse24HourFormat: true,
        ),
        endsWith('Coffee 1 drink, Late nights 0 times. One entry, at 08:10.'),
      );
      expect(
        DayDial.summary(
          addDays(today, -5),
          today,
          habits,
          <int>[0, 0],
          const <DateTime>[],
          alwaysUse24HourFormat: true,
        ),
        '${formatDay(addDays(today, -5))}. Coffee 0 drinks, '
        'Late nights 0 times. Nothing recorded.',
      );
    });

    test("an arc names its hour, then each habit's total in habit order", () {
      DialEntry entry(int h, int hour, int minute, int q) => DialEntry(
        id: '$h-$hour-$minute',
        vice: habits[h],
        mark: HabitMark(h),
        quantity: q,
        at: DateTime(2026, 11, 5, hour, minute),
      );
      expect(
        DayDial.arcLabel(8, <DialEntry>[
          entry(1, 8, 5, 1),
          entry(0, 8, 10, 2),
          entry(0, 8, 40, 1),
        ], alwaysUse24Hour: true),
        '3 entries from 08:00 to 09:00: Coffee 3 drinks, Late nights 1 time',
      );
      expect(
        DayDial.arcLabel(23, <DialEntry>[
          entry(0, 23, 5, 1),
          entry(0, 23, 50, 1),
        ], alwaysUse24Hour: true),
        '2 entries from 23:00 to 00:00: Coffee 2 drinks',
      );
    });

    test('sizes beads against each habit on its own', () {
      final Map<String, double> typical = DayDial.typicals(<DialEntry>[
        for (final int q in <int>[10, 20, 30])
          DialEntry(
            id: 'm$q',
            vice: habits[0],
            mark: const HabitMark(0),
            quantity: q,
            at: today,
          ),
        DialEntry(
          id: 'n',
          vice: habits[1],
          mark: const HabitMark(1),
          quantity: 1,
          at: today,
        ),
      ]);
      expect(typical, <String, double>{'c': 20, 'l': 1});
    });

    test('a stored typical replaces the day\'s median for its habit only', () {
      final List<DialEntry> entries = <DialEntry>[
        for (final int q in <int>[10, 20, 30])
          DialEntry(
            id: 'm$q',
            vice: habits[0],
            mark: const HabitMark(0),
            quantity: q,
            at: today,
          ),
        DialEntry(
          id: 'n',
          vice: habits[1],
          mark: const HabitMark(1),
          quantity: 4,
          at: today,
        ),
      ];
      expect(
        DayDial.typicals(entries, stored: <String, double>{'c': 5, 'x': 9}),
        <String, double>{'c': 5, 'l': 4},
      );
      expect(
        DayDial.layout(
          entries,
          stored: <String, double>{'c': 5},
        )['m20']!.radius,
        beadRadius(20, 5),
      );
      expect(DayDial.layout(entries)['m20']!.radius, beadRadius(20, 20));
    });
  });

  group('the Log fan', () {
    test('offers up to eight habits, then seven and More', () {
      expect(fanSlots(<int>[1, 2, 3, 4, 5, 6, 7, 8]).more, isFalse);
      final ({List<int> shown, bool more}) ten = fanSlots(<int>[
        for (int i = 0; i < 10; i++) i,
      ]);
      expect(ten.more, isTrue);
      expect(ten.shown, <int>[0, 1, 2, 3, 4, 5, 6]);
    });

    test('finds the wedge under a point, clockwise from the top', () {
      Offset towards(double degrees, double r) =>
          Offset(cos(degrees * pi / 180), sin(degrees * pi / 180)) * r;
      // Five wedges of 72 degrees, the first starting straight up.
      expect(wedgeAt(towards(-90 + 10, 100), 5), 0);
      expect(wedgeAt(towards(-90 + 80, 100), 5), 1);
      expect(wedgeAt(towards(-90 + 359, 100), 5), 4);
      expect(wedgeAt(towards(0, 20), 5), isNull);
      expect(wedgeAt(towards(0, 200), 5), isNull);
      expect(wedgeAt(towards(0, 100), 5, scale: 0.5), isNull);
    });

    test("a wedge's label point is inside its own shape", () {
      for (final int n in <int>[1, 2, 3, 5, 8]) {
        for (int k = 0; k < n; k++) {
          expect(
            wedgePath(k, n, 1).contains(wedgeLabelPoint(k, n, 1)),
            isTrue,
            reason: 'wedge $k of $n',
          );
          expect(wedgeAt(wedgeLabelPoint(k, n, 1), n), k);
        }
      }
    });
  });
}
