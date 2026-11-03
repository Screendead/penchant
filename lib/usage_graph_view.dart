import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/info_box.dart';

class UsageGraphView extends ConsumerStatefulWidget {
  const UsageGraphView({super.key});

  @override
  ConsumerState<UsageGraphView> createState() => _UsageGraphViewState();
}

class _UsageGraphViewState extends ConsumerState<UsageGraphView> {
  late final DateTime today;
  String? selectedViceID;
  int rangeDays = 30;
  int stepDays = 1;
  int smoothingWindow = 1;

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    today = DateTime(now.year, now.month, now.day);
  }

  void _applyRange(int newRangeDays) {
    if (newRangeDays == rangeDays) {
      return;
    }

    setState(() {
      rangeDays = newRangeDays;
    });
  }

  List<double> _movingAverage(List<double> values, int window) {
    if (window <= 1) {
      return values;
    }

    return List<double>.generate(values.length, (int index) {
      final int start = max(0, index - window + 1);
      final List<double> slice = values.sublist(start, index + 1);
      return slice.reduce((double a, double b) => a + b) / slice.length;
    });
  }

  String? _effectiveViceID(List<Vice> viceList) {
    if (viceList.isEmpty) {
      return null;
    }

    if (selectedViceID != null &&
        viceList.any((Vice vice) => vice.id == selectedViceID)) {
      return selectedViceID;
    }

    return viceList.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final List<Vice>? viceList = ref.watch(viceListProvider).value;

    if (viceList == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (viceList.isEmpty) {
      return const InfoBox(
        message: 'No vices available to graph',
        color: Colors.red,
      );
    }

    final String? effectiveViceID = _effectiveViceID(viceList);
    final Vice selectedVice = viceList.firstWhere(
      (Vice vice) => vice.id == effectiveViceID,
    );

    final DateTime rangeStart = today.subtract(Duration(days: rangeDays - 1));
    final DateTime rangeEnd = today.add(const Duration(days: 1));
    final List<ViceActivity>? activityList =
        ref.watch(
          viceActivityGraphProvider((
            viceID: selectedVice.id,
            start: rangeStart,
            end: rangeEnd,
          )),
        ).value;

    final int bucketCount = ((rangeDays - 1) ~/ stepDays) + 1;
    final List<double> totals = List<double>.filled(bucketCount, 0);

    if (activityList != null) {
      for (final ViceActivity activity in activityList) {
        final int deltaDays =
            activity.createdAt.toDate().difference(rangeStart).inDays;

        final int bucketIndex = deltaDays ~/ stepDays;
        if (bucketIndex >= 0 && bucketIndex < totals.length) {
          totals[bucketIndex] += activity.quantity.toDouble();
        }
      }
    }

    final List<double> smoothed = _movingAverage(totals, smoothingWindow);
    final double maxY = max(
      totals.fold<double>(0, (double a, double b) => a > b ? a : b),
      smoothed.fold<double>(0, (double a, double b) => a > b ? a : b),
    );
    final int smoothingMaxBuckets = max(1, min(7, bucketCount));
    final DateFormat labelFormat = DateFormat('MMM d');

    final List<FlSpot> rawSpots = List<FlSpot>.generate(
      totals.length,
      (int index) => FlSpot(index.toDouble(), totals[index]),
    );
    final List<FlSpot> smoothedSpots = List<FlSpot>.generate(
      smoothed.length,
      (int index) => FlSpot(index.toDouble(), smoothed[index]),
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool useStackedControls = constraints.maxWidth < 720;

              final Widget viceSelector = DropdownButtonFormField<String>(
                key: ValueKey<String?>(effectiveViceID),
                isExpanded: true,
                initialValue: effectiveViceID,
                decoration: const InputDecoration(labelText: 'Vice'),
                items: viceList
                    .map(
                      (Vice vice) => DropdownMenuItem<String>(
                        value: vice.id,
                        child: Text(
                          vice.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (String? value) {
                  if (value != null) {
                    setState(() {
                      selectedViceID = value;
                    });
                  }
                },
              );

              final Widget rangeSelector = DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: rangeDays,
                decoration: const InputDecoration(labelText: 'Range'),
                items: const [7, 14, 30, 90, 180, 365]
                    .map(
                      (int value) => DropdownMenuItem<int>(
                        value: value,
                        child: Text('$value days'),
                      ),
                    )
                    .toList(),
                onChanged: (int? value) {
                  if (value != null) {
                    _applyRange(value);
                  }
                },
              );

              final Widget timestepSelector = DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: stepDays,
                decoration: const InputDecoration(labelText: 'Timestep'),
                items: const [1, 7]
                    .map(
                      (int value) => DropdownMenuItem<int>(
                        value: value,
                        child: Text(value == 1 ? 'Daily' : 'Weekly'),
                      ),
                    )
                    .toList(),
                onChanged: (int? value) {
                  if (value != null) {
                    setState(() {
                      stepDays = value;
                      smoothingWindow = min(smoothingWindow, bucketCount);
                    });
                  }
                },
              );

              if (useStackedControls) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    viceSelector,
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: rangeSelector),
                        const SizedBox(width: 12),
                        Expanded(child: timestepSelector),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: viceSelector),
                  const SizedBox(width: 12),
                  Expanded(child: rangeSelector),
                  const SizedBox(width: 12),
                  Expanded(child: timestepSelector),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            'Smoothing: $smoothingWindow buckets for ${selectedVice.name}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (smoothingMaxBuckets == 1)
            const Text('Smoothing is unavailable for a single bucket')
          else
            Slider(
              min: 1,
              max: smoothingMaxBuckets.toDouble(),
              divisions: smoothingMaxBuckets - 1,
              value: smoothingWindow.clamp(1, smoothingMaxBuckets).toDouble(),
              label: smoothingWindow.toString(),
              onChanged: (double value) {
                setState(() {
                  smoothingWindow = value.round();
                });
              },
            ),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: activityList == null
                    ? const Center(
                        child: CircularProgressIndicator(),
                      )
                    : totals.every((double value) => value == 0)
                        ? Center(
                            child: InfoBox(
                              message:
                                  'No activities found for ${selectedVice.name} in the selected range',
                              color: Colors.red,
                            ),
                          )
                        : LineChart(
                            LineChartData(
                              minX: 0,
                              maxX: max(0, rawSpots.length - 1).toDouble(),
                              minY: 0,
                              maxY: maxY == 0 ? 1 : maxY * 1.15,
                              gridData: const FlGridData(show: true),
                              borderData: FlBorderData(show: false),
                              titlesData: FlTitlesData(
                                topTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                rightTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 40,
                                    interval: max(1, (maxY / 4).ceil()).toDouble(),
                                    getTitlesWidget:
                                        (double value, TitleMeta meta) {
                                      return Text(
                                        value.toInt().toString(),
                                        style: const TextStyle(fontSize: 10),
                                      );
                                    },
                                  ),
                                ),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 40,
                                    interval: max(1, rawSpots.length ~/ 4).toDouble(),
                                    getTitlesWidget:
                                        (double value, TitleMeta meta) {
                                      final int index = value.round();
                                      if (index < 0 || index >= rawSpots.length) {
                                        return const SizedBox.shrink();
                                      }

                                      final DateTime labelDate = rangeStart
                                          .add(Duration(days: index * stepDays));
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(
                                          labelFormat.format(labelDate),
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: rawSpots,
                                  isCurved: true,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.35),
                                  barWidth: 2,
                                  dotData: const FlDotData(show: false),
                                ),
                                if (smoothingWindow > 1)
                                  LineChartBarData(
                                    spots: smoothedSpots,
                                    isCurved: true,
                                    color: Theme.of(context).colorScheme.primary,
                                    barWidth: 3,
                                    dotData: const FlDotData(show: false),
                                  ),
                              ],
                            ),
                            duration: const Duration(milliseconds: 500),
                          ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}