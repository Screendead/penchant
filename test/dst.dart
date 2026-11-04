// Dart builds DateTimes only in the process time zone, so a DST test can
// discriminate only where that zone changes offset (TZ=Europe/London
// flutter test); elsewhere this is null and the test skips.
DateTime? firstDstTransitionDay(int year) {
  for (int i = 0; i < 365; i++) {
    final DateTime day = DateTime(year, 1, 1 + i);

    if (day.timeZoneOffset != DateTime(year, 1, 2 + i).timeZoneOffset) {
      return day;
    }
  }

  return null;
}

const String noDstSkipReason =
    'local timezone has no DST transition in 2026; '
    'run with TZ=Europe/London to exercise it';
