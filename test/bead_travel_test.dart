import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/dial_layout.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/widgets/day_dial.dart';

import 'fakes.dart';

final DateTime _day = DateTime(2026, 11, 4);
final Vice _coffee = fakeVice('coffee');

DialEntry _entry(int hour, {bool pending = false}) => DialEntry(
  id: 'edited',
  vice: _coffee,
  mark: const HabitMark(0),
  quantity: 1,
  at: _day.add(Duration(hours: hour)),
  pending: pending,
);

Future<void> _pump(
  WidgetTester tester,
  DialEntry entry, {
  bool reduced = false,
  bool ticking = true,
}) => tester.pumpWidget(
  ProviderScope(
    child: MaterialApp(
      theme: appTheme(Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: TickerMode(
          enabled: ticking,
          child: Center(
            child: SizedBox.square(
              dimension: DialFace.side,
              child: DayDial(
                day: _day,
                today: DateTime(2026, 11, 5),
                entries: <DialEntry>[entry],
                semanticsLabel: 'dial',
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

// The bead's angle on the dial, from its tap target's centre.
double _angle(WidgetTester tester) {
  final Offset d =
      tester.getCenter(find.byKey(const ValueKey<String>('bead-edited'))) -
      tester.getCenter(find.byType(DayDial));
  return atan2(d.dy, d.dx);
}

void main() {
  testWidgets('an edited bead travels round the rim the short way to its new '
      'time', (tester) async {
    await _pump(tester, _entry(9));
    await tester.pumpAndSettle();
    expect(_angle(tester), closeTo(dialAngle(9 * 60), 0.01));

    await _pump(tester, _entry(15));
    await tester.pump();
    expect(_angle(tester), closeTo(dialAngle(9 * 60), 0.01));
    await tester.pump(DialMotion.beadTravel ~/ 2);
    // Half way along the eased path, about noon: clockwise, the short way.
    expect(_angle(tester), closeTo(dialAngle(12 * 60), 0.05));

    await tester.pump(DialMotion.beadTravel);
    await tester.pumpAndSettle();
    expect(_angle(tester), closeTo(dialAngle(15 * 60), 0.01));
  });

  testWidgets('across midnight it goes the short way too', (tester) async {
    await _pump(tester, _entry(23));
    await tester.pumpAndSettle();
    await _pump(tester, _entry(1));
    await tester.pump();
    await tester.pump(DialMotion.beadTravel ~/ 2);
    expect(_angle(tester), closeTo(dialAngle(0), 0.05));
    await tester.pumpAndSettle();
    expect(_angle(tester), closeTo(dialAngle(60), 0.01));
  });

  for (final bool pending in <bool>[false, true]) {
    testWidgets('an edit made while a page covers the dial travels once the '
        'dial shows again${pending ? ', its rim turning meanwhile' : ''}', (
      tester,
    ) async {
      await _pump(tester, _entry(9, pending: pending));
      await tester.pump(const Duration(seconds: 2));
      await _pump(tester, _entry(15, pending: pending), ticking: false);
      await tester.pump(const Duration(seconds: 5));

      await _pump(tester, _entry(15));
      await tester.pump();
      expect(_angle(tester), closeTo(dialAngle(9 * 60), 0.01));
      await tester.pump(DialMotion.beadTravel ~/ 2);
      expect(_angle(tester), closeTo(dialAngle(12 * 60), 0.05));
      await tester.pump(DialMotion.beadTravel);
      await tester.pumpAndSettle();
      expect(_angle(tester), closeTo(dialAngle(15 * 60), 0.01));
    });
  }

  testWidgets('under reduce motion the bead appears at its new time', (
    tester,
  ) async {
    await _pump(tester, _entry(9), reduced: true);
    await tester.pumpAndSettle();
    await _pump(tester, _entry(15), reduced: true);
    await tester.pump();
    expect(_angle(tester), closeTo(dialAngle(15 * 60), 0.01));
    await tester.pumpAndSettle();
  });
}
