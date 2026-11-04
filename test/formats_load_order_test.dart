import 'dart:ui';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:tracker/formats.dart';

// Its own file, so its own isolate: the app loads Flutter's date data before
// it formats anything, which formats_test.dart's setUpAll does not.
void main() {
  test('regions Flutter has no date data for survive its delegates', () async {
    await GlobalMaterialLocalizations.delegate.load(const Locale('en'));

    expect(localeForFormatting(const [Locale('en', 'MY')]), 'en_MY');
    final DateTime day = DateTime(2026, 11, 4);
    expect(DateFormat.yMd('en_MY').format(day), '04/11/2026');
    expect(DateFormat.yMMMEd('en_MY').format(day), 'Wed, 4 Nov 2026');
  });
}
