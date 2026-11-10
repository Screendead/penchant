import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/widgets/bead_painter.dart';

class _Canvas extends Fake implements Canvas {
  final List<({Path path, PaintingStyle style})> paths =
      <({Path path, PaintingStyle style})>[];

  @override
  void save() {}

  @override
  void restore() {}

  @override
  void clipPath(Path path, {bool doAntiAlias = true}) {}

  @override
  void drawPath(Path path, Paint paint) =>
      paths.add((path: path, style: paint.style));
}

void main() {
  final Path shape = Path()..addRect(const Rect.fromLTWH(0, 0, 60, 12));

  test('a share holding unsynced entries is hollow with a dashed rim', () {
    final _Canvas synced = _Canvas();
    paintHabitBand(synced, shape, const HabitMark(0), DialColors.light);
    expect(
      synced.paths.where((p) => p.style == PaintingStyle.fill),
      isNotEmpty,
    );

    final _Canvas pending = _Canvas();
    paintHabitBand(
      pending,
      shape,
      const HabitMark(0),
      DialColors.light,
      pending: true,
    );
    expect(pending.paths, hasLength(1));
    expect(pending.paths.single.style, PaintingStyle.stroke);
    final double drawn = pending.paths.single.path.computeMetrics().fold(
      0,
      (double sum, m) => sum + m.length,
    );
    final double rim = shape.computeMetrics().fold(
      0,
      (double sum, m) => sum + m.length,
    );
    expect(drawn, inExclusiveRange(0, rim));
  });
}
