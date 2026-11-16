import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/design/tokens.dart';

import 'palette_names.dart';

// The Dart tokens against what they mirror: the colours against the design
// system's tokens.json, the rest against lib/design/tokens.json.
final Map<String, dynamic> _json =
    jsonDecode(File('lib/design/tokens.json').readAsStringSync())
        as Map<String, dynamic>;

final Map<String, dynamic> _system =
    jsonDecode(
          File(
            'docs/design-system/day-dial/project/tokens.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

// The system's colours for one theme, by token name.
Map<String, Color> _systemColours(String theme) => <String, Color>{
  for (final dynamic token
      in (_system['color'] as Map<String, dynamic>)['tokens'] as List<dynamic>)
    (token as Map<String, dynamic>)['name'] as String: hexColor(
      (token['value'] as Map<String, dynamic>)[theme] as String,
    ),
};

void main() {
  test('the design system has a light and a dark theme', () {
    expect(
      <String>[
        for (final dynamic t
            in (_system['color'] as Map<String, dynamic>)['themes']
                as List<dynamic>)
          (t as Map<String, dynamic>)['id'] as String,
      ],
      <String>['light', 'dark'],
    );
  });

  for (final (String name, DialPalette palette, BeadTreatment bead) in [
    ('light', DialPalette.light, BeadTreatment.light),
    ('dark', DialPalette.dark, BeadTreatment.dark),
  ]) {
    test('the $name palette matches the design system', () {
      final Map<String, Color> system = _systemColours(name);
      final Map<String, Color> dart = paletteByName(palette);
      expect(dart.keys.toSet(), system.keys.toSet());
      for (final MapEntry<String, Color> entry in dart.entries) {
        expect(entry.value, system[entry.key], reason: '$name ${entry.key}');
      }
    });

    test('lib/design/tokens.json carries the system\'s $name colours', () {
      final Map<String, Color> system = _systemColours(name);
      final Map<String, dynamic> app =
          (_json['color'] as Map<String, dynamic>)[name]
              as Map<String, dynamic>;
      expect(system.keys, containsAll(app.keys));
      for (final MapEntry<String, dynamic> entry in app.entries) {
        expect(
          hexColor(entry.value as String),
          system[entry.key],
          reason: '$name ${entry.key}',
        );
      }
    });

    test('the $name bead treatment matches its rim and glow colours', () {
      for (int i = 0; i < 5; i++) {
        final Color rim = palette.dataRim[i];
        final Color glow = palette.dataGlow[i];
        if (bead.rimAlpha > 0) {
          expect(
            rim.withValues(alpha: 1),
            palette.dataInk[i].withValues(alpha: 1),
          );
        }
        if (bead.glowAlpha > 0) {
          expect(
            glow.withValues(alpha: 1),
            palette.data[i].withValues(alpha: 1),
          );
        }
        expect(
          rim.a,
          closeTo(bead.rimAlpha, 0.5 / 255),
          reason: 'data${i + 1}Rim',
        );
        expect(
          glow.a,
          closeTo(bead.glowAlpha, 0.5 / 255),
          reason: 'data${i + 1}Glow',
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
