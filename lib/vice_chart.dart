import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/info_box.dart';

class ViceChart extends ConsumerWidget {
  const ViceChart({super.key, required this.selectedDate});

  final DateTime selectedDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Vice>? vices = ref.watch(unarchivedViceListProvider).value;
    final List<ViceActivity>? activityList =
        ref.watch(viceActivityDayProvider(selectedDate)).value;

    if (vices == null || activityList == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (vices.isEmpty) {
      return const InfoBox(
        message: 'No vices found',
        color: Colors.red,
      );
    }

    if (activityList.isEmpty) {
      return const InfoBox(
        message: 'No activities found',
        color: Colors.red,
      );
    }

    final Map<String, Vice> vicesByID = {
      for (final Vice vice in vices) vice.id: vice,
    };
    final Map<String, int> todayData = {
      for (final Vice vice in vices) vice.name: 0,
    };

    for (final ViceActivity activity in activityList) {
      final Vice? vice = vicesByID[activity.viceID];
      if (vice == null) {
        continue;
      }

      todayData[vice.name] = (todayData[vice.name] ?? 0) + activity.quantity;
    }

    final ThemeData theme = Theme.of(context);
    final List<RadarEntry> dataEntries = todayData.entries
        .map(
          (e) => RadarEntry(
            value: e.value.toDouble(),
          ),
        )
        .toList();

    final int tickCount = max(
      todayData.values.fold(0, (a, b) => a > b ? a : b),
      1,
    );

    final RadarDataSet dataSet = RadarDataSet(
      fillColor: theme.colorScheme.primary.withValues(alpha: 0.2),
      borderColor: theme.colorScheme.primary,
      entryRadius: 6,
      dataEntries: dataEntries,
      borderWidth: 2,
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: RadarChart(
        RadarChartData(
          dataSets: [dataSet],
          // radarBackgroundColor: Colors.pink.withOpacity(0.25),
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
            final List<Vice>? vices = ref.watch(viceListProvider).value;

            if (vices == null) {
              return const RadarChartTitle(text: '');
            }

            final Vice vice = vices.firstWhere(
              (v) => v.name == todayData.keys.elementAt(index),
            );
            final int quantity = todayData.values.elementAt(index);
            final double correctionFactor = angle > 90 && angle < 270 ? 180 : 0;

            return RadarChartTitle(
              text: '${vice.name} (${vice.unit.label(quantity)})',
              angle: angle + correctionFactor,
            );
          },
          tickCount: tickCount,
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
