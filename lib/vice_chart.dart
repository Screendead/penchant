import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/vice_activities_by_vice_id_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/info_box.dart';

class ViceChart extends ConsumerStatefulWidget {
  const ViceChart({super.key});

  @override
  ConsumerState<ViceChart> createState() => ViceChartState();
}

class ViceChartState extends ConsumerState<ViceChart> {
  DateTime? selectedDate;

  void updateDate(DateTime newDate) {
    if (selectedDate == newDate) {
      return;
    }

    selectedDate = newDate;
  }

  bool isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  @override
  Widget build(BuildContext context) {
    final List<Vice>? vices = ref.watch(unarchivedViceListProvider).value;
    final Map<String, List<ViceActivity>>? viceActivityListByViceID =
        ref.watch(viceActivityListByViceIDProvider);

    if (vices == null ||
        viceActivityListByViceID == null ||
        selectedDate == null) {
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

    if (viceActivityListByViceID.isEmpty) {
      return const InfoBox(
        message: 'No activities found',
        color: Colors.red,
      );
    }

    final Map<String, int> todayData = {};

    for (final Vice vice in vices) {
      todayData[vice.name] = 0;
    }

    viceActivityListByViceID.forEach((viceID, activities) {
      for (final ViceActivity activity in activities) {
        if (isSameDay(activity.createdAt.toDate(), selectedDate!)) {
          final vice = vices.firstWhere((v) => v.id == viceID);
          todayData[vice.name] =
              (todayData[vice.name] ?? 0) + activity.quantity;
        }
      }
    });

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
