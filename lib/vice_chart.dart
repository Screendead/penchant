import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/widgets/clean_day.dart';
import 'package:tracker/widgets/info_box.dart';

class ViceChart extends ConsumerWidget {
  const ViceChart({super.key, required this.selectedDate});

  final DateTime selectedDate;

  static const int minimumRadarAxes = 3;

  static String title(Vice vice, int quantity) =>
      '${vice.name} (${vice.unit.label(quantity)})';

  Widget _bars(ThemeData theme, List<Vice> vices, List<int> quantities) {
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
                reservedSize: 48,
                getTitlesWidget: (double value, TitleMeta meta) {
                  final int index = value.toInt();

                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      title(vices[index], quantities[index]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.colorScheme.secondary,
                        fontSize: 14,
                      ),
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
        message: 'No vices yet. Add one from Manage Data in the menu.',
        color: Colors.blueGrey,
      );
    }

    if (vicesValue.error ?? activitiesValue.error case final Object error) {
      return InfoBox(
        message: 'Unable to load this day: $error',
        color: Colors.red,
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
      );
    }

    final ThemeData theme = Theme.of(context);
    final List<int> quantities = [
      for (final Vice vice in vices) quantityByViceID[vice.id]!,
    ];

    // fl_chart asserts that a radar data set has at least three entries.
    if (vices.length < minimumRadarAxes) {
      return _bars(theme, vices, quantities);
    }

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

    return Padding(
      padding: const EdgeInsets.all(16),
      child: RadarChart(
        RadarChartData(
          dataSets: [dataSet],
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
          tickCount: max(quantities.reduce(max), 1),
          ticksTextStyle: TextStyle(
            color: theme.colorScheme.secondary,
            fontSize: 10,
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
