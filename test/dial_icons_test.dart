import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/design/dial_icons.dart';

void main() {
  test('every glyph parses and stays inside its 24-unit box', () {
    final Rect box = const Rect.fromLTRB(0, 0, 24, 24).inflate(0.01);
    for (final DialGlyph glyph in DialGlyph.values) {
      for (final String d in glyph.paths) {
        final Rect bounds = parseSvgPath(d).getBounds();
        expect(bounds.width + bounds.height, greaterThan(0), reason: d);
        expect(
          box.contains(bounds.topLeft) && box.contains(bounds.bottomRight),
          isTrue,
          reason: '${glyph.name}: $bounds',
        );
      }
    }
  });
}
