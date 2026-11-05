import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/design/tokens.dart';

// The Dart tokens against the mock-up's export they mirror.
final Map<String, dynamic> _json =
    jsonDecode(File('lib/design/tokens.json').readAsStringSync())
        as Map<String, dynamic>;

// tokens.json writes #RRGGBB or #RRGGBBAA.
Color _hex(String hex) {
  final String digits = hex.substring(1);
  final int rgb = int.parse(digits.substring(0, 6), radix: 16);
  final int alpha = digits.length == 8
      ? int.parse(digits.substring(6), radix: 16)
      : 0xFF;
  return Color((alpha << 24) | rgb);
}

void main() {
  for (final (String name, DialPalette palette) in [
    ('light', DialPalette.light),
    ('dark', DialPalette.dark),
  ]) {
    test('the $name palette matches tokens.json', () {
      final Map<String, dynamic> c =
          (_json['color'] as Map<String, dynamic>)[name]
              as Map<String, dynamic>;
      final Map<String, Color> dart = <String, Color>{
        'bg': palette.bg,
        'surface': palette.surface,
        'surface2': palette.surface2,
        'text': palette.text,
        'muted': palette.muted,
        'line': palette.line,
        'accent': palette.accent,
        'onAccent': palette.onAccent,
        'danger': palette.danger,
        'dangerContainer': palette.dangerContainer,
        for (int i = 0; i < 5; i++) 'data${i + 1}': palette.data[i],
        for (int i = 0; i < 5; i++) 'data${i + 1}Ink': palette.dataInk[i],
        'spoke': palette.spoke,
        'clear': palette.clear,
        'clearInk': palette.clearInk,
        'scrim': palette.scrim,
        'wedgeInk': palette.wedgeInk,
      };
      expect(dart.keys.toSet(), c.keys.toSet());
      for (final MapEntry<String, Color> entry in dart.entries) {
        expect(
          entry.value,
          _hex(c[entry.key] as String),
          reason: '$name ${entry.key}',
        );
      }
    });
  }

  test('the type scale matches tokens.json', () {
    final Map<String, dynamic> type = _json['type'] as Map<String, dynamic>;
    final Map<String, dynamic> families =
        type['families'] as Map<String, dynamic>;
    final Map<String, TextStyle> dart = <String, TextStyle>{
      'displayXL': DialTypeScale.displayXL,
      'displayL': DialTypeScale.displayL,
      'displayM': DialTypeScale.displayM,
      'dialNumeral': DialTypeScale.dialNumeral,
      'bodyL': DialTypeScale.bodyL,
      'body': DialTypeScale.body,
      'bodyS': DialTypeScale.bodyS,
      'label': DialTypeScale.label,
      'monoXL': DialTypeScale.monoXL,
      'monoL': DialTypeScale.monoL,
      'monoM': DialTypeScale.monoM,
      'monoS': DialTypeScale.monoS,
      'dialTime': DialTypeScale.dialTime,
    };
    final Map<String, dynamic> scale = type['scale'] as Map<String, dynamic>;
    expect(dart.keys.toSet(), scale.keys.toSet());
    for (final MapEntry<String, TextStyle> entry in dart.entries) {
      final Map<String, dynamic> spec =
          scale[entry.key] as Map<String, dynamic>;
      final TextStyle style = entry.value;
      expect(style.fontFamily, families[spec['family']], reason: entry.key);
      expect(style.fontWeight!.value, spec['weight'], reason: entry.key);
      expect(style.fontSize, spec['size'], reason: entry.key);
      expect(
        style.fontSize! * style.height!,
        closeTo((spec['line'] as num).toDouble(), 1e-9),
        reason: entry.key,
      );
      expect(style.letterSpacing, spec['tracking'] ?? 0, reason: entry.key);
      expect(
        style.fontFeatures,
        contains(const FontFeature.tabularFigures()),
        reason: entry.key,
      );
    }
  });

  test('spacing, radii and durations match tokens.json', () {
    expect(<String, double>{
      'xxs': DialSpace.xxs,
      'xs': DialSpace.xs,
      's': DialSpace.s,
      'm': DialSpace.m,
      'l': DialSpace.l,
      'xl': DialSpace.xl,
      'xxl': DialSpace.xxl,
      'xxxl': DialSpace.xxxl,
      'gutter': DialSpace.gutter,
    }, _json['space']);
    expect(<String, double>{
      'card': DialRadius.card,
      'sheet': DialRadius.sheet,
      'tile': DialRadius.tile,
      'pill': DialRadius.pill,
      'input': DialRadius.input,
      'iconTile': DialRadius.iconTile,
    }, _json['radius']);

    final Map<String, dynamic> size = _json['size'] as Map<String, dynamic>;
    expect(DialSize.logButton, size['logButton']);
    expect(DialSize.circleButton, size['circleButton']);
    expect(DialSize.pillHeight, size['pillHeight']);
    expect(DialSize.chipHeight, size['chipHeight']);
    expect(DialSize.tallyRow, size['tallyRow']);
    expect(
      DialSize.dialDiameter,
      (size['dial'] as Map<String, dynamic>)['diameter'],
    );

    final Map<String, dynamic> motion = _json['motion'] as Map<String, dynamic>;
    expect(<String, int>{
      'beadTravel': DialMotion.beadTravel.inMilliseconds,
      'landingRipple': DialMotion.landingRipple.inMilliseconds,
      'tallyRoll': DialMotion.tallyRoll.inMilliseconds,
      'dayContract': DialMotion.dayContract.inMilliseconds,
      'daySweep': DialMotion.daySweep.inMilliseconds,
      'cleanDayGlow': DialMotion.cleanDayGlow.inMilliseconds,
      'fadeThrough': DialMotion.fadeThrough.inMilliseconds,
      'containerTransform': DialMotion.containerTransform.inMilliseconds,
      'chartMorph': DialMotion.chartMorph.inMilliseconds,
      'pendingFill': DialMotion.pendingFill.inMilliseconds,
      'pendingRotation': DialMotion.pendingRotation.inMilliseconds,
      'bannerDrop': DialMotion.bannerDrop.inMilliseconds,
      'fanStagger': DialMotion.fanStagger.inMilliseconds,
      'fanClose': DialMotion.fanClose.inMilliseconds,
      'holdForAmount': DialMotion.holdForAmount.inMilliseconds,
      'undoWindow': DialMotion.undoWindow.inMilliseconds,
      'reducedFade': DialMotion.reducedFade.inMilliseconds,
    }, motion['duration']);

    final Map<String, dynamic> curves =
        motion['curves'] as Map<String, dynamic>;
    expect(curves['travel'], 'Curves.easeInOutCubic');
    expect(DialMotion.travel, Curves.easeInOutCubic);
    expect(curves['exit'], 'Curves.easeInCubic');
    expect(DialMotion.exit, Curves.easeInCubic);
    expect(curves['enter'], 'Curves.easeOutCubic');
    expect(DialMotion.enter, Curves.easeOutCubic);
    expect(
      curves['landing'],
      'SpringDescription(mass: 1, stiffness: 220, damping: 22)',
    );
    expect(DialMotion.landing.mass, 1);
    expect(DialMotion.landing.stiffness, 220);
    expect(DialMotion.landing.damping, 22);
  });

  test('the bundled fonts are the families the tokens name', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    for (final String family in <String>[
      DialFonts.display,
      DialFonts.text,
      DialFonts.mono,
    ]) {
      expect(pubspec, contains('- family: $family'));
      final String file = family.replaceAll(' ', '');
      expect(File('assets/fonts/$file-Variable.ttf').existsSync(), isTrue);
    }
    expect(
      File('assets/fonts/OFL.txt').readAsStringSync(),
      contains('SIL OPEN FONT LICENSE Version 1.1'),
    );
  });
}
