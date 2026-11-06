import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tracker/data/chart_scale.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/usage_series.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/widgets/chart_text.dart';

// One habit's totals over a range as a line, its moving average as a curve
// over a tint, and a cursor with a readout on one bucket. Dragging moves the
// cursor; tapping a day hands it to [onOpenBucket].
class TrendsChart extends StatelessWidget {
  const TrendsChart({
    super.key,
    required this.vice,
    required this.mark,
    required this.range,
    required this.totals,
    required this.smoothed,
    required this.window,
    required this.cursor,
    required this.onCursor,
    this.onOpenBucket,
  });

  final Vice vice;
  final HabitMark mark;
  final UsageRange range;
  final List<double> totals;
  final List<double> smoothed;
  final int window;
  // The bucket the readout describes.
  final int cursor;
  final ValueChanged<int> onCursor;
  final ValueChanged<int>? onOpenBucket;

  static const double plotHeight = 220;
  static const int maxYSteps = 4;
  static const double labelGap = 8;
  // fl_chart tests every spot's distance to the touch; this always picks one.
  static const double _anyDistance = 1e9;

  static String seriesName(int stepDays) =>
      stepDays == 1 ? 'Daily total' : 'Weekly total';

  static String averageName(int stepDays, int window) =>
      '${formatCount(window)}-${stepDays == 1 ? 'day' : 'week'} average';

  static String summary({
    required Vice vice,
    required UsageRange range,
    required List<double> totals,
    required int smoothingWindow,
  }) {
    final int stepDays = range.stepDays;
    final UsageStats stats = usageStats(range, totals);
    final int total = stats.total.round();
    final String peakDate = formatShortDay(range.bucketStart(stats.peakIndex));
    final String average = smoothingWindow > 1
        ? ' Shown with a ${averageName(stepDays, smoothingWindow)}.'
        : '';

    return '${seriesName(stepDays)}s of ${vice.name} over the last '
        '${formatCount(range.days)} days: ${vice.unit.label(total)} in all. The most was '
        '${vice.unit.label(totals[stats.peakIndex].round())} '
        '${stepDays == 1 ? 'on' : 'in the week of'} $peakDate.$average';
  }

  // The date under bucket [index], and in the readout.
  static String bucketLabel(UsageRange range, int index, DateTime today) {
    final DateTime start = range.bucketStart(index);
    if (range.stepDays == 1) {
      return start == today ? 'Today' : formatShortDay(start);
    }
    return formatShortDay(start);
  }

  static String readoutLabel(UsageRange range, int index, DateTime today) {
    if (range.stepDays == 1) {
      final DateTime day = range.bucketStart(index);
      return day == today
          ? 'Today'
          : DateFormat.MMMEd(formatLocale).format(day);
    }
    final DateTime start = range.bucketStart(index);
    final DateTime next = index + 1 < range.bucketCount
        ? range.bucketStart(index + 1)
        : range.end;
    return '${formatShortDay(start)}–${formatShortDay(addDays(next, -1))}';
  }

  // The widest date the axis can print: every month's 28th, and Today.
  static double widestDateLabel(BuildContext context, TextStyle style) {
    double widest = chartLabelSize(context, 'Today', style).width;
    for (int month = 1; month <= 12; month++) {
      widest = max(
        widest,
        chartLabelSize(
          context,
          formatShortDay(DateTime(2000, month, 28)),
          style,
        ).width,
      );
    }
    return widest;
  }

  @override
  Widget build(BuildContext context) {
    final DialColors colors = DialColors.of(context);
    final DialType type = DialType.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextStyle axisStyle = type.monoS.copyWith(color: colors.muted);
    final Color ink = colors.habitInk(mark);
    final Color surface = scheme.surfaceContainerLow;
    final int n = totals.length;
    final int shown = cursor.clamp(0, max(0, n - 1));
    final DateTime today = addDays(range.end, -1);

    final double dateWidth = widestDateLabel(context, axisStyle);
    final double numberHeight = chartLabelSize(context, '0', axisStyle).height;
    final double bottomTitlesHeight = max(24, numberHeight + labelGap);
    final int largest = max(1, (totals.reduce(max) * 1.15).ceil());
    final ({int top, int step}) yScale = roundScale(
      largest,
      min(
        maxYSteps,
        max(1, (plotHeight - bottomTitlesHeight) ~/ (numberHeight + labelGap)),
      ),
    );
    final double leftTitlesWidth =
        chartLabelSize(context, formatCount(yScale.top), axisStyle).width +
        labelGap;
    final double minX = n == 1 ? -0.5 : 0;
    final double maxX = n == 1 ? 0.5 : (n - 1).toDouble();

    return Semantics(
      container: true,
      label: summary(
        vice: vice,
        range: range,
        totals: totals,
        smoothingWindow: window,
      ),
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double width = constraints.maxWidth;
          final double plotWidth = max(1, width - leftTitlesWidth);
          final Set<int> labelled = labelIndices(
            n,
            labelsThatFit(plotWidth, dateWidth),
          ).toSet();
          final double cursorX =
              leftTitlesWidth + (shown - minX) / (maxX - minX) * plotWidth;
          final bool dots = n <= 31;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _readout(context, today, shown, colors, type, cursorX),
              const SizedBox(height: DialSpace.xs),
              SizedBox(
                height: plotHeight,
                child: LineChart(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : DialMotion.chartMorph,
                  curve: DialMotion.travel,
                  LineChartData(
                    minX: minX,
                    maxX: maxX,
                    minY: 0,
                    maxY: yScale.top.toDouble(),
                    // A curve through a small value between steep falls can
                    // still swing below the axis.
                    clipData: const FlClipData(
                      top: false,
                      bottom: true,
                      left: false,
                      right: false,
                    ),
                    gridData: FlGridData(
                      drawVerticalLine: false,
                      horizontalInterval: yScale.step.toDouble(),
                      getDrawingHorizontalLine: (double value) =>
                          FlLine(color: colors.line, strokeWidth: 1),
                    ),
                    borderData: FlBorderData(show: false),
                    extraLinesData: ExtraLinesData(
                      verticalLines: <VerticalLine>[
                        VerticalLine(
                          x: shown.toDouble(),
                          color: scheme.outline,
                          strokeWidth: 1,
                        ),
                      ],
                    ),
                    lineTouchData: LineTouchData(
                      handleBuiltInTouches: false,
                      touchSpotThreshold: _anyDistance,
                      touchCallback:
                          (FlTouchEvent event, LineTouchResponse? r) {
                            final int? index =
                                r?.lineBarSpots?.firstOrNull?.spotIndex;
                            if (index == null) {
                              return;
                            }
                            if (event is FlTapUpEvent) {
                              onCursor(index);
                              onOpenBucket?.call(index);
                            } else if (event.isInterestedForInteractions) {
                              onCursor(index);
                            }
                          },
                    ),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(),
                      rightTitles: const AxisTitles(),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: leftTitlesWidth,
                          interval: yScale.step.toDouble(),
                          getTitlesWidget: (double value, TitleMeta meta) =>
                              Padding(
                                padding: const EdgeInsets.only(right: labelGap),
                                child: Text(
                                  formatCount(value.round()),
                                  style: axisStyle,
                                  textAlign: TextAlign.end,
                                ),
                              ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: bottomTitlesHeight,
                          interval: 1,
                          getTitlesWidget: (double value, TitleMeta meta) {
                            final int index = value.round();
                            if (value != index.toDouble() ||
                                !labelled.contains(index)) {
                              return const SizedBox.shrink();
                            }
                            return SideTitleWidget(
                              meta: meta,
                              fitInside: SideTitleFitInsideData.fromTitleMeta(
                                meta,
                                distanceFromEdge: 0,
                              ),
                              child: Text(
                                bucketLabel(range, index, today),
                                style: axisStyle,
                                maxLines: 1,
                                softWrap: false,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    lineBarsData: <LineChartBarData>[
                      LineChartBarData(
                        spots: <FlSpot>[
                          for (int i = 0; i < n; i++)
                            FlSpot(i.toDouble(), totals[i]),
                        ],
                        color: ink,
                        barWidth: 1.5,
                        dotData: FlDotData(
                          checkToShowDot: (FlSpot spot, LineChartBarData _) =>
                              dots || spot.x == shown,
                          getDotPainter:
                              (
                                FlSpot spot,
                                double _,
                                LineChartBarData _,
                                int index,
                              ) => index == shown
                              ? FlDotCirclePainter(
                                  radius: 5,
                                  color: ink,
                                  strokeWidth: 2.5,
                                  strokeColor: surface,
                                )
                              : FlDotCirclePainter(
                                  radius: n <= 7 ? 3.5 : 2.4,
                                  color: ink,
                                  strokeWidth: 0,
                                ),
                        ),
                      ),
                      if (window > 1)
                        LineChartBarData(
                          spots: <FlSpot>[
                            for (int i = 0; i < smoothed.length; i++)
                              FlSpot(i.toDouble(), smoothed[i]),
                          ],
                          isCurved: true,
                          preventCurveOverShooting: true,
                          isStrokeCapRound: true,
                          color: ink,
                          barWidth: 3,
                          belowBarData: BarAreaData(
                            show: true,
                            color: colors.habit(mark).withValues(alpha: 0.10),
                          ),
                          dotData: FlDotData(
                            checkToShowDot: (FlSpot spot, LineChartBarData _) =>
                                spot.x == shown,
                            getDotPainter:
                                (
                                  FlSpot spot,
                                  double _,
                                  LineChartBarData _,
                                  int _,
                                ) => FlDotCirclePainter(
                                  radius: 4.5,
                                  color: surface,
                                  strokeWidth: 2.5,
                                  strokeColor: ink,
                                ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _readout(
    BuildContext context,
    DateTime today,
    int index,
    DialColors colors,
    DialType type,
    double x,
  ) {
    final TextStyle words = DialTypeScale.bodyS.copyWith(color: colors.muted);
    final TextStyle strong = DialTypeScale.label.copyWith(
      fontSize: 13,
      color: Theme.of(context).colorScheme.onSurface,
    );
    final int value = totals[index].round();
    final TextSpan text = TextSpan(
      style: words,
      children: <InlineSpan>[
        TextSpan(text: readoutLabel(range, index, today)),
        const TextSpan(text: '  '),
        TextSpan(text: vice.unit.label(value), style: strong),
        if (window > 1) ...<InlineSpan>[
          const TextSpan(text: '  avg '),
          TextSpan(
            text: formatAverage(smoothed[index]),
            style: type.monoM.copyWith(fontSize: 13),
          ),
        ],
      ],
    );
    const double sides = 11;

    return _Readout(
      x: x,
      width: chartSpanSize(context, text).width + 2 * sides + 1,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: colors.surface2,
          shape: const StadiumBorder(),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: sides, vertical: 5),
          child: Text.rich(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

// Lays its child out at [width], centred on [x] and kept inside the row.
class _Readout extends StatelessWidget {
  const _Readout({required this.x, required this.width, required this.child});

  final double x;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final double row = constraints.maxWidth;
      final double w = min(width, row);
      return Padding(
        padding: EdgeInsets.only(left: (x - w / 2).clamp(0, row - w)),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: SizedBox(width: w, child: child),
        ),
      );
    },
  );
}
