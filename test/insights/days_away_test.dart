import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/days_away.dart';

final DateTime _first = DateTime(2025, 3, 3);

void main() {
  final DayCell home = dayCellOf(51.5, -0.1);
  final DayCell nearby = dayCellOf(51.6, -0.3); // About 17 km.
  final DayCell far = dayCellOf(53.4, -2.2); // About 260 km.

  test('a day is away when a photo was taken far from home; nearby, at home '
      'or with nothing taken, it is not', () {
    final Map<DateTime, Set<DayCell>> cells = <DateTime, Set<DayCell>>{
      for (int i = 0; i < 40; i += 2) addDays(_first, i): <DayCell>{home},
      addDays(_first, 1): <DayCell>{nearby},
      addDays(_first, 5): <DayCell>{home, far},
    };
    final Map<DateTime, bool> away = daysAwayFrom(
      cells,
      through: addDays(_first, 40),
    );
    expect(away[_first], isFalse);
    expect(away[addDays(_first, 1)], isFalse);
    expect(away[addDays(_first, 3)], isFalse, reason: 'nothing taken');
    expect(away[addDays(_first, 5)], isTrue);
    expect(away.length, 41);
  });

  test('days with nothing taken between two away days are away; a home '
      'photo between them ends the trip', () {
    final Map<DateTime, Set<DayCell>> cells = <DateTime, Set<DayCell>>{
      for (int i = 0; i < 40; i += 2) addDays(_first, i): <DayCell>{home},
      addDays(_first, 21): <DayCell>{far},
      addDays(_first, 25): <DayCell>{far},
      addDays(_first, 45): <DayCell>{far},
      addDays(_first, 48): <DayCell>{far},
    };
    // Days 22 and 24 have home photos; 23, 46 and 47 have nothing.
    final Map<DateTime, bool> away = daysAwayFrom(
      cells,
      through: addDays(_first, 60),
    );
    expect(away[addDays(_first, 23)], isFalse);
    expect(away[addDays(_first, 46)], isTrue);
    expect(away[addDays(_first, 47)], isTrue);
  });

  test('home follows a move of house', () {
    final Map<DateTime, Set<DayCell>> cells = <DateTime, Set<DayCell>>{
      for (int i = 0; i < 400; i += 3)
        addDays(_first, i): <DayCell>{i < 200 ? home : far},
    };
    final Map<DateTime, bool> away = daysAwayFrom(
      cells,
      through: addDays(_first, 400),
    );
    expect(away[addDays(_first, 30)], isFalse);
    expect(away[addDays(_first, 360)], isFalse);
  });

  test('no comparison with fewer away days than a calendar feature needs', () {
    expect(
      daysAway(
        uses: const [],
        away: <DateTime, bool>{
          for (int i = 0; i < 100; i++)
            addDays(_first, i): i < daysAwayMinDays - 1,
        },
        through: addDays(_first, 100),
      ),
      isEmpty,
    );
  });
}
