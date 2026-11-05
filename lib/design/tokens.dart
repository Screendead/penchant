import 'dart:ui';

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

// The Day Dial design tokens, mirrored from lib/design/tokens.json (the
// mock-up's export); test/design_tokens_test.dart holds the two in step.

class DialPalette {
  const DialPalette({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.text,
    required this.muted,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.danger,
    required this.dangerContainer,
    required this.data,
    required this.dataInk,
    required this.spoke,
    required this.clear,
    required this.clearInk,
    required this.scrim,
    required this.wedgeInk,
  });

  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color text;
  final Color muted;
  final Color line;
  final Color accent;
  final Color onAccent;
  final Color danger;
  final Color dangerContainer;
  // The five habit colours, data1 to data5, and the text colour for each.
  final List<Color> data;
  final List<Color> dataInk;
  final Color spoke;
  final Color clear;
  final Color clearInk;
  final Color scrim;
  final Color wedgeInk;

  static DialPalette of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  static const DialPalette light = DialPalette(
    brightness: Brightness.light,
    bg: Color(0xFFF6F4EF),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFEFECE5),
    text: Color(0xFF1D1C1A),
    muted: Color(0xFF635E56),
    line: Color(0x1A1D1C1A),
    accent: Color(0xFF1D1C1A),
    onAccent: Color(0xFFF6F4EF),
    danger: Color(0xFFB42A37),
    dangerContainer: Color(0xFFF8E4E2),
    data: <Color>[
      Color(0xFFFFB347),
      Color(0xFFFF7A59),
      Color(0xFFE8505B),
      Color(0xFF9B5DE5),
      Color(0xFF4D96FF),
    ],
    dataInk: <Color>[
      Color(0xFF8F5600),
      Color(0xFFB03E1C),
      Color(0xFFB42A37),
      Color(0xFF6A31B5),
      Color(0xFF1D5FC2),
    ],
    spoke: Color(0x731D1C1A),
    clear: Color(0xFFE3EFE4),
    clearInk: Color(0xFF276B43),
    scrim: Color(0x331D1C1A),
    wedgeInk: Color(0xFF120F0C),
  );

  static const DialPalette dark = DialPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF151412),
    surface: Color(0xFF1F1D1B),
    surface2: Color(0xFF2A2825),
    text: Color(0xFFF3F0EA),
    muted: Color(0xFFA39E94),
    line: Color(0x1FF3F0EA),
    accent: Color(0xFFF3F0EA),
    onAccent: Color(0xFF1D1C1A),
    danger: Color(0xFFFF8A8F),
    dangerContainer: Color(0xFF3A1D1E),
    data: <Color>[
      Color(0xFFFFB347),
      Color(0xFFFF7A59),
      Color(0xFFE8505B),
      Color(0xFF9B5DE5),
      Color(0xFF4D96FF),
    ],
    dataInk: <Color>[
      Color(0xFFFFB347),
      Color(0xFFFF7A59),
      Color(0xFFF0737C),
      Color(0xFFB48AF0),
      Color(0xFF4D96FF),
    ],
    spoke: Color(0x80F3F0EA),
    clear: Color(0xFF15241B),
    clearInk: Color(0xFF9ED8B0),
    scrim: Color(0xA60A0908),
    wedgeInk: Color(0xFF120F0C),
  );
}

// The bead treatment of tokens.json: an inner rim in the habit's ink in light,
// a glow of the habit's own colour in dark.
class BeadTreatment {
  const BeadTreatment({
    required this.rimWidth,
    required this.rimAlpha,
    required this.glowRadius,
    required this.glowBlur,
    required this.glowAlpha,
  });

  final double rimWidth;
  final double rimAlpha;
  final double glowRadius;
  final double glowBlur;
  final double glowAlpha;

  static const BeadTreatment light = BeadTreatment(
    rimWidth: 1.25,
    rimAlpha: 0.85,
    glowRadius: 0,
    glowBlur: 0,
    glowAlpha: 0,
  );

  static const BeadTreatment dark = BeadTreatment(
    rimWidth: 0,
    rimAlpha: 0,
    glowRadius: 8,
    glowBlur: 6,
    glowAlpha: 0.35,
  );
}

class DialFonts {
  static const String display = 'Red Hat Display';
  static const String text = 'Red Hat Text';
  static const String mono = 'Red Hat Mono';

  static const List<FontFeature> tabular = <FontFeature>[
    FontFeature.tabularFigures(),
  ];
}

// The type scale. Styles carry no colour, so they take the ambient one.
class DialTypeScale {
  static TextStyle _style(
    String family,
    FontWeight weight,
    double size,
    double line, {
    double tracking = 0,
  }) => TextStyle(
    fontFamily: family,
    fontWeight: weight,
    fontSize: size,
    height: line / size,
    letterSpacing: tracking,
    fontFeatures: DialFonts.tabular,
  );

  static final TextStyle displayXL = _style(
    DialFonts.display,
    FontWeight.w900,
    34,
    40,
    tracking: -0.5,
  );
  static final TextStyle displayL = _style(
    DialFonts.display,
    FontWeight.w900,
    26,
    32,
    tracking: -0.3,
  );
  static final TextStyle displayM = _style(
    DialFonts.display,
    FontWeight.w700,
    17,
    22,
  );
  static final TextStyle dialNumeral = _style(
    DialFonts.display,
    FontWeight.w700,
    12,
    12,
    tracking: 0.6,
  );
  static final TextStyle bodyL = _style(
    DialFonts.text,
    FontWeight.w500,
    16,
    22,
  );
  static final TextStyle body = _style(DialFonts.text, FontWeight.w400, 15, 21);
  static final TextStyle bodyS = _style(
    DialFonts.text,
    FontWeight.w400,
    13,
    18,
  );
  static final TextStyle label = _style(
    DialFonts.text,
    FontWeight.w600,
    15,
    20,
  );
  static final TextStyle monoXL = _style(
    DialFonts.mono,
    FontWeight.w500,
    40,
    44,
  );
  static final TextStyle monoL = _style(
    DialFonts.mono,
    FontWeight.w500,
    22,
    26,
  );
  static final TextStyle monoM = _style(
    DialFonts.mono,
    FontWeight.w500,
    15,
    20,
  );
  static final TextStyle monoS = _style(
    DialFonts.mono,
    FontWeight.w500,
    10,
    12,
  );
  static final TextStyle dialTime = _style(
    DialFonts.mono,
    FontWeight.w500,
    11,
    11,
  );
}

class DialSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double s = 12;
  static const double m = 16;
  static const double l = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;
  static const double gutter = 20;
}

class DialRadius {
  static const double card = 24;
  static const double sheet = 32;
  static const double tile = 18;
  static const double pill = 999;
  static const double input = 999;
  static const double iconTile = 22;
}

class DialSize {
  static const double logButton = 64;
  static const double circleButton = 40;
  static const double pillHeight = 52;
  static const double chipHeight = 34;
  static const double tallyRow = 36;
  static const double tallyPlus = 32;
  static const double minTapTarget = 44;
  static const double dialDiameter = 320;
}

class DialMotion {
  static const Duration beadTravel = Duration(milliseconds: 520);
  static const Duration landingRipple = Duration(milliseconds: 300);
  static const Duration tallyRoll = Duration(milliseconds: 300);
  static const Duration dayContract = Duration(milliseconds: 200);
  static const Duration daySweep = Duration(milliseconds: 600);
  static const Duration cleanDayGlow = Duration(milliseconds: 600);
  static const Duration fadeThrough = Duration(milliseconds: 320);
  static const Duration containerTransform = Duration(milliseconds: 450);
  static const Duration chartMorph = Duration(milliseconds: 450);
  static const Duration pendingFill = Duration(milliseconds: 240);
  static const Duration pendingRotation = Duration(milliseconds: 2000);
  static const Duration bannerDrop = Duration(milliseconds: 260);
  static const Duration fanStagger = Duration(milliseconds: 30);
  static const Duration fanClose = Duration(milliseconds: 160);
  static const Duration holdForAmount = Duration(milliseconds: 400);
  static const Duration undoWindow = Duration(milliseconds: 8000);
  static const Duration reducedFade = Duration(milliseconds: 150);

  static const Curve travel = Curves.easeInOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve enter = Curves.easeOutCubic;
  static const SpringDescription landing = SpringDescription(
    mass: 1,
    stiffness: 220,
    damping: 22,
  );
  static const SpringDescription sheetSnap = landing;
}
