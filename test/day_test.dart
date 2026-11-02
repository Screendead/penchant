import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';

void main() {
  test('day arithmetic stays on calendar days', () {
    final DateTime day = DateTime(2026, 3, 29);

    expect(addDays(day, 1), DateTime(2026, 3, 30));
    expect(addDays(day, -29), DateTime(2026, 2, 28));
    expect(addDays(DateTime(2026, 12, 31), 1), DateTime(2027));
    expect(startOfDay(DateTime(2026, 3, 29, 23, 59)), day);
    expect(daysBetween(DateTime(2026, 3, 28, 23), DateTime(2026, 3, 30, 1)), 2);
    expect(daysBetween(day, day), 0);
  });
}
