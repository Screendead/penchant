import 'dart:math';

import 'package:flutter/material.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';

// A row per weekday, Monday first, of 24 hour cells, each tinted with how
// much the habit's average such day holds in that hour.
class WeekdayGrid extends StatelessWidget {
  const WeekdayGrid({super.key, required this.cells, required this.mark});

  // [weekday][hour], Monday first.
  final List<List<double>> cells;
  final HabitMark mark;

  static const double cellHeight = 11;
  static const double gap = 2;
  static const List<int> labelledHours = <int>[0, 6, 12, 18];

  @override
  Widget build(BuildContext context) {
    final DialColors colors = DialColors.of(context);
    final MaterialLocalizations l10n = MaterialLocalizations.of(context);
    final TextStyle label = DialTypeScale.dialNumeral.copyWith(
      color: colors.muted,
      fontSize: 9,
    );
    final double rows = 7 * cellHeight + 6 * gap;

    return ExcludeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: rows,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                // Material's narrow weekdays start on Sunday.
                for (int i = 1; i <= 7; i++)
                  SizedBox(
                    height: cellHeight,
                    child: Center(
                      child: Text(
                        l10n.narrowWeekdays[i % 7],
                        style: label,
                        textScaler: TextScaler.noScaling,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: CustomPaint(
              size: Size.fromHeight(rows + gap + 12),
              painter: _WeekdayGridPainter(
                cells: cells,
                fill: colors.habit(mark),
                empty: colors.line,
                label: label,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekdayGridPainter extends CustomPainter {
  _WeekdayGridPainter({
    required this.cells,
    required this.fill,
    required this.empty,
    required this.label,
  });

  final List<List<double>> cells;
  final Color fill;
  final Color empty;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    const double g = WeekdayGrid.gap;
    const double h = WeekdayGrid.cellHeight;
    final double w = (size.width - 23 * g) / 24;
    final double most = cells
        .expand((List<double> row) => row)
        .fold<double>(0, max);

    for (int day = 0; day < 7; day++) {
      for (int hour = 0; hour < 24; hour++) {
        final double v = cells[day][hour];
        final Color color = v <= 0 || most <= 0
            ? empty
            : fill.withValues(alpha: 0.2 + 0.8 * v / most);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(hour * (w + g), day * (h + g), w, h),
            const Radius.circular(2),
          ),
          Paint()..color = color,
        );
      }
    }

    final double top = 7 * h + 7 * g;
    for (final int hour in WeekdayGrid.labelledHours) {
      final TextPainter text = TextPainter(
        text: TextSpan(text: '$hour', style: label),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(hour * (w + g), top));
      text.dispose();
    }
  }

  @override
  bool shouldRepaint(_WeekdayGridPainter old) =>
      old.cells != cells ||
      old.fill != fill ||
      old.empty != empty ||
      old.label != label;
}
