import 'package:flutter/painting.dart';
import 'package:tracker/design/tokens.dart';

// The palette under the design system's token names.
Map<String, Color> paletteByName(DialPalette p) => <String, Color>{
  'bg': p.bg,
  'surface': p.surface,
  'surface2': p.surface2,
  'text': p.text,
  'muted': p.muted,
  'line': p.line,
  'outline': p.outline,
  'accent': p.accent,
  'onAccent': p.onAccent,
  'danger': p.danger,
  'dangerContainer': p.dangerContainer,
  for (int i = 0; i < 5; i++) 'data${i + 1}': p.data[i],
  for (int i = 0; i < 5; i++) 'data${i + 1}Ink': p.dataInk[i],
  for (int i = 0; i < 5; i++) 'data${i + 1}Rim': p.dataRim[i],
  for (int i = 0; i < 5; i++) 'data${i + 1}Glow': p.dataGlow[i],
  'spoke': p.spoke,
  'clear': p.clear,
  'clearInk': p.clearInk,
  'scrim': p.scrim,
  'wedgeInk': p.wedgeInk,
};

// tokens.json writes #RRGGBB or #RRGGBBAA.
Color hexColor(String hex) {
  final String digits = hex.substring(1);
  final int rgb = int.parse(digits.substring(0, 6), radix: 16);
  final int alpha = digits.length == 8
      ? int.parse(digits.substring(6), radix: 16)
      : 0xFF;
  return Color((alpha << 24) | rgb);
}
