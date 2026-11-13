import 'package:tracker/data/day.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/insights/places.dart';

/// The fewest finished visits from which a usual time is said.
const int placeUsualMinStays = 4;

/// Share of visits that makes a weekday pattern "mostly".
const double _mostly = 0.75;

/// When the person was at [placeId], as lines for the sheet that names it:
/// how many visits and over which dates, the same for stays found in photos,
/// whether they are there now, and, from [placeUsualMinStays] finished visits,
/// the usual days and hours. Photo stays only say when photos were taken, so
/// they give dates and nothing usual.
List<String> placeTimesLines(
  List<PlaceStay> stays,
  int placeId, {
  required bool alwaysUse24HourFormat,
}) {
  final List<PlaceStay> visits = <PlaceStay>[
    for (final PlaceStay s in stays)
      if (s.placeId == placeId && !s.fromPhotos) s,
  ]..sort((a, b) => a.arrival.compareTo(b.arrival));
  final List<PlaceStay> photos = <PlaceStay>[
    for (final PlaceStay s in stays)
      if (s.placeId == placeId && s.fromPhotos) s,
  ]..sort((a, b) => a.arrival.compareTo(b.arrival));
  String time(int minuteOfDay) => formatTime(
    DateTime(2000, 1, 1, minuteOfDay ~/ 60, minuteOfDay % 60),
    alwaysUse24HourFormat: alwaysUse24HourFormat,
  );

  final List<String> lines = <String>[];
  if (visits.isNotEmpty) {
    lines.add(
      '${_count(visits.length, 'visit', 'visits')}, '
      '${_dates(visits.first.arrival, visits.last.arrival)}',
    );
  }
  if (photos.isNotEmpty) {
    lines.add(
      'From photos: ${_count(photos.length, 'stay', 'stays')}, '
      '${_dates(photos.first.arrival, photos.last.arrival)}',
    );
  }
  final PlaceStay? open = visits.lastOrNull;
  if (open != null && open.departure == null) {
    lines.add('There now, since ${time(_minuteOf(open.arrival))}');
  }

  // A visit over midnight says nothing of usual hours by clock time alone.
  final List<PlaceStay> finished = <PlaceStay>[
    for (final PlaceStay s in visits)
      if (s.departure case final DateTime left
          when startOfDay(left) == startOfDay(s.arrival))
        s,
  ];
  final int overnight = visits
      .where(
        (s) =>
            s.departure != null &&
            startOfDay(s.departure!) != startOfDay(s.arrival),
      )
      .length;
  final int closed = finished.length + overnight;
  if (closed < placeUsualMinStays) return lines;

  final String? days = _usualDays(<DateTime>[
    for (final PlaceStay s in visits)
      if (s.departure != null) s.arrival,
  ]);
  final String? hours = overnight / closed >= _mostly
      ? 'usually overnight'
      : finished.length >= placeUsualMinStays
      ? 'usually ${time(_median(<int>[for (final PlaceStay s in finished) _minuteOf(s.arrival)]))} '
            'to ${time(_median(<int>[for (final PlaceStay s in finished) _minuteOf(s.departure!)]))}'
      : null;
  if (days != null || hours != null) {
    final String said = <String>[?days, ?hours].join(', ');
    lines.add('${said[0].toUpperCase()}${said.substring(1)}');
  }
  return lines;
}

String _count(int n, String one, String other) =>
    '${formatCount(n)} ${pluralWord(n, one: one, other: other)}';

String _dates(DateTime first, DateTime last) =>
    startOfDay(first) == startOfDay(last)
    ? 'on ${formatDate(first)}'
    : '${formatDate(first)} to ${formatDate(last)}';

int _minuteOf(DateTime t) => t.hour * 60 + t.minute;

/// The middle value, to the nearest quarter hour.
int _median(List<int> minutes) {
  final List<int> sorted = List<int>.of(minutes)..sort();
  final int n = sorted.length;
  final double middle = n.isOdd
      ? sorted[n ~/ 2].toDouble()
      : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
  return ((middle / 15).round() * 15).clamp(0, 24 * 60 - 15);
}

String? _usualDays(List<DateTime> arrivals) {
  if (arrivals.isEmpty) return null;
  final int weekend = arrivals
      .where(
        (t) => t.weekday == DateTime.saturday || t.weekday == DateTime.sunday,
      )
      .length;
  final int n = arrivals.length;
  final Map<int, int> byDay = <int, int>{};
  for (final DateTime t in arrivals) {
    byDay[t.weekday] = (byDay[t.weekday] ?? 0) + 1;
  }
  final MapEntry<int, int> top = byDay.entries.reduce(
    (a, b) => b.value > a.value ? b : a,
  );
  if (top.value / n >= _mostly) {
    return 'mostly ${_weekdayName(top.key)}s';
  }
  if ((n - weekend) / n >= _mostly) return 'mostly weekdays';
  if (weekend / n >= _mostly) return 'mostly weekends';
  return null;
}

String _weekdayName(int weekday) => const <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
][weekday - 1];
