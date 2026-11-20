import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/formats.dart';

void main() {
  setUpAll(() => formatLocale);

  group('money', () {
    test('a new price starts in the device region currency', () {
      expect(deviceCurrency(const <Locale>[Locale('en', 'GB')]), 'GBP');
      expect(deviceCurrency(const <Locale>[Locale('de', 'DE')]), 'EUR');
      expect(deviceCurrency(const <Locale>[Locale('ja', 'JP')]), 'JPY');
    });
  });

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

  test('the test device formats as en_US', () {
    expect(formatLocale, 'en_US');
  });
}
