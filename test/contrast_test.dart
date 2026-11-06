import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/design/tokens.dart';

import 'palette_names.dart';

// Every colour pair the design system lists, painted with the app's palette.
// tools/contrast-check.py checks the same file against the system's
// tokens.json; the arithmetic here is the same: source-over in gamma-encoded
// sRGB, scored at the worse of the exact and the 8-bit blend, WCAG 2.2
// luminance, unrounded.

final List<dynamic> _pairs =
    (jsonDecode(
              File(
                'docs/design-system/day-dial/project/contrast-pairs.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>)['pairs']
        as List<dynamic>;

final RegExp _layer = RegExp(
  r'^(?:mix\((\w+),\s*([\d.]+)\)|(\w+)(?:@([\d.]+))?)$',
);

typedef _Rgba = ({List<double> rgb, double alpha});

_Rgba _resolve(String layer, Map<String, Color> palette) {
  final RegExpMatch? m = _layer.firstMatch(layer.trim());
  if (m == null) {
    throw FormatException('bad layer', layer);
  }
  final String name = m[1] ?? m[3]!;
  final Color c = palette[name] ?? (throw ArgumentError('no token $name'));
  final double factor = m[1] != null
      ? double.parse(m[2]!) / 100
      : (m[4] != null ? double.parse(m[4]!) : 1);
  return (rgb: <double>[c.r * 255, c.g * 255, c.b * 255], alpha: c.a * factor);
}

// Topmost first; the bottom layer must be opaque.
List<double> _flatten(
  List<String> layers,
  Map<String, Color> palette, {
  required bool rounded,
}) {
  final List<_Rgba> stack = <_Rgba>[
    for (final String l in layers) _resolve(l, palette),
  ];
  expect(stack.last.alpha, 1, reason: '${layers.last} must be opaque');
  List<double> out = stack.last.rgb;
  for (final _Rgba layer in stack.reversed.skip(1)) {
    out = <double>[
      for (int i = 0; i < 3; i++)
        layer.alpha * layer.rgb[i] + (1 - layer.alpha) * out[i],
    ];
    if (rounded) {
      out = <double>[for (final double c in out) c.roundToDouble()];
    }
  }
  return out;
}

double _luminance(List<double> rgb) {
  double linear(double c) {
    final double s = c / 255;
    return s <= 0.04045
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * linear(rgb[0]) +
      0.7152 * linear(rgb[1]) +
      0.0722 * linear(rgb[2]);
}

double _ratio(List<double> a, List<double> b) {
  final double la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

List<String> _layers(dynamic side) =>
    side is String ? <String>[side] : List<String>.from(side as List<dynamic>);

void main() {
  test('the pair file lists pairs', () {
    expect(_pairs.length, greaterThan(40));
  });

  test('a token at half its opacity is scored as the blend it paints', () {
    final Map<String, Color> palette = <String, Color>{
      'black': const Color(0xFF000000),
      'white': const Color(0xFFFFFFFF),
    };
    final List<double> grey = _flatten(
      <String>['black@0.5', 'white'],
      palette,
      rounded: true,
    );
    expect(grey, <double>[128, 128, 128]);
    expect(
      _ratio(<double>[0, 0, 0], <double>[255, 255, 255]),
      closeTo(21, 1e-9),
    );
  });

  for (final (String theme, DialPalette p) in [
    ('light', DialPalette.light),
    ('dark', DialPalette.dark),
  ]) {
    final Map<String, Color> palette = paletteByName(p);
    for (final dynamic raw in _pairs) {
      final Map<String, dynamic> pair = raw as Map<String, dynamic>;
      final List<dynamic>? themes = pair['themes'] as List<dynamic>?;
      if (themes != null && !themes.contains(theme)) {
        continue;
      }
      final bool perHabit = pair['per_habit'] == true;
      for (final int? n in perHabit ? <int>[1, 2, 3, 4, 5] : <int?>[null]) {
        List<String> sub(dynamic side) => <String>[
          for (final String l in _layers(side))
            n == null ? l : l.replaceAll('{n}', '$n'),
        ];
        final List<String> fg = sub(pair['fg']), bg = sub(pair['bg']);
        final double min = (pair['min'] as num).toDouble();
        test('$theme: ${fg.join(' over ')} on ${bg.join(' over ')} '
            'meets $min:1 (${pair['purpose']})', () {
          double worst = double.infinity;
          for (final bool rounded in <bool>[false, true]) {
            worst = math.min(
              worst,
              _ratio(
                _flatten(<String>[...fg, ...bg], palette, rounded: rounded),
                _flatten(bg, palette, rounded: rounded),
              ),
            );
          }
          expect(worst, greaterThanOrEqualTo(min), reason: pair['purpose']);
        });
      }
    }
  }
}
