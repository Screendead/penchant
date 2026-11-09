import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/formats.dart';

void main() {
  final DateTime moment = DateTime(2026, 11, 4, 14, 3, 22);

  setUpAll(() => formatLocale);

  group('localeForFormatting', () {
    test('keeps an English variant the device lists', () {
      expect(localeForFormatting(const [Locale('en', 'GB')]), 'en_GB');
      expect(
        localeForFormatting(const [Locale('fr', 'FR'), Locale('en', 'AU')]),
        'en_AU',
      );
    });

    test('takes the region of a non-English first language', () {
      expect(localeForFormatting(const [Locale('de', 'IE')]), 'en_IE');
    });

    test('falls back to en where English has no data for the region', () {
      expect(localeForFormatting(const [Locale('fr', 'FR')]), 'en');
      expect(localeForFormatting(const [Locale('ja')]), 'en');
      expect(localeForFormatting(const []), 'en');
    });
  });

  group('resolveAppLocale', () {
    test('gives Flutter the locale the formats use', () {
      expect(
        resolveAppLocale(const [
          Locale('en', 'US'),
          Locale('en', 'GB'),
        ], appLocales),
        const Locale('en'),
      );
      expect(
        resolveAppLocale(const [Locale('de', 'IE')], appLocales),
        const Locale('en', 'IE'),
      );
    });

    test('falls back to en where Flutter has no such region', () {
      expect(
        resolveAppLocale(const [Locale('en', 'MY')], appLocales),
        const Locale('en'),
      );
      expect(resolveAppLocale(null, appLocales), const Locale('en'));
    });
  });

  test('the region sets the day order, words stay English', () {
    expect(DateFormat.yMd('en_US').format(moment), '11/4/2026');
    expect(DateFormat.yMd('en_GB').format(moment), '04/11/2026');
    expect(DateFormat.yMMMMEEEEd('en_GB').format(moment), contains('November'));
  });

  test('a 12-hour time is not something a user can type', () {
    expect(DateFormat.jms('en_US').format(moment), '2:03:22\u202fPM');
  });

  test('every region parses the entry format it writes', () {
    for (final String locale in ['en', 'en_US', 'en_GB', 'en_AU', 'en_IN']) {
      final DateFormat entry = DateFormat.yMd(locale).add_Hms();
      expect(entry.parse(entry.format(moment)), moment, reason: locale);
      expect(entry.format(moment), isNot(contains('\u202f')), reason: locale);
    }
  });

  test('the test device formats as en_US', () {
    expect(formatLocale, 'en_US');
    expect(formatDay(moment), 'Wednesday, November 4, 2026');
    expect(formatShortDay(moment), 'Nov 4');
    expect(formatCount(12345), '12,345');
  });

  test('the history time follows the device clock', () {
    expect(
      formatDayAndTime(moment, alwaysUse24HourFormat: true),
      'Wed, Nov 4, 2026 14:03',
    );
    expect(
      formatDayAndTime(moment, alwaysUse24HourFormat: false),
      'Wed, Nov 4, 2026 2:03\u202fPM',
    );
  });

  test('relative days', () {
    expect(relativeDay(0), 'Today');
    expect(relativeDay(1), 'Yesterday');
    expect(relativeDay(2), '2 days ago');
  });

  test('unit labels use English plurals and grouped digits', () {
    expect(Unit.drink.label(0), '0 drinks');
    expect(Unit.drink.label(1), '1 drink');
    expect(Unit.item.label(1500), '1,500 items');
  });
}
