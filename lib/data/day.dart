// Calendar arithmetic goes through the DateTime constructor rather than
// Duration so that a day stays aligned to local midnight across daylight-saving
// transitions, where a calendar day is 23 or 25 hours long.

DateTime startOfDay(DateTime time) => DateTime(time.year, time.month, time.day);

DateTime addDays(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);

int daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
