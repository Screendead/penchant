import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/chart_scale.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/chart_text.dart';
import 'package:tracker/widgets/clean_day.dart';
import 'package:tracker/widgets/info_box.dart';

class ViceChart extends ConsumerWidget {
  const ViceChart({super.key, required this.selectedDate});

  final DateTime selectedDate;

  static const int minimumRadarAxes = 3;
  static const int maximumRadarRings = 5;
  static const double barWidth = 48;
  static const double titleGap = 8;
  static const double radarTitleOffset = 0.2;
  static const int barTitleLines = 2;

  static String total(Vice vice, int quantity) =>
      '${vice.name}: ${vice.unit.label(quantity)}';

  static String summary(DateTime day, List<Vice> vices, List<int> quantities) {
    final String totals = [
      for (int i = 0; i < vices.length; i++) total(vices[i], quantities[i]),
    ].join('; ');

    return 'Totals for ${formatDay(day)}. $totals';
  }

  // The outermost ring's value and the spacing between rings.
  static ({int top, int step}) radarScale(int largest) =>
      roundScale(largest, maximumRadarRings);

  static String _suffix(Vice vice, int quantity) =>
      ' (${vice.unit.label(quantity)})';

  static TextStyle _titleStyle(ThemeData theme) =>
      TextStyle(color: theme.colorScheme.secondary, fontSize: 14);

  static List<({String text, bool complete})> _barTitles(
    BuildContext context,
    TextStyle style,
    double width,
    List<Vice> vices,
    List<int> quantities,
  ) {
    final double titleWidth =
        barTitleWidth(width, vices.length, barWidth) - titleGap;
    bool fits(String text) => chartLabelWraps(
      context,
      text,
      style,
      maxWidth: titleWidth,
      maxLines: barTitleLines,
    );

    return [
      for (int i = 0; i < vices.length; i++)
        if (fits('${vices[i].name}${_suffix(vices[i], quantities[i])}'))
          (
            text: '${vices[i].name}${_suffix(vices[i], quantities[i])}',
            complete: true,
          )
        else
          (text: vices[i].name, complete: false),
    ];
  }

  // fl_chart draws each radar title up to a full line beyond its rings
  // (0.96 of the half side plus the title's height), outside the chart's box.
  static EdgeInsets _radarInset(BuildContext context, TextStyle style) =>
      EdgeInsets.all(chartLabelSize(context, 'Ag', style).height);

  static List<({String text, bool complete})> _radarTitles(
    BuildContext context,
    TextStyle style,
    Size size,
    List<Vice> vices,
    List<int> quantities,
  ) {
    final double titleWidth =
        radarTitleWidth(size, vices.length, radarTitleOffset) - titleGap;

    return [
      for (int i = 0; i < vices.length; i++)
        fitChartLabel(
          context,
          name: vices[i].name,
          suffix: _suffix(vices[i], quantities[i]),
          style: style,
          maxWidth: titleWidth,
        ),
    ];
  }

  Widget _key(
    TextStyle style,
    double maxHeight,
    List<Vice> vices,
    List<int> quantities,
  ) => ConstrainedBox(
    constraints: BoxConstraints(maxHeight: maxHeight),
    child: SingleChildScrollView(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 16,
        runSpacing: 4,
        children: [
          for (int i = 0; i < vices.length; i++)
            Text(
              total(vices[i], quantities[i]),
              textAlign: TextAlign.center,
              style: style,
            ),
        ],
      ),
    ),
  );

  Widget _bars(
    BuildContext context,
    ThemeData theme,
    List<({String text, bool complete})> titles,
    List<int> quantities,
  ) {
    final TextStyle titleStyle = _titleStyle(theme);
    final double lineHeight = chartLabelSize(context, 'Ag', titleStyle).height;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double titleWidth =
            barTitleWidth(constraints.maxWidth, titles.length, barWidth) -
            titleGap;

        return BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceEvenly,
            minY: 0,
            maxY: quantities.reduce(max) * 1.15,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(enabled: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              leftTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: max(48, barTitleLines * lineHeight + 8),
                  getTitlesWidget: (double value, TitleMeta meta) {
                    return SideTitleWidget(
                      meta: meta,
                      child: SizedBox(
                        width: titleWidth,
                        child: Text(
                          titles[value.toInt()].text,
                          maxLines: barTitleLines,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: titleStyle,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            barGroups: [
              for (int i = 0; i < quantities.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: quantities[i].toDouble(),
                      width: barWidth,
                      color: theme.colorScheme.primary,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(6),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          duration: const Duration(milliseconds: 600),
          curve: Curves.fastOutSlowIn,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Vice>> vicesValue = ref.watch(
      unarchivedViceListProvider,
    );
    final AsyncValue<List<ViceActivity>> activitiesValue = ref.watch(
      viceActivityDayProvider(selectedDate),
    );

    final List<Vice>? vices = vicesValue.value;

    // With no vices there is nothing to chart, whatever the day's query did.
    if (!vicesValue.hasError && vices != null && vices.isEmpty) {
      return const InfoBox(
        message: 'No habits yet. Add one from Manage Data in the menu.',
      );
    }

    if (vicesValue.error ?? activitiesValue.error case final Object error) {
      return InfoBox(
        message: loadErrorMessage('this day', error),
        isError: true,
        onRetry: () {
          ref.invalidate(viceListForUserProvider, asReload: true);
          ref.invalidate(viceActivityDayForUserProvider, asReload: true);
        },
      );
    }

    final List<ViceActivity>? activityList = activitiesValue.value;

    if (vices == null || activityList == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final Map<String, int> quantityByViceID = {
      for (final Vice vice in vices) vice.id: 0,
    };

    for (final ViceActivity activity in activityList) {
      final int? quantity = quantityByViceID[activity.viceID];
      if (quantity != null) {
        quantityByViceID[activity.viceID] = quantity + activity.quantity;
      }
    }

    if (quantityByViceID.values.every((int quantity) => quantity == 0)) {
      return CleanDay(
        isToday: daysBetween(selectedDate, startOfDay(DateTime.now())) == 0,
        offline: ref.watch(offlineProvider).value ?? false,
      );
    }

    final ThemeData theme = Theme.of(context);
    final List<int> quantities = [
      for (final Vice vice in vices) quantityByViceID[vice.id]!,
    ];

    final TextStyle titleStyle = _titleStyle(theme);
    // fl_chart asserts that a radar data set has at least three entries.
    final bool asBars = vices.length < minimumRadarAxes;

    return Semantics(
      container: true,
      label: summary(selectedDate, vices, quantities),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final List<({String text, bool complete})>? barTitles = asBars
                ? _barTitles(
                    context,
                    titleStyle,
                    constraints.maxWidth,
                    vices,
                    quantities,
                  )
                : null;
            final Widget chart = barTitles != null
                ? _bars(context, theme, barTitles, quantities)
                : _radar(context, theme, vices, quantities);
            // Decided on the whole area: the key's height would otherwise
            // change the radar's size, and with it whether the titles fit.
            final bool titlesComplete =
                (barTitles ??
                        _radarTitles(
                          context,
                          titleStyle,
                          _radarInset(
                            context,
                            titleStyle,
                          ).deflateSize(constraints.biggest),
                          vices,
                          quantities,
                        ))
                    .every((({String text, bool complete}) t) => t.complete);
            if (titlesComplete) {
              return chart;
            }

            // A chart under four title lines tall cannot be read.
            final double minimumChart =
                4 * chartLabelSize(context, 'Ag', titleStyle).height;
            return Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints space) =>
                        space.maxHeight < minimumChart
                        ? const SizedBox.shrink()
                        : chart,
                  ),
                ),
                _key(titleStyle, constraints.maxHeight, vices, quantities),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _radar(
    BuildContext context,
    ThemeData theme,
    List<Vice> vices,
    List<int> quantities,
  ) {
    final ({int top, int step}) scale = radarScale(quantities.reduce(max));
    final int rings = scale.top ~/ scale.step;

    final RadarDataSet dataSet = RadarDataSet(
      fillColor: theme.colorScheme.primary.withValues(alpha: 0.2),
      borderColor: theme.colorScheme.primary,
      entryRadius: 6,
      dataEntries: [
        for (final int quantity in quantities)
          RadarEntry(value: quantity.toDouble()),
      ],
      borderWidth: 2,
    );
    // fl_chart puts the smallest entry of all data sets at the centre and the
    // largest on the outer ring, so this invisible set pins them to 0 and to
    // a round top value.
    final RadarDataSet scaleSet = RadarDataSet(
      fillColor: Colors.transparent,
      borderColor: Colors.transparent,
      borderWidth: 0,
      entryRadius: 0,
      dataEntries: [
        RadarEntry(value: scale.top.toDouble()),
        for (int i = 1; i < quantities.length; i++) const RadarEntry(value: 0),
      ],
    );

    final TextStyle titleStyle = _titleStyle(theme);

    return Padding(
      padding: _radarInset(context, titleStyle),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final List<({String text, bool complete})> titles = _radarTitles(
            context,
            titleStyle,
            constraints.biggest,
            vices,
            quantities,
          );

          final double radius = radarRadius(constraints.biggest);
          final RadarChart chart = RadarChart(
            RadarChartData(
              dataSets: [dataSet, scaleSet],
              isMinValueAtCenter: true,
              borderData: FlBorderData(show: false),
              radarBorderData: BorderSide(color: theme.colorScheme.outline),
              radarShape: RadarShape.polygon,
              titlePositionPercentageOffset: radarTitleOffset,
              titleTextStyle: titleStyle,
              getTitle: (int index, double angle) {
                final double correctionFactor = angle > 90 && angle < 270
                    ? 180
                    : 0;

                return RadarChartTitle(
                  text: titles[index].text,
                  angle: angle + correctionFactor,
                );
              },
              tickCount: rings,
              // fl_chart prints every ring's value with one decimal, the
              // centre's 0 included; the rings are labelled below instead.
              ticksTextStyle: const TextStyle(color: Colors.transparent),
              tickBorderData: BorderSide(color: theme.colorScheme.outline),
              gridBorderData: BorderSide(
                color: theme.colorScheme.tertiary,
                width: 1,
              ),
            ),
            duration: const Duration(milliseconds: 600),
            curve: Curves.fastOutSlowIn,
          );

          // Each inner ring's value sits just above it, right of the top
          // axis, where fl_chart would print it; the outer ring is the edge.
          return Stack(
            children: [
              Positioned.fill(child: chart),
              for (int ring = 1; ring < rings; ring++)
                Positioned(
                  left: constraints.maxWidth / 2 + 5,
                  bottom: constraints.maxHeight / 2 + radius * ring / rings,
                  child: Text(
                    formatCount(ring * scale.step),
                    style: TextStyle(
                      color: theme.colorScheme.secondary,
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
