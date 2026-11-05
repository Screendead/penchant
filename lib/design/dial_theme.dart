import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';

// What ColorScheme has no role for: the habit colours and their inks, the
// dial's spokes, the clear-day wash, the scrim and the bead treatment.
@immutable
class DialColors extends ThemeExtension<DialColors> {
  const DialColors({
    required this.data,
    required this.dataInk,
    required this.surface2,
    required this.muted,
    required this.line,
    required this.spoke,
    required this.clear,
    required this.clearInk,
    required this.scrim,
    required this.wedgeInk,
    required this.bead,
  });

  factory DialColors.fromPalette(DialPalette p) => DialColors(
    data: p.data,
    dataInk: p.dataInk,
    surface2: p.surface2,
    muted: p.muted,
    line: p.line,
    spoke: p.spoke,
    clear: p.clear,
    clearInk: p.clearInk,
    scrim: p.scrim,
    wedgeInk: p.wedgeInk,
    bead: p.brightness == Brightness.dark
        ? BeadTreatment.dark
        : BeadTreatment.light,
  );

  static final DialColors light = DialColors.fromPalette(DialPalette.light);
  static final DialColors dark = DialColors.fromPalette(DialPalette.dark);

  // A theme built elsewhere (a test's bare ThemeData) has no extension; it
  // gets the tokens for its brightness.
  static DialColors of(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return theme.extension<DialColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  final List<Color> data;
  final List<Color> dataInk;
  final Color surface2;
  final Color muted;
  final Color line;
  final Color spoke;
  final Color clear;
  final Color clearInk;
  final Color scrim;
  final Color wedgeInk;
  final BeadTreatment bead;

  Color habit(HabitMark mark) => data[mark.slot];

  // For text about a habit.
  Color habitInk(HabitMark mark) => dataInk[mark.slot];

  @override
  DialColors copyWith({
    List<Color>? data,
    List<Color>? dataInk,
    Color? surface2,
    Color? muted,
    Color? line,
    Color? spoke,
    Color? clear,
    Color? clearInk,
    Color? scrim,
    Color? wedgeInk,
    BeadTreatment? bead,
  }) => DialColors(
    data: data ?? this.data,
    dataInk: dataInk ?? this.dataInk,
    surface2: surface2 ?? this.surface2,
    muted: muted ?? this.muted,
    line: line ?? this.line,
    spoke: spoke ?? this.spoke,
    clear: clear ?? this.clear,
    clearInk: clearInk ?? this.clearInk,
    scrim: scrim ?? this.scrim,
    wedgeInk: wedgeInk ?? this.wedgeInk,
    bead: bead ?? this.bead,
  );

  @override
  DialColors lerp(DialColors? other, double t) {
    if (other == null) {
      return this;
    }
    List<Color> lerpAll(List<Color> a, List<Color> b) => <Color>[
      for (int i = 0; i < a.length; i++) Color.lerp(a[i], b[i], t)!,
    ];
    return DialColors(
      data: lerpAll(data, other.data),
      dataInk: lerpAll(dataInk, other.dataInk),
      surface2: Color.lerp(surface2, other.surface2, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      line: Color.lerp(line, other.line, t)!,
      spoke: Color.lerp(spoke, other.spoke, t)!,
      clear: Color.lerp(clear, other.clear, t)!,
      clearInk: Color.lerp(clearInk, other.clearInk, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      wedgeInk: Color.lerp(wedgeInk, other.wedgeInk, t)!,
      bead: BeadTreatment(
        rimWidth: lerpDouble(bead.rimWidth, other.bead.rimWidth, t)!,
        rimAlpha: lerpDouble(bead.rimAlpha, other.bead.rimAlpha, t)!,
        glowRadius: lerpDouble(bead.glowRadius, other.bead.glowRadius, t)!,
        glowBlur: lerpDouble(bead.glowBlur, other.bead.glowBlur, t)!,
        glowAlpha: lerpDouble(bead.glowAlpha, other.bead.glowAlpha, t)!,
      ),
    );
  }
}

// The type scale's roles that TextTheme has no slot for, in the theme's text
// colour. Mono styles set numbers only, with tabular figures.
@immutable
class DialType extends ThemeExtension<DialType> {
  const DialType({
    required this.displayXL,
    required this.displayL,
    required this.displayM,
    required this.dialNumeral,
    required this.monoXL,
    required this.monoL,
    required this.monoM,
    required this.monoS,
    required this.dialTime,
  });

  factory DialType.colored(Color text, Color muted) => DialType(
    displayXL: DialTypeScale.displayXL.copyWith(color: text),
    displayL: DialTypeScale.displayL.copyWith(color: text),
    displayM: DialTypeScale.displayM.copyWith(color: text),
    dialNumeral: DialTypeScale.dialNumeral.copyWith(color: muted),
    monoXL: DialTypeScale.monoXL.copyWith(color: text),
    monoL: DialTypeScale.monoL.copyWith(color: text),
    monoM: DialTypeScale.monoM.copyWith(color: text),
    monoS: DialTypeScale.monoS.copyWith(color: muted),
    dialTime: DialTypeScale.dialTime.copyWith(color: muted),
  );

  static DialType of(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return theme.extension<DialType>() ??
        DialType.colored(
          theme.colorScheme.onSurface,
          theme.colorScheme.onSurfaceVariant,
        );
  }

  final TextStyle displayXL;
  final TextStyle displayL;
  final TextStyle displayM;
  final TextStyle dialNumeral;
  final TextStyle monoXL;
  final TextStyle monoL;
  final TextStyle monoM;
  final TextStyle monoS;
  final TextStyle dialTime;

  @override
  DialType copyWith({
    TextStyle? displayXL,
    TextStyle? displayL,
    TextStyle? displayM,
    TextStyle? dialNumeral,
    TextStyle? monoXL,
    TextStyle? monoL,
    TextStyle? monoM,
    TextStyle? monoS,
    TextStyle? dialTime,
  }) => DialType(
    displayXL: displayXL ?? this.displayXL,
    displayL: displayL ?? this.displayL,
    displayM: displayM ?? this.displayM,
    dialNumeral: dialNumeral ?? this.dialNumeral,
    monoXL: monoXL ?? this.monoXL,
    monoL: monoL ?? this.monoL,
    monoM: monoM ?? this.monoM,
    monoS: monoS ?? this.monoS,
    dialTime: dialTime ?? this.dialTime,
  );

  @override
  DialType lerp(DialType? other, double t) {
    if (other == null) {
      return this;
    }
    return DialType(
      displayXL: TextStyle.lerp(displayXL, other.displayXL, t)!,
      displayL: TextStyle.lerp(displayL, other.displayL, t)!,
      displayM: TextStyle.lerp(displayM, other.displayM, t)!,
      dialNumeral: TextStyle.lerp(dialNumeral, other.dialNumeral, t)!,
      monoXL: TextStyle.lerp(monoXL, other.monoXL, t)!,
      monoL: TextStyle.lerp(monoL, other.monoL, t)!,
      monoM: TextStyle.lerp(monoM, other.monoM, t)!,
      monoS: TextStyle.lerp(monoS, other.monoS, t)!,
      dialTime: TextStyle.lerp(dialTime, other.dialTime, t)!,
    );
  }
}
