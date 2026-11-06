import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/design/dial_icons.dart';

void main() {
  test('every glyph parses and stays inside its 24-unit box', () {
    for (final DialGlyph glyph in DialGlyph.values) {
      for (final String d in glyph.paths) {
        final Rect bounds = parseSvgPath(d).getBounds();
        expect(bounds.isEmpty && bounds.width == 0, isFalse, reason: d);
        expect(
          const Rect.fromLTRB(0, 0, 24, 24).inflate(0.01).contains(
                bounds.topLeft,
              ) &&
              const Rect.fromLTRB(
                0,
                0,
                24,
                24,
              ).inflate(0.01).contains(bounds.bottomRight),
          isTrue,
          reason: '${glyph.name}: $bounds',
        );
      }
    }
  });

  test('run-together arc flags split as SVG reads them', () {
    // A circle of radius 8 about (12, 12) from two half arcs.
    final Rect circle = parseSvgPath(
      'M12 4a8 8 0 110 16 8 8 0 010-16z',
    ).getBounds();
    expect(circle.left, moreOrLessEquals(4, epsilon: 0.01));
    expect(circle.right, moreOrLessEquals(20, epsilon: 0.01));
    // "00.3" is the flags 0 and 0, then .3.
    final Rect tiny = parseSvgPath('M19.4 15a1.7 1.7 0 00.3 1.8').getBounds();
    expect(tiny.bottom, moreOrLessEquals(16.8, epsilon: 0.01));
  });
}
