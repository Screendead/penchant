import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/widgets/info_box.dart';

class ViceChart extends ConsumerWidget {
  const ViceChart({super.key, required this.selectedDate});

  final DateTime selectedDate;

  static const int minimumRadarAxes = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Vice>?> vicesValue = ref.watch(
      unarchivedViceListProvider,
    );
    final AsyncValue<List<ViceActivity>?> activitiesValue = ref.watch(
      viceActivityDayProvider(selectedDate),
    );

    if (vicesValue.error ?? activitiesValue.error case final Object error) {
      return InfoBox(
        message: 'Unable to load this day: $error',
        color: Colors.red,
      );
    }

    final List<Vice>? vices = vicesValue.value;
    final List<ViceActivity>? activityList = activitiesValue.value;

    if (vices == null || activityList == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (vices.isEmpty) {
      return const InfoBox(
        message: 'No vices yet. Add one from Manage Data in the menu.',
        color: Colors.blueGrey,
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
      return const InfoBox(
        message: 'Nothing recorded on this day',
        color: Colors.blueGrey,
      );
    }

    final ThemeData theme = Theme.of(context);
    final List<int> quantities = [
      for (final Vice vice in vices) quantityByViceID[vice.id]!,
    ];

    // fl_chart asserts that a radar data set has at least three entries.
    if (vices.length < minimumRadarAxes) {
      return ListView(
        children: [
          for (int i = 0; i < vices.length; i++)
            ListTile(
              title: Text(vices[i].name),
              trailing: Text(vices[i].unit.label(quantities[i])),
            ),
        ],
      );
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
              text: '${vice.name} (${vice.unit.label(quantity)})',
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
