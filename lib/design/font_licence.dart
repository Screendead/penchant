import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tracker/design/tokens.dart';

// The OFL asks every copy of the fonts to carry the licence; this lists it on
// the licence page behind Settings > About, beside the packages' own.
void registerFontLicence() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const <String>[
      DialFonts.display,
      DialFonts.text,
      DialFonts.mono,
    ], await rootBundle.loadString(fontLicenceAsset));
  });
}

const String fontLicenceAsset = 'assets/fonts/OFL.txt';
