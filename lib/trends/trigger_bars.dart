import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/trend_breakdowns.dart';
import 'package:tracker/data/usage_series.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/trends/trends_chart.dart';

// Each bucket's tagged entries as one bar split by trigger area, in shades of
// the habit's ink, with the chart's cursor: the arrow keys or a screen
// reader's adjust move it, as on [TrendsChart].
class TriggerBars extends StatelessWidget {
  const TriggerBars({
    super.key,
    required this.vice,
    required this.mark,
    required this.range,
    required this.shares,
    required this.cursor,
    required this.onCursor,
  });

  final Vice vice;
  final HabitMark mark;
  final UsageRange range;
  final TriggerShares shares;
  final int cursor;
  final ValueChanged<int> onCursor;

  static const double height = 72;
  static const String focusLabel = 'Trigger bars';

  // From the most tagged area, darkest, to the least.
  static double shade(int index, int count) =>
      count <= 1 ? 1 : 1 - 0.75 * index / (count - 1);

  static String percent(double share) => '${(share * 100).round()}%';

  static String summary(Vice vice, UsageRange range, TriggerShares s) {
    final int tagged = s.tagged.fold<int>(0, (int a, int b) => a + b);
    final String areas = <String>[
      for (int i = 0; i < s.areas.length; i++)
        '${triggerAreaLabel(s.areas[i])} ${percent(s.overall[i])}',
    ].join(', ');
    return 'What set off ${vice.name} over the last '
        '${formatCount(range.days)} days, by area: '
        '${formatCount(tagged)} tagged ${pluralWord(tagged, one: 'entry', other: 'entries')}. '
        '$areas. An entry tagged in several areas counts a part to each.';
  }

  static String readout(UsageRange range, TriggerShares s, int index) {
    final String date = TrendsChart.readoutLabel(
      range,
      index,
      addDays(range.end, -1),
    );
    final int tagged = s.tagged[index];
    if (tagged == 0) {
      return '$date, none tagged';
    }
    final String areas = <String>[
      for (int i = 0; i < s.areas.length; i++)
        if (s.shares[index][i] > 0)
          '${triggerAreaLabel(s.areas[i])} ${percent(s.shares[index][i])}',
    ].join(', ');
    return '$date, ${formatCount(tagged)} tagged: $areas';
  }

  @override
  Widget build(BuildContext context) {
    final DialColors colors = DialColors.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color ink = colors.habitInk(mark);
    final int n = shares.tagged.length;
    final int shown = cursor.clamp(0, max(0, n - 1));
    final VoidCallback? earlier = shown > 0 ? () => onCursor(shown - 1) : null;
    final VoidCallback? later = shown < n - 1
        ? () => onCursor(shown + 1)
        : null;

    KeyEventResult onKey(FocusNode node, KeyEvent event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        earlier?.call();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        later?.call();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    final TextStyle words = DialTypeScale.bodyS.copyWith(color: colors.muted);
    return Semantics(
      container: true,
      label: summary(vice, range, shares),
      value: readout(range, shares, shown),
      decreasedValue: earlier == null
          ? null
          : readout(range, shares, shown - 1),
      increasedValue: later == null ? null : readout(range, shares, shown + 1),
      onDecrease: earlier,
      onIncrease: later,
      excludeSemantics: true,
      child: Focus(
        debugLabel: focusLabel,
        onKeyEvent: onKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              readout(range, shares, shown),
              style: words,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: DialSpace.xs),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) =>
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (TapDownDetails d) => onCursor(
                      (d.localPosition.dx / box.maxWidth * n).floor().clamp(
                        0,
                        n - 1,
                      ),
                    ),
                    child: CustomPaint(
                      size: Size(box.maxWidth, height),
                      painter: _BarsPainter(
                        shares: shares,
                        cursor: shown,
                        ink: ink,
                        empty: colors.line,
                        cursorColor: scheme.outline,
                      ),
                    ),
                  ),
            ),
            const SizedBox(height: DialSpace.xs),
            Wrap(
              spacing: DialSpace.m,
              runSpacing: DialSpace.xxs,
              children: <Widget>[
                for (int i = 0; i < shares.areas.length; i++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: ink.withValues(
                            alpha: shade(i, shares.areas.length),
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${triggerAreaLabel(shares.areas[i])} '
                        '${percent(shares.overall[i])}',
                        style: words,
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.shares,
    required this.cursor,
    required this.ink,
    required this.empty,
    required this.cursorColor,
  });

  final TriggerShares shares;
  final int cursor;
  final Color ink;
  final Color empty;
  final Color cursorColor;

  @override
  void paint(Canvas canvas, Size size) {
    final int n = shares.tagged.length;
    if (n == 0) {
      return;
    }
    final double slot = size.width / n;
    final double gap = slot > 6 ? max(1, slot * 0.2) : 0;
    final int count = shares.areas.length;
    for (int b = 0; b < n; b++) {
      final double left = b * slot + gap / 2;
      final double width = slot - gap;
      if (shares.tagged[b] == 0) {
        canvas.drawRect(
          Rect.fromLTWH(left, size.height - 2, width, 2),
          Paint()..color = empty,
        );
        continue;
      }
      double bottom = size.height;
      for (int i = 0; i < count; i++) {
        final double h = shares.shares[b][i] * size.height;
        if (h <= 0) {
          continue;
        }
        canvas.drawRect(
          Rect.fromLTWH(left, bottom - h, width, h),
          Paint()..color = ink.withValues(alpha: TriggerBars.shade(i, count)),
        );
        bottom -= h;
      }
    }
    final double x = (cursor + 0.5) * slot;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = cursorColor
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      !identical(old.shares, shares) ||
      old.cursor != cursor ||
      old.ink != ink ||
      old.empty != empty ||
      old.cursorColor != cursorColor;
}
