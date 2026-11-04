import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

const List<Locale> appLocales = [Locale('en')];

bool _dateSymbolsLoaded = false;

// English is the only language the app speaks, so the device supplies only
// the regional conventions (day order, 12 or 24 hours, digit grouping): the
// user's first English variant, else English in their region, else en.
String get formatLocale {
  if (!_dateSymbolsLoaded) {
    // Synchronous despite the Future: the data is compiled in.
    initializeDateFormatting();
    _dateSymbolsLoaded = true;
  }
  final List<Locale> locales = PlatformDispatcher.instance.locales;
  final Iterable<String> candidates = [
    for (final Locale locale in locales)
      if (locale.languageCode == 'en' && locale.countryCode != null)
        'en_${locale.countryCode}',
    if (locales.isNotEmpty && locales.first.countryCode != null)
      'en_${locales.first.countryCode}',
  ];

  return candidates.firstWhere(DateFormat.localeExists, orElse: () => 'en');
}

String formatDay(DateTime day) =>
    DateFormat.yMMMMEEEEd(formatLocale).format(day);

String formatShortDay(DateTime day) =>
    DateFormat.MMMd(formatLocale).format(day);

String formatDayAndTime(DateTime moment) =>
    DateFormat.yMMMEd(formatLocale).add_jm().format(moment);

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
