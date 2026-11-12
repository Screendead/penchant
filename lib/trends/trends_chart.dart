import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tracker/data/chart_scale.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/usage_series.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/trends/pane_fill.dart';
import 'package:tracker/widgets/bead_painter.dart';
import 'package:tracker/widgets/chart_text.dart';

// Another habit drawn over the chosen one's chart, on the same axis:
// [line] is its totals under the chart's moving average.
typedef TrendsOverlay = ({
  Vice vice,
  HabitMark mark,
  List<double> totals,
  List<double> line,
});

// A Health measure drawn under the habit's line on a scale of its own:
// [values] per bucket, null where Health has none.
typedef TrendsHealth = ({
  String name,
  String Function(double value) format,
  List<double?> values,
});

// The chart's values are money in [currency] rather than the habit's units.
typedef TrendsMoney = ({String? currency});

// One habit's totals over a range as a line, its moving average as a curve
// over a tint, and a cursor with a readout on one bucket. Dragging, the arrow
// keys or a screen reader's adjust move the cursor; tapping a day, Enter or a
// screen reader's activate hands it to [onOpenBucket].
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
    this.focusNode,
    this.fill = false,
    this.overlays = const <TrendsOverlay>[],
    this.health,
    this.money,
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
  final FocusNode? focusNode;
  // The plot takes the height a [PaneFill] gives it, rather than
  // [plotHeight]; the chart then sits under an [Expanded].
  final bool fill;
  // Each the length of [totals].
  final List<TrendsOverlay> overlays;
  // Each the length of [totals].
  final TrendsHealth? health;
  final TrendsMoney? money;

  static const String focusLabel = 'Trends chart';
  static const double plotHeight = 220;
  static const int maxYSteps = 4;
  static const double labelGap = 8;
  // fl_chart tests every spot's distance to the touch; this always picks one.
  static const double _anyDistance = 1e9;

  static String seriesName(int stepDays, {bool money = false}) =>
      '${stepDays == 1 ? 'Daily' : 'Weekly'} ${money ? 'spend' : 'total'}';

  static String amount(Vice vice, double value, TrendsMoney? money) =>
      money == null
      ? vice.units.label(value)
      : formatMoney(value, money.currency);

  static String _axisLabel(int value, TrendsMoney? money) => money == null
      ? formatCount(value)
      : formatMoney(value.toDouble(), money.currency);

  // The lowest and highest of [values] that are there, or null for none.
  static ({double low, double high})? healthSpan(List<double?> values) {
    final Iterable<double> there = values.whereType<double>();
    if (there.isEmpty) {
      return null;
    }
    return (low: there.reduce(min), high: there.reduce(max));
  }

  static String _healthSummary(TrendsHealth h) {
    final ({double low, double high})? span = healthSpan(h.values);
    return span == null
        ? ' Under it, ${h.name}: no values in this range.'
        : ' Under it, ${h.name}, from ${h.format(span.low)} to '
              '${h.format(span.high)}.';
  }

  static String averageName(int stepDays, int window) =>
      '${formatCount(window)}-${stepDays == 1 ? 'day' : 'week'} average';

  static String summary({
    required Vice vice,
    required UsageRange range,
    required List<double> totals,
    required int smoothingWindow,
    List<TrendsOverlay> overlays = const <TrendsOverlay>[],
    TrendsHealth? health,
    TrendsMoney? money,
  }) {
    final int stepDays = range.stepDays;
    final UsageStats stats = usageStats(range, totals);
    final double total = stats.total;
    final String peakDate = formatShortDay(range.bucketStart(stats.peakIndex));
    final String average = smoothingWindow > 1
        ? ' Shown with a ${averageName(stepDays, smoothingWindow)}.'
        : '';
    final String compared = overlays.isEmpty
        ? ''
        : ' Compared with ${overlays.map((TrendsOverlay o) {
            final double sum = o.totals.fold<double>(0, (a, b) => a + b);
            return '${o.vice.name}, ${o.vice.units.label(sum)} in all';
          }).join('; ')}.';

    final String under = health == null ? '' : _healthSummary(health);

    return '${seriesName(stepDays, money: money != null)}s of ${vice.name} '
        'over the last ${formatCount(range.days)} days: '
        '${amount(vice, total, money)} in all. The most was '
        '${amount(vice, totals[stats.peakIndex], money)} '
        '${stepDays == 1 ? 'on' : 'in the week of'} $peakDate.$average$compared'
        '$under';
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

  // What a screen reader says for the bucket under the cursor.
  static String readoutSpoken({
    required Vice vice,
    required UsageRange range,
    required List<double> totals,
    required List<double> smoothed,
    required int window,
    required int index,
    List<TrendsOverlay> overlays = const <TrendsOverlay>[],
    TrendsHealth? health,
    TrendsMoney? money,
  }) {
    final String date = readoutLabel(range, index, addDays(range.end, -1));
    String one(Vice v, List<double> totals, List<double> line, TrendsMoney? m) {
      final String said = amount(v, totals[index], m);
      final String average = m == null
          ? formatAverage(line[index])
          : formatMoney(line[index], m.currency);
      return window > 1 ? '$said, average $average' : said;
    }

    final double? h = health?.values[index];
    return <String>[
      '$date, ${one(vice, totals, smoothed, money)}',
      for (final TrendsOverlay o in overlays)
        '${o.vice.name} ${one(o.vice, o.totals, o.line, null)}',
      if (health != null)
        '${health.name} ${h == null ? 'none' : health.format(h)}',
    ].join('; ');
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
    final int n = totals.length;
    final int shown = cursor.clamp(0, max(0, n - 1));
    final DateTime today = addDays(range.end, -1);

    final ValueChanged<int>? open = onOpenBucket;
    final VoidCallback? earlier = shown > 0 ? () => onCursor(shown - 1) : null;
    final VoidCallback? later = shown < n - 1
        ? () => onCursor(shown + 1)
        : null;

    String spoken(int index) => readoutSpoken(
      vice: vice,
      range: range,
      totals: totals,
      smoothed: smoothed,
      window: window,
      index: index,
      overlays: overlays,
      health: health,
      money: money,
    );

    KeyEventResult onKey(FocusNode node, KeyEvent event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      final LogicalKeyboardKey key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowLeft) {
        earlier?.call();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        later?.call();
        return KeyEventResult.handled;
      }
      if (open != null &&
          event is KeyDownEvent &&
          (key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter ||
              key == LogicalKeyboardKey.space)) {
        open(shown);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    return Semantics(
      container: true,
      label: summary(
        vice: vice,
        range: range,
        totals: totals,
        smoothingWindow: window,
        overlays: overlays,
        health: health,
        money: money,
      ),
      value: spoken(shown),
      decreasedValue: earlier == null ? null : spoken(shown - 1),
      increasedValue: later == null ? null : spoken(shown + 1),
      onDecrease: earlier,
      onIncrease: later,
      onTap: open == null ? null : () => open(shown),
      excludeSemantics: true,
      child: Focus(
        focusNode: focusNode,
        debugLabel: focusLabel,
        onKeyEvent: onKey,
        child: Builder(
          builder: (BuildContext context) => DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: ShapeDecoration(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DialRadius.tile),
                side: Focus.of(context).hasPrimaryFocus
                    ? BorderSide(
                        color: scheme.primary,
                        width: 2,
                        strokeAlign: BorderSide.strokeAlignOutside,
                      )
                    : BorderSide.none,
              ),
            ),
            child: _plot(context, n, shown, today, colors, type, scheme),
          ),
        ),
      ),
    );
  }

  Widget _plotBox(Widget chart) => fill
      ? Expanded(child: PaneFillSlot(child: chart))
      : SizedBox(height: plotHeight, child: chart);

  Widget _plot(
    BuildContext context,
    int n,
    int shown,
    DateTime today,
    DialColors colors,
    DialType type,
    ColorScheme scheme,
  ) {
    final TextStyle axisStyle = type.monoS.copyWith(color: colors.muted);
    final Color ink = colors.habitInk(mark);
    final Color surface = scheme.surfaceContainerLow;
    final double dateWidth = widestDateLabel(context, axisStyle);
    final double numberHeight = chartLabelSize(context, '0', axisStyle).height;
    final double bottomTitlesHeight = max(24, numberHeight + labelGap);
    final double highest = <double>[
      totals.reduce(max),
      for (final TrendsOverlay o in overlays) ...<double>[
        o.totals.reduce(max),
        o.line.reduce(max),
      ],
    ].reduce(max);
    final int largest = max(1, (highest * 1.15).ceil());
    final ({int top, int step}) yScale = roundScale(
      largest,
      min(
        maxYSteps,
        max(
          1,
          // A filled plot is at least this tall, so the labels still fit.
          (plotHeight - bottomTitlesHeight) ~/ (numberHeight + labelGap),
        ),
      ),
    );
    final double leftTitlesWidth =
        chartLabelSize(
          context,
          _axisLabel(yScale.top, money),
          axisStyle,
        ).width +
        labelGap;
    final double minX = n == 1 ? -0.5 : 0;
    final double maxX = n == 1 ? 0.5 : (n - 1).toDouble();

    return LayoutBuilder(
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
            _plotBox(
              RangeMorph(
                shape: (days: range.days, stepDays: range.stepDays),
                totals: totals,
                smoothed: window > 1 ? smoothed : null,
                top: yScale.top.toDouble(),
                builder:
                    (
                      BuildContext context,
                      MorphFrame? morph,
                      bool tween,
                    ) => LineChart(
                      duration:
                          !tween || MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : DialMotion.chartMorph,
                      curve: DialMotion.travel,
                      LineChartData(
                        minX: minX,
                        maxX: maxX,
                        minY: 0,
                        maxY: morph?.top ?? yScale.top.toDouble(),
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
                          enabled: morph == null,
                          handleBuiltInTouches: false,
                          touchSpotThreshold: _anyDistance,
                          touchCallback:
                              (FlTouchEvent event, LineTouchResponse? r) {
                                final int? index = r?.lineBarSpots
                                    ?.where(
                                      (TouchLineBarSpot s) =>
                                          s.barIndex ==
                                          (health != null && morph == null
                                              ? 1
                                              : 0),
                                    )
                                    .firstOrNull
                                    ?.spotIndex;
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
                                    padding: const EdgeInsets.only(
                                      right: labelGap,
                                    ),
                                    child: Text(
                                      _axisLabel(value.round(), money),
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
                                  fitInside:
                                      SideTitleFitInsideData.fromTitleMeta(
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
                          // First, so under the habit's line.
                          if (health != null && morph == null)
                            _healthBar(
                              health!,
                              shown,
                              yScale.top.toDouble(),
                              scheme,
                              surface,
                            ),
                          LineChartBarData(
                            spots: morph == null
                                ? <FlSpot>[
                                    for (int i = 0; i < n; i++)
                                      FlSpot(i.toDouble(), totals[i]),
                                  ]
                                : morph.spots(morph.totals, minX, maxX),
                            color: ink,
                            barWidth: 1.5,
                            dotData: FlDotData(
                              checkToShowDot:
                                  (FlSpot spot, LineChartBarData _) =>
                                      morph == null &&
                                      (dots || spot.x == shown),
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
                              spots: morph?.smoothed == null
                                  ? <FlSpot>[
                                      for (int i = 0; i < smoothed.length; i++)
                                        FlSpot(i.toDouble(), smoothed[i]),
                                    ]
                                  : morph!.spots(morph.smoothed!, minX, maxX),
                              isCurved: true,
                              preventCurveOverShooting: true,
                              isStrokeCapRound: true,
                              color: ink,
                              barWidth: 3,
                              belowBarData: BarAreaData(
                                show: true,
                                color: colors
                                    .habit(mark)
                                    .withValues(alpha: 0.10),
                              ),
                              dotData: FlDotData(
                                checkToShowDot:
                                    (FlSpot spot, LineChartBarData _) =>
                                        morph == null && spot.x == shown,
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
                          // A morph resamples only the chosen habit's series.
                          if (morph == null)
                            for (final TrendsOverlay o in overlays)
                              _overlayBar(o, shown, colors, surface),
                        ],
                      ),
                    ),
              ),
            ),
            if (overlays.isNotEmpty || health != null) ...<Widget>[
              const SizedBox(height: DialSpace.xs),
              _legend(context, shown, colors, type),
            ],
          ],
        );
      },
    );
  }

  // Habits sharing a hue (the 1st and 6th) tell apart by their mark's style.
  static List<int>? _dashes(HabitMark mark) => switch (mark.style) {
    HabitMarkStyle.filled => null,
    HabitMarkStyle.ring => const <int>[7, 4],
    HabitMarkStyle.dotted => const <int>[2, 3],
  };

  LineChartBarData _overlayBar(
    TrendsOverlay o,
    int shown,
    DialColors colors,
    Color surface,
  ) {
    final Color ink = colors.habitInk(o.mark);
    return LineChartBarData(
      spots: <FlSpot>[
        for (int i = 0; i < o.line.length; i++) FlSpot(i.toDouble(), o.line[i]),
      ],
      isCurved: window > 1,
      preventCurveOverShooting: true,
      isStrokeCapRound: true,
      color: ink,
      barWidth: 2,
      dashArray: _dashes(o.mark),
      dotData: FlDotData(
        checkToShowDot: (FlSpot spot, LineChartBarData _) => spot.x == shown,
        getDotPainter: (FlSpot spot, double _, LineChartBarData _, int _) =>
            FlDotCirclePainter(
              radius: 3.5,
              color: surface,
              strokeWidth: 2,
              strokeColor: ink,
            ),
      ),
    );
  }

  LineChartBarData _healthBar(
    TrendsHealth h,
    int shown,
    double top,
    ColorScheme scheme,
    Color surface,
  ) {
    final ({double low, double high})? span = healthSpan(h.values);
    // Its own scale: lowest at a tenth of the plot, highest at nine tenths.
    double y(double v) => span == null || span.high == span.low
        ? top / 2
        : top * (0.1 + 0.8 * (v - span.low) / (span.high - span.low));
    final Color ink = scheme.outline;
    return LineChartBarData(
      spots: <FlSpot>[
        for (int i = 0; i < h.values.length; i++)
          if (h.values[i] case final double v)
            FlSpot(i.toDouble(), y(v))
          else
            FlSpot.nullSpot,
      ],
      isCurved: true,
      preventCurveOverShooting: true,
      color: ink.withValues(alpha: 0.7),
      barWidth: 1.5,
      dashArray: const <int>[4, 3],
      belowBarData: BarAreaData(show: true, color: ink.withValues(alpha: 0.08)),
      dotData: FlDotData(
        checkToShowDot: (FlSpot spot, LineChartBarData _) => spot.x == shown,
        getDotPainter: (FlSpot spot, double _, LineChartBarData _, int _) =>
            FlDotCirclePainter(
              radius: 3,
              color: surface,
              strokeWidth: 1.5,
              strokeColor: ink,
            ),
      ),
    );
  }

  // The value under the cursor of each line drawn, the chosen habit first.
  Widget _legend(
    BuildContext context,
    int index,
    DialColors colors,
    DialType type,
  ) {
    final TextStyle words = DialTypeScale.bodyS.copyWith(color: colors.muted);
    final TextStyle number = type.monoM.copyWith(
      fontSize: 13,
      color: Theme.of(context).colorScheme.onSurface,
    );
    Widget entry(Vice v, HabitMark m, List<double> line) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        HabitPip(mark: m, size: 8),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            v.name,
            style: words,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          window > 1 ? formatAverage(line[index]) : formatCount(line[index]),
          style: number,
        ),
      ],
    );
    final double? under = health?.values[index];

    return Wrap(
      spacing: DialSpace.m,
      runSpacing: DialSpace.xxs,
      children: <Widget>[
        entry(vice, mark, window > 1 ? smoothed : totals),
        for (final TrendsOverlay o in overlays) entry(o.vice, o.mark, o.line),
        if (health case final TrendsHealth h)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 10,
                height: 2,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  h.name,
                  style: words,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 5),
              Text(under == null ? '–' : h.format(under), style: number),
            ],
          ),
      ],
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
    final double value = totals[index];
    final TextSpan text = TextSpan(
      style: words,
      children: <InlineSpan>[
        TextSpan(text: readoutLabel(range, index, today)),
        const TextSpan(text: '  '),
        TextSpan(text: amount(vice, value, money), style: strong),
        if (window > 1) ...<InlineSpan>[
          const TextSpan(text: '  avg '),
          TextSpan(
            text: money == null
                ? formatAverage(smoothed[index])
                : formatMoney(smoothed[index], money!.currency),
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

// [values] read at [count] evenly spaced points from the first to the last,
// joining neighbours with straight lines.
List<double> resampleSeries(List<double> values, int count) {
  if (values.length == 1) {
    return List<double>.filled(count, values.single);
  }
  return <double>[
    for (int j = 0; j < count; j++)
      () {
        final double x = j * (values.length - 1) / (count - 1);
        final int i = min(x.floor(), values.length - 2);
        return values[i] + (values[i + 1] - values[i]) * (x - i);
      }(),
  ];
}

typedef ChartShape = ({int days, int stepDays});

// One frame of a morph between ranges: both series resampled to
// [RangeMorph.samples] points, part way from the old range's to the new's.
class MorphFrame {
  const MorphFrame({required this.totals, this.smoothed, required this.top});

  final List<double> totals;
  final List<double>? smoothed;
  final double top;

  List<FlSpot> spots(List<double> values, double minX, double maxX) => <FlSpot>[
    for (int j = 0; j < values.length; j++)
      FlSpot(minX + (maxX - minX) * j / (values.length - 1), values[j]),
  ];
}

// fl_chart tweens a line spot by spot, so a range with another bucket count
// would jump. On a change of range this hands [builder] both ranges' series
// resampled to one count and eased from the old to the new over
// DialMotion.chartMorph, then the new range's own series ([MorphFrame] null).
// [builder]'s chart may tween its own changes only while `tween` is true: not
// during a morph, nor on the frame that swaps the resampled series for the
// range's own, which have another spot count.
class RangeMorph extends StatefulWidget {
  const RangeMorph({
    super.key,
    required this.shape,
    required this.totals,
    required this.smoothed,
    required this.top,
    required this.builder,
  });

  // The mock-up's count.
  static const int samples = 221;

  final ChartShape shape;
  final List<double> totals;
  final List<double>? smoothed;
  final double top;
  final Widget Function(BuildContext context, MorphFrame? morph, bool tween)
  builder;

  @override
  State<RangeMorph> createState() => _RangeMorphState();
}

class _RangeMorphState extends State<RangeMorph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t =
      AnimationController(
        vsync: this,
        animationBehavior: AnimationBehavior.preserve,
        duration: DialMotion.chartMorph,
      )..addStatusListener((AnimationStatus status) {
        if (status.isCompleted) {
          setState(() {
            _from = null;
            _handoff = true;
          });
        }
      });
  MorphFrame? _from;
  bool _handoff = false;

  MorphFrame _resampled(RangeMorph w) => MorphFrame(
    totals: resampleSeries(w.totals, RangeMorph.samples),
    smoothed: w.smoothed == null
        ? null
        : resampleSeries(w.smoothed!, RangeMorph.samples),
    top: w.top,
  );

  // Where the morph from [_from] towards [target]'s series has got to.
  MorphFrame _towards(RangeMorph target) {
    final MorphFrame from = _from!;
    final MorphFrame to = _resampled(target);
    final double k = DialMotion.travel.transform(_t.value);
    List<double> mix(List<double> a, List<double> b) => <double>[
      for (int i = 0; i < a.length; i++) a[i] + (b[i] - a[i]) * k,
    ];
    return MorphFrame(
      totals: mix(from.totals, to.totals),
      smoothed: to.smoothed == null
          ? null
          : mix(from.smoothed ?? from.totals, to.smoothed!),
      top: from.top + (to.top - from.top) * k,
    );
  }

  @override
  void didUpdateWidget(RangeMorph old) {
    super.didUpdateWidget(old);
    if (old.shape == widget.shape || MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    // A morph caught part way starts again from where it is.
    _from = _from == null ? _resampled(old) : _towards(old);
    _t.forward(from: 0);
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Cleared only once the swap has been built, whatever rebuilds first.
    if (_handoff) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handoff = false);
    }
    return AnimatedBuilder(
      animation: _t,
      builder: (BuildContext context, _) => widget.builder(
        context,
        _from == null ? null : _towards(widget),
        _from == null && !_handoff,
      ),
    );
  }
}
