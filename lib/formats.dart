import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

const List<Locale> appLocales = [Locale('en')];

bool _dateSymbolsLoaded = false;

String get formatLocale {
  if (!_dateSymbolsLoaded) {
    // Synchronous despite the Future: the data is compiled in.
    initializeDateFormatting();
    _dateSymbolsLoaded = true;
  }

  return localeForFormatting(PlatformDispatcher.instance.locales);
}

// English is the only language the app speaks, so the device supplies only
// the regional conventions (day order, 12 or 24 hours, digit grouping): the
// user's first English variant, else English in their region, else en.
// Call through [formatLocale], which loads the data this checks against.
String localeForFormatting(List<Locale> deviceLocales) {
  final Iterable<String> candidates = [
    for (final Locale locale in deviceLocales)
      if (locale.languageCode == 'en' && locale.countryCode != null)
        'en_${locale.countryCode}',
    if (deviceLocales.isNotEmpty && deviceLocales.first.countryCode != null)
      'en_${deviceLocales.first.countryCode}',
  ];

  return candidates.firstWhere(DateFormat.localeExists, orElse: () => 'en');
}

String formatDay(DateTime day) =>
    DateFormat.yMMMMEEEEd(formatLocale).format(day);

String formatShortDay(DateTime day) =>
    DateFormat.MMMd(formatLocale).format(day);

// On iOS and macOS the flag is the device's effective clock, 24-Hour Time
// setting included, so false means 12-hour time even where the region's
// default is 24-hour. intl has no 12-hour skeleton, so that pattern is
// CLDR English's, with the region still choosing the AM/PM words.
String formatDayAndTime(
  DateTime moment, {
  required bool alwaysUse24HourFormat,
}) {
  final DateFormat day = DateFormat.yMMMEd(formatLocale);

  return (alwaysUse24HourFormat ? day.add_Hm() : day.addPattern('h:mm\u202fa'))
      .format(moment);
}

// Typed by hand and parsed back with the same instance, so it stays numeric
// and 24-hour: a 12-hour pattern puts a narrow no-break space before AM/PM.
DateFormat get entryDateFormat => DateFormat.yMd(formatLocale).add_Hms();

String formatCount(num count) =>
    NumberFormat.decimalPattern(formatLocale).format(count);

// The words are English, so English plural rules pick them whatever the
// region: under fr's rules 0 would take the singular.
String pluralWord(int count, {required String one, required String other}) =>
    Intl.plural(count, one: one, other: other, locale: 'en');

String relativeDay(int daysAgo) => switch (daysAgo) {
  0 => 'Today',
  1 => 'Yesterday',
  _ =>
    '${formatCount(daysAgo)} ${pluralWord(daysAgo, one: 'day', other: 'days')} ago',
};
