import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/chart_text.dart';
import 'package:tracker/widgets/info_box.dart';

class UsageGraphView extends ConsumerStatefulWidget {
  const UsageGraphView({super.key});

  static final DateFormat labelFormat = DateFormat('MMM d');

  static String seriesName(int stepDays) =>
      stepDays == 1 ? 'Daily total' : 'Weekly total';

  static String averageName(int stepDays, int window) =>
      '$window-${stepDays == 1 ? 'day' : 'week'} average';

  static String summary({
    required Vice vice,
    required List<double> totals,
    required DateTime rangeStart,
    required int rangeDays,
    required int stepDays,
    required int smoothingWindow,
  }) {
    int peakIndex = 0;
    for (int i = 1; i < totals.length; i++) {
      if (totals[i] > totals[peakIndex]) {
        peakIndex = i;
      }
    }

    final int total = totals
        .fold<double>(0, (double a, double b) => a + b)
        .round();
    final String peakDate = labelFormat.format(
      addDays(rangeStart, peakIndex * stepDays),
    );
    final String average = smoothingWindow > 1
        ? ' Shown with a ${averageName(stepDays, smoothingWindow)}.'
        : '';

    return '${seriesName(stepDays)}s of ${vice.name} over the last '
        '$rangeDays days: ${vice.unit.label(total)} in all. The most was '
        '${vice.unit.label(totals[peakIndex].round())} '
        '${stepDays == 1 ? 'on' : 'in the week of'} $peakDate.$average';
  }

  @override
  ConsumerState<UsageGraphView> createState() => _UsageGraphViewState();
}

typedef _GraphSelection = ({
  String? viceID,
  int rangeDays,
  int stepDays,
  int smoothingWindow,
});

class _UsageGraphViewState extends ConsumerState<UsageGraphView> {
  static const String _storageID = 'UsageGraphView.selection';

  String? selectedViceID;
  int rangeDays = 30;
  int stepDays = 1;
  int smoothingWindow = 1;

  @override
  void initState() {
    super.initState();
    if (PageStorage.maybeOf(context)?.readState(context, identifier: _storageID)
        case final _GraphSelection saved) {
      selectedViceID = saved.viceID;
      rangeDays = saved.rangeDays;
      stepDays = saved.stepDays;
      smoothingWindow = saved.smoothingWindow;
    }
  }

  void _update(VoidCallback change) {
    setState(change);
    final _GraphSelection selection = (
      viceID: selectedViceID,
      rangeDays: rangeDays,
      stepDays: stepDays,
      smoothingWindow: smoothingWindow,
    );
    PageStorage.maybeOf(
      context,
    )?.writeState(context, selection, identifier: _storageID);
  }

  void _applyRange(int newRangeDays) {
    if (newRangeDays == rangeDays) {
      return;
    }

    _update(() {
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

  static String _viceLabel(Vice vice) =>
      vice.archived ? '${vice.name} (archived)' : vice.name;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Vice>> viceListValue = ref.watch(viceListProvider);

    if (viceListValue.error case final Object error) {
      return ErrorView(
        message: loadErrorMessage('your vices', error),
        onRetry: () => ref.invalidate(viceListForUserProvider, asReload: true),
      );
    }

    final List<Vice>? allVices = viceListValue.value;

    if (allVices == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // An archived vice keeps its history, so it stays graphable, after the
    // vices in use.
    final List<Vice> viceList = <Vice>[
      ...allVices.where((Vice vice) => !vice.archived),
      ...allVices.where((Vice vice) => vice.archived),
    ];

    if (viceList.isEmpty) {
      return const InfoBox(message: 'No vices available to graph');
    }

    final String? effectiveViceID = _effectiveViceID(viceList);
    final Vice selectedVice = viceList.firstWhere(
      (Vice vice) => vice.id == effectiveViceID,
    );

    final DateTime today = ref.watch(todayProvider);
    final DateTime rangeStart = addDays(today, -(rangeDays - 1));
    final DateTime rangeEnd = addDays(today, 1);
    final AsyncValue<List<ViceActivity>> activityValue = ref.watch(
      viceActivityGraphProvider((
        viceID: selectedVice.id,
        start: rangeStart,
        end: rangeEnd,
      )),
    );
    final Object? activityError = activityValue.error;
    final List<ViceActivity>? activityList = activityError == null
        ? activityValue.value
        : null;

    final int bucketCount = ((rangeDays - 1) ~/ stepDays) + 1;
    final List<double> totals = List<double>.filled(bucketCount, 0);

    if (activityList != null) {
      for (final ViceActivity activity in activityList) {
        final int deltaDays = daysBetween(
          rangeStart,
          activity.createdAt.toDate(),
        );

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
    final DateFormat labelFormat = UsageGraphView.labelFormat;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    const TextStyle axisStyle = TextStyle(fontSize: 10);
    final double chartMaxY = maxY == 0 ? 1 : maxY * 1.15;
    final double leftTitlesWidth = max(
      40,
      chartLabelSize(context, '${chartMaxY.ceil()}', axisStyle).width + 8,
    );
    final double bottomTitlesHeight = max(
      40,
      chartLabelSize(context, 'May 30', axisStyle).height + 16,
    );

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
                          _viceLabel(vice),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (String? value) {
                  if (value != null) {
                    _update(() {
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
                    _update(() {
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
                _update(() {
                  smoothingWindow = value.round();
                });
              },
            ),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: activityError != null
                    ? InfoBox(
                        message: loadErrorMessage(
                          '${selectedVice.name} for this range',
                          activityError,
                        ),
                        isError: true,
                        onRetry: () => ref.invalidate(
                          viceActivityGraphForUserProvider,
                          asReload: true,
                        ),
                      )
                    : activityList == null
                    ? const Center(child: CircularProgressIndicator())
                    : totals.every((double value) => value == 0)
                    ? Center(
                        child: InfoBox(
                          message:
                              'No activities found for ${selectedVice.name} in the selected range',
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (smoothingWindow > 1)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: ExcludeSemantics(
                                child: Wrap(
                                  spacing: 16,
                                  runSpacing: 4,
                                  children: [
                                    _LegendEntry(
                                      color: scheme.primary.withValues(
                                        alpha: 0.5,
                                      ),
                                      dashed: true,
                                      label: UsageGraphView.seriesName(
                                        stepDays,
                                      ),
                                    ),
                                    _LegendEntry(
                                      color: scheme.primary,
                                      dashed: false,
                                      label: UsageGraphView.averageName(
                                        stepDays,
                                        smoothingWindow,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          Expanded(
                            child: Semantics(
                              container: true,
                              label: UsageGraphView.summary(
                                vice: selectedVice,
                                totals: totals,
                                rangeStart: rangeStart,
                                rangeDays: rangeDays,
                                stepDays: stepDays,
                                smoothingWindow: smoothingWindow,
                              ),
                              excludeSemantics: true,
                              child: LineChart(
                                LineChartData(
                                  minX: 0,
                                  maxX: max(0, rawSpots.length - 1).toDouble(),
                                  minY: 0,
                                  maxY: chartMaxY,
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
                                        reservedSize: leftTitlesWidth,
                                        interval: max(
                                          1,
                                          (maxY / 4).ceil(),
                                        ).toDouble(),
                                        getTitlesWidget:
                                            (double value, TitleMeta meta) {
                                              return Text(
                                                value.toInt().toString(),
                                                style: axisStyle,
                                              );
                                            },
                                      ),
                                    ),
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: bottomTitlesHeight,
                                        interval: max(
                                          1,
                                          rawSpots.length ~/ 4,
                                        ).toDouble(),
                                        getTitlesWidget:
                                            (double value, TitleMeta meta) {
                                              final int index = value.round();
                                              if (index < 0 ||
                                                  index >= rawSpots.length) {
                                                return const SizedBox.shrink();
                                              }

                                              final DateTime labelDate =
                                                  addDays(
                                                    rangeStart,
                                                    index * stepDays,
                                                  );
                                              return Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 8,
                                                ),
                                                child: Text(
                                                  labelFormat.format(labelDate),
                                                  style: axisStyle,
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
                                      color: scheme.primary.withValues(
                                        alpha: 0.5,
                                      ),
                                      barWidth: 2,
                                      dashArray: const [4, 4],
                                      dotData: const FlDotData(show: false),
                                    ),
                                    if (smoothingWindow > 1)
                                      LineChartBarData(
                                        spots: smoothedSpots,
                                        isCurved: true,
                                        color: scheme.primary,
                                        barWidth: 3,
                                        dotData: const FlDotData(show: false),
                                      ),
                                  ],
                                ),
                                duration: const Duration(milliseconds: 500),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({
    required this.color,
    required this.dashed,
    required this.label,
  });

  final Color color;
  final bool dashed;
  final String label;

  @override
  Widget build(BuildContext context) {
    final Widget segment = Container(width: 8, height: 3, color: color);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 24,
          child: dashed
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [segment, segment],
                )
              : Container(height: 3, color: color),
        ),
        const SizedBox(width: 8),
        Flexible(child: Text(label)),
      ],
    );
  }
}
