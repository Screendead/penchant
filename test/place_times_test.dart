import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/insights/place_times.dart';
import 'package:tracker/insights/places.dart';

List<String> _lines(List<PlaceStay> stays, {int placeId = 1}) =>
    placeTimesLines(stays, placeId, alwaysUse24HourFormat: true);

// Days from Monday 2 March 2026.
DateTime _at(int day, int hour, [int minute = 0]) {
  final DateTime d = addDays(DateTime(2026, 3, 2), day);
  return DateTime(d.year, d.month, d.day, hour, minute);
}

DateTime _monday(int week, int hour, [int minute = 0]) =>
    _at(week * 7, hour, minute);

void main() {
  test('nothing known says nothing', () {
    expect(_lines(const <PlaceStay>[]), isEmpty);
    expect(
      _lines(<PlaceStay>[PlaceStay(2, _monday(0, 9), _monday(0, 17))]),
      isEmpty,
    );
  });

  test('a few visits give dates and a count, nothing usual', () {
    expect(
      _lines(<PlaceStay>[
        PlaceStay(1, _monday(0, 9), _monday(0, 17)),
        PlaceStay(1, _monday(2, 9), _monday(2, 17)),
      ]),
      <String>[
        '2 visits, ${formatDate(DateTime(2026, 3, 2))} to '
            '${formatDate(DateTime(2026, 3, 16))}',
      ],
    );
  });

  test('working days give the usual weekdays and hours', () {
    final List<PlaceStay> stays = <PlaceStay>[
      for (int week = 0; week < 3; week++)
        for (int d = 0; d < 5; d++)
          PlaceStay(1, _at(week * 7 + d, 9, d * 2), _at(week * 7 + d, 17, 20)),
    ];
    final List<String> lines = _lines(stays);
    expect(lines.last, 'Mostly weekdays, usually 09:00 to 17:15');
  });

  test('one weekday is named', () {
    final List<String> lines = _lines(<PlaceStay>[
      for (int week = 0; week < 4; week++)
        PlaceStay(1, _monday(week, 18), _monday(week, 19, 30)),
    ]);
    expect(lines.last, 'Mostly Mondays, usually 18:00 to 19:30');
  });

  test('stays over midnight are said to be overnight', () {
    final List<String> lines = _lines(<PlaceStay>[
      for (int night = 0; night < 7; night++)
        PlaceStay(1, _at(night, 22), _at(night + 1, 7)),
    ]);
    expect(lines.last, 'Usually overnight');
  });

  test('an open visit says the person is there now and is no usual time', () {
    final List<String> lines = _lines(<PlaceStay>[
      for (int week = 0; week < 3; week++)
        PlaceStay(1, _monday(week, 9), _monday(week, 17)),
      PlaceStay(1, _monday(3, 8, 5), null),
    ]);
    expect(lines.first, startsWith('4 visits, '));
    expect(lines, contains('There now, since 08:05'));
    expect(lines.where((l) => l.startsWith('Mostly')), isEmpty);
  });

  test('photo stays give their own dates, said to be from photos, and no '
      'usual time', () {
    final List<String> lines = _lines(<PlaceStay>[
      for (int week = 0; week < 6; week++)
        PlaceStay(
          1,
          _monday(week, 12),
          _monday(week, 13),
          source: PlaceSource.photos,
        ),
    ]);
    expect(lines, <String>[
      'From photos: 6 stays, ${formatDate(DateTime(2026, 3, 2))} to '
          '${formatDate(DateTime(2026, 4, 6))}',
    ]);
  });
}
