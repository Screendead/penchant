import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/chart_scale.dart';
import 'package:tracker/data/usage_series.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/chart_text.dart';
import 'package:tracker/widgets/info_box.dart';

class UsageGraphView extends ConsumerStatefulWidget {
  const UsageGraphView({super.key});

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
    int peakIndex = 0;
    for (int i = 1; i < totals.length; i++) {
      if (totals[i] > totals[peakIndex]) {
        peakIndex = i;
      }
    }

    final int stepDays = range.stepDays;
    final int total = totals
        .fold<double>(0, (double a, double b) => a + b)
        .round();
    final String peakDate = formatShortDay(range.bucketStart(peakIndex));
    final String average = smoothingWindow > 1
        ? ' Shown with a ${averageName(stepDays, smoothingWindow)}.'
        : '';

    return '${seriesName(stepDays)}s of ${vice.name} over the last '
        '${formatCount(range.days)} days: ${vice.unit.label(total)} in all. The most was '
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
  int pickedWindow,
});

class _UsageGraphViewState extends ConsumerState<UsageGraphView> {
  static const String _storageID = 'UsageGraphView.selection';

  String? selectedViceID;
  int rangeDays = 30;
  int stepDays = 1;
  // The window last picked on the slider; what is applied is
  // [effectiveWindow] of it, so that it never exceeds the buckets shown.
  int pickedWindow = 1;

  // Bucketing depends on the activities and the range only, so a slider drag,
  // which rebuilds every frame, reuses it.
  List<ViceActivity>? _bucketedActivities;
  UsageRange? _bucketedRange;
  List<double> _totals = const <double>[];

  @override
  void initState() {
    super.initState();
    if (PageStorage.maybeOf(context)?.readState(context, identifier: _storageID)
        case final _GraphSelection saved) {
      selectedViceID = saved.viceID;
      rangeDays = saved.rangeDays;
      stepDays = saved.stepDays;
      pickedWindow = saved.pickedWindow;
    }
  }

  void _update(VoidCallback change) {
    setState(change);
    final _GraphSelection selection = (
      viceID: selectedViceID,
      rangeDays: rangeDays,
      stepDays: stepDays,
      pickedWindow: pickedWindow,
    );
    PageStorage.maybeOf(
      context,
    )?.writeState(context, selection, identifier: _storageID);
  }

  List<double> _totalsFor(UsageRange range, List<ViceActivity> activities) {
    if (!identical(activities, _bucketedActivities) ||
        range != _bucketedRange) {
      _bucketedActivities = activities;
      _bucketedRange = range;
      _totals = bucketTotals(range, activities);
    }
    return _totals;
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
        message: loadErrorMessage('your habits', error),
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
      return const InfoBox(message: 'No habits available to graph');
    }

    final String? effectiveViceID = _effectiveViceID(viceList);
    final Vice selectedVice = viceList.firstWhere(
      (Vice vice) => vice.id == effectiveViceID,
    );

    final DateTime today = ref.watch(todayProvider);
    final UsageRange range = usageRange(today, rangeDays, stepDays);
    final AsyncValue<List<ViceActivity>> activityValue = ref.watch(
      viceActivityGraphProvider((
        viceID: selectedVice.id,
        start: range.start,
        end: range.end,
      )),
    );
    final Object? activityError = activityValue.error;
    final List<ViceActivity>? activityList = activityError == null
        ? activityValue.value
        : null;

    final int window = effectiveWindow(pickedWindow, range.bucketCount);
    final int windowLimit = smoothingLimit(range.bucketCount);

    final Widget content;
    if (activityError != null) {
      content = InfoBox(
        message: loadErrorMessage(
          '${selectedVice.name} for this range',
          activityError,
        ),
        isError: true,
        onRetry: () =>
            ref.invalidate(viceActivityGraphForUserProvider, asReload: true),
      );
    } else if (activityList == null) {
      content = const Center(child: CircularProgressIndicator());
    } else {
      final List<double> totals = _totalsFor(range, activityList);
      content = totals.every((double value) => value == 0)
          ? Center(
              child: InfoBox(
                message:
                    'No activities found for ${selectedVice.name} in the selected range',
              ),
            )
          : _UsageChart(
              vice: selectedVice,
              range: range,
              totals: totals,
              smoothed: movingAverage(totals, window),
              window: window,
            );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _controls(viceList, effectiveViceID),
          const SizedBox(height: 16),
          Text(
            'Smoothing: ${formatCount(window)} '
            '${pluralWord(window, one: 'bucket', other: 'buckets')} for '
            '${selectedVice.name}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (windowLimit == 1)
            const Text('Smoothing is unavailable for a single bucket')
          else
            Slider(
              min: 1,
              max: windowLimit.toDouble(),
              divisions: windowLimit - 1,
              value: window.toDouble(),
              label: formatCount(window),
              onChanged: (double value) {
                _update(() {
                  pickedWindow = value.round();
                });
              },
            ),
          Expanded(
            child: Card(
              child: Padding(padding: const EdgeInsets.all(16), child: content),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls(List<Vice> viceList, String? effectiveViceID) {
    final Widget viceSelector = DropdownButtonFormField<String>(
      key: ValueKey<String?>(effectiveViceID),
      isExpanded: true,
      initialValue: effectiveViceID,
      decoration: const InputDecoration(labelText: 'Habit'),
      items: viceList
          .map(
            (Vice vice) => DropdownMenuItem<String>(
              value: vice.id,
              child: Text(_viceLabel(vice), overflow: TextOverflow.ellipsis),
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
              child: Text('${formatCount(value)} days'),
            ),
          )
          .toList(),
      onChanged: (int? value) {
        if (value != null && value != rangeDays) {
          _update(() {
            rangeDays = value;
          });
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
          });
        }
      },
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 720) {
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
    );
  }
}

class _UsageChart extends StatelessWidget {
  const _UsageChart({
    required this.vice,
    required this.range,
    required this.totals,
    required this.smoothed,
    required this.window,
  });

  static const TextStyle axisStyle = TextStyle(fontSize: 10);
  static const int maxYSteps = 4;
  static const double labelGap = 8;

  final Vice vice;
  final UsageRange range;
  final List<double> totals;
  final List<double> smoothed;
  final int window;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int stepDays = range.stepDays;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (window > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ExcludeSemantics(
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _LegendEntry(
                    color: scheme.primary.withValues(alpha: 0.5),
                    dashed: true,
                    label: UsageGraphView.seriesName(stepDays),
                  ),
                  _LegendEntry(
                    color: scheme.primary,
                    dashed: false,
                    label: UsageGraphView.averageName(stepDays, window),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: Semantics(
            container: true,
            label: UsageGraphView.summary(
              vice: vice,
              range: range,
              totals: totals,
              smoothingWindow: window,
            ),
            excludeSemantics: true,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) =>
                  LineChart(
                    _data(context, scheme, constraints.biggest),
                    duration: const Duration(milliseconds: 500),
                  ),
            ),
          ),
        ),
      ],
    );
  }

  LineChartData _data(BuildContext context, ColorScheme scheme, Size size) {
    final Size dateLabel = chartLabelSize(
      context,
      formatShortDay(DateTime(2000, 5, 30)),
      axisStyle,
    );
    final double bottomTitlesHeight = max(40, dateLabel.height + 16);
    final double numberHeight = chartLabelSize(context, '0', axisStyle).height;

    // The tallest bucket plus headroom, on a round scale with as many steps as
    // fit the plot's height.
    final int largest = (totals.reduce(max) * 1.15).ceil();
    final double plotHeight = max(0, size.height - bottomTitlesHeight);
    final ({int top, int step}) yScale = roundScale(
      largest,
      min(maxYSteps, max(1, plotHeight ~/ (numberHeight + labelGap))),
    );
    final double leftTitlesWidth = max(
      40,
      chartLabelSize(context, formatCount(yScale.top), axisStyle).width +
          labelGap,
    );

    final Set<int> labelled = labelIndices(
      totals.length,
      labelsThatFit(size.width - leftTitlesWidth, dateLabel.width),
    ).toSet();

    final List<FlSpot> rawSpots = [
      for (int i = 0; i < totals.length; i++) FlSpot(i.toDouble(), totals[i]),
    ];
    final List<FlSpot> smoothedSpots = [
      for (int i = 0; i < smoothed.length; i++)
        FlSpot(i.toDouble(), smoothed[i]),
    ];

    return LineChartData(
      minX: 0,
      maxX: max(0, totals.length - 1).toDouble(),
      minY: 0,
      maxY: yScale.top.toDouble(),
      // preventCurveOverShooting keeps the tangent of a point that falls steeply
      // on both sides, so a steep fall through a small value to zero can still
      // swing below the axis.
      clipData: const FlClipData(
        top: false,
        bottom: true,
        left: false,
        right: false,
      ),
      gridData: const FlGridData(show: true),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: leftTitlesWidth,
            interval: yScale.step.toDouble(),
            getTitlesWidget: (double value, TitleMeta meta) =>
                Text(formatCount(value.round()), style: axisStyle),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: bottomTitlesHeight,
            interval: 1,
            getTitlesWidget: (double value, TitleMeta meta) {
              final int index = value.round();
              if (!labelled.contains(index)) {
                return const SizedBox.shrink();
              }

              return SideTitleWidget(
                meta: meta,
                fitInside: SideTitleFitInsideData.fromTitleMeta(
                  meta,
                  distanceFromEdge: 0,
                ),
                child: Text(
                  formatShortDay(range.bucketStart(index)),
                  style: axisStyle,
                  maxLines: 1,
                  softWrap: false,
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
          preventCurveOverShooting: true,
          color: scheme.primary.withValues(alpha: 0.5),
          barWidth: 2,
          dashArray: const [4, 4],
          dotData: const FlDotData(show: false),
        ),
        if (window > 1)
          LineChartBarData(
            spots: smoothedSpots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: scheme.primary,
            barWidth: 3,
            dotData: const FlDotData(show: false),
          ),
      ],
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
