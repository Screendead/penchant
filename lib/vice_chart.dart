import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/widgets/chart_text.dart';
import 'package:tracker/widgets/clean_day.dart';
import 'package:tracker/widgets/info_box.dart';

class ViceChart extends ConsumerWidget {
  const ViceChart({super.key, required this.selectedDate});

  final DateTime selectedDate;

  static const int minimumRadarAxes = 3;
  static const int maximumRadarRings = 5;

  static final DateFormat dayFormat = DateFormat('EEEE, MMMM d, yyyy');

  static String title(Vice vice, int quantity) =>
      '${vice.name} (${vice.unit.label(quantity)})';

  static String summary(DateTime day, List<Vice> vices, List<int> quantities) {
    final String totals = [
      for (int i = 0; i < vices.length; i++)
        '${vices[i].name}: ${vices[i].unit.label(quantities[i])}',
    ].join('; ');

    return 'Totals for ${dayFormat.format(day)}. $totals';
  }

  // The outermost ring's value and the spacing between rings: at most
  // [maximumRadarRings] rings, each a round number of units.
  static ({int top, int step}) radarScale(int largest) {
    for (int magnitude = 1; ; magnitude *= 10) {
      for (final int multiple in const [1, 2, 5]) {
        final int step = multiple * magnitude;
        final int rings = (largest + step - 1) ~/ step;

        if (rings <= maximumRadarRings) {
          return (top: max(rings, 1) * step, step: step);
        }
      }
    }
  }

  Widget _bars(
    BuildContext context,
    ThemeData theme,
    List<Vice> vices,
    List<int> quantities,
  ) {
    final TextStyle titleStyle = TextStyle(
      color: theme.colorScheme.secondary,
      fontSize: 14,
    );
    final double lineHeight = chartLabelSize(context, 'Ag', titleStyle).height;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: BarChart(
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
                reservedSize: max(48, 2 * lineHeight + 8),
                getTitlesWidget: (double value, TitleMeta meta) {
                  final int index = value.toInt();

                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      title(vices[index], quantities[index]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: titleStyle,
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (int i = 0; i < vices.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: quantities[i].toDouble(),
                    width: 48,
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
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Vice>?> vicesValue = ref.watch(
      unarchivedViceListProvider,
    );
    final AsyncValue<List<ViceActivity>?> activitiesValue = ref.watch(
      viceActivityDayProvider(selectedDate),
    );

    if (vicesValue.error ?? activitiesValue.error case final Object error) {
      return InfoBox(message: 'Unable to load this day: $error', isError: true);
    }

    final List<Vice>? vices = vicesValue.value;
    final List<ViceActivity>? activityList = activitiesValue.value;

    if (vices == null || activityList == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (vices.isEmpty) {
      return const InfoBox(
        message: 'No vices yet. Add one from Manage Data in the menu.',
      );
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
      );
    }

    final ThemeData theme = Theme.of(context);
    final List<int> quantities = [
      for (final Vice vice in vices) quantityByViceID[vice.id]!,
    ];

    return Semantics(
      container: true,
      label: summary(selectedDate, vices, quantities),
      excludeSemantics: true,
      // fl_chart asserts that a radar data set has at least three entries.
      child: vices.length < minimumRadarAxes
          ? _bars(context, theme, vices, quantities)
          : _radar(context, theme, vices, quantities),
    );
  }

  Widget _radar(
    BuildContext context,
    ThemeData theme,
    List<Vice> vices,
    List<int> quantities,
  ) {
    final ({int top, int step}) scale = radarScale(quantities.reduce(max));

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

    return Padding(
      padding: const EdgeInsets.all(16),
      child: RadarChart(
        RadarChartData(
          dataSets: [dataSet, scaleSet],
          isMinValueAtCenter: true,
          borderData: FlBorderData(show: false),
          radarBorderData: BorderSide(
            color: theme.colorScheme.tertiary.withValues(alpha: 0.5),
          ),
          radarShape: RadarShape.polygon,
          titlePositionPercentageOffset: 0.2,
          titleTextStyle: TextStyle(
            color: theme.colorScheme.secondary,
            fontSize: 14,
          ),
          getTitle: (int index, double angle) {
            final Vice vice = vices[index];
            final int quantity = quantities[index];
            final double correctionFactor = angle > 90 && angle < 270 ? 180 : 0;

            return RadarChartTitle(
              text: title(vice, quantity),
              angle: angle + correctionFactor,
            );
          },
          tickCount: scale.top ~/ scale.step,
          // fl_chart scales the titles by the device text size, not the ticks.
          ticksTextStyle: TextStyle(
            color: theme.colorScheme.secondary,
            fontSize: MediaQuery.textScalerOf(context).scale(10),
          ),
          tickBorderData: BorderSide(
            color: theme.colorScheme.tertiary.withValues(alpha: 0.5),
          ),
          gridBorderData: BorderSide(
            color: theme.colorScheme.tertiary,
            width: 1,
          ),
        ),
        duration: const Duration(milliseconds: 600),
        curve: Curves.fastOutSlowIn,
      ),
    );
  }
}
