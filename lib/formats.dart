import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:intl/date_symbol_data_custom.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/date_symbols.dart';
import 'package:intl/date_time_patterns.dart';
import 'package:intl/intl.dart';

const List<Locale> appLocales = [Locale('en')];

bool _dateDataLoaded = false;

// The app's localization delegates fill intl's date table before anything is
// formatted, with only Flutter's locales (no en_MY), and intl will not replace
// a filled table, so intl's other locales are added one by one.
void _loadDateData() {
  if (_dateDataLoaded) return;
  initializeDateFormatting();
  final Map<String, Map<String, String>> patterns = dateTimePatternMap();
  for (final MapEntry<String, DateSymbols>(:key, :value)
      in dateTimeSymbolMap().entries) {
    if (!DateFormat.localeExists(key)) {
      initializeDateFormattingCustom(
        locale: key,
        symbols: value,
        patterns: patterns[key],
      );
    }
  }
  _dateDataLoaded = true;
}

String get formatLocale =>
    localeForFormatting(PlatformDispatcher.instance.locales);

// English is the only language the app speaks, so the device supplies only
// the regional conventions (day order, 12 or 24 hours, digit grouping): the
// user's first English variant, else English in their region, else en.
String localeForFormatting(List<Locale> deviceLocales) {
  _loadDateData();

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

// On iOS the flag is true when 24-Hour Time is on or the region defaults to
// 24-hour, so false always means a 12-hour device. intl has no 12-hour
// skeleton, so that pattern is CLDR English's, the region choosing AM/PM.
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
