import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/info_box.dart';

enum TimeScale {
  day('Day', 'Hourly'),
  week('Week', 'Daily'),
  month('Month', 'Daily'),
  quarter('Quarter', 'Weekly'),
  year('Year', 'Monthly');

  const TimeScale(this.label, this.breakdown);
  final String label;
  final String breakdown;
}

class ViceTimeSeriesChart extends ConsumerStatefulWidget {
  const ViceTimeSeriesChart({
    super.key,
    required this.selectedDate,
  });

  final DateTime selectedDate;

  @override
  ConsumerState<ViceTimeSeriesChart> createState() => _ViceTimeSeriesChartState();
}

class _ViceTimeSeriesChartState extends ConsumerState<ViceTimeSeriesChart> {
  TimeScale selectedTimeScale = TimeScale.week;

  @override
  Widget build(BuildContext context) {
    final List<Vice>? vices = ref.watch(viceListProvider).value;

    if (vices == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Time scale selector
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Text(
                'Time Scale:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              DropdownButton<TimeScale>(
                value: selectedTimeScale,
                onChanged: (TimeScale? newValue) {
                  setState(() {
                    selectedTimeScale = newValue!;
                  });
                },
                items: TimeScale.values.map((TimeScale scale) {
                  return DropdownMenuItem<TimeScale>(
                    value: scale,
                    child: Text('${scale.label} (${scale.breakdown})'),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Chart area
          Expanded(
            child: StreamBuilder<Map<String, List<ViceActivity>>>(
              stream: _getViceActivitiesStream(vices),
              builder: (
                BuildContext context,
                AsyncSnapshot<Map<String, List<ViceActivity>>> snapshot,
              ) {
                if (snapshot.hasError) {
                  return InfoBox(
                    message:
                        'Error loading activities:\n${snapshot.error.toString()}',
                    color: Colors.red,
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const InfoBox(
                    message: 'No vice activities found.',
                    color: Colors.blue,
                  );
                }

                return _buildTimeSeriesChart(vices, snapshot.data!);
              },
            ),
          ),
        ],
      ),
    );
  }

  Stream<Map<String, List<ViceActivity>>> _getViceActivitiesStream(List<Vice> vices) {
    final DateTime startDate = _getStartDate();
    final DateTime endDate = _getEndDate();

    return FirebaseFirestore.instance
        .collection('activities')
        .where('viceID', whereIn: vices.map((vice) => vice.id))
        .where('ownerID', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.fold<Map<String, List<ViceActivity>>>(
            <String, List<ViceActivity>>{},
            (map, doc) {
              final ViceActivity activity = ViceActivity.fromJson(
                id: doc.id,
                json: doc.data(),
              );

              if (map.containsKey(activity.viceID)) {
                map[activity.viceID]!.add(activity);
              } else {
                map[activity.viceID] = <ViceActivity>[activity];
              }

              return map;
            },
          ),
        );
  }

  DateTime _getStartDate() {
    switch (selectedTimeScale) {
      case TimeScale.day:
        // Last 24 hours
        return widget.selectedDate.subtract(const Duration(hours: 24));
      case TimeScale.week:
        // Last 7 days
        return widget.selectedDate.subtract(const Duration(days: 7));
      case TimeScale.month:
        // Last 30 days
        return widget.selectedDate.subtract(const Duration(days: 30));
      case TimeScale.quarter:
        // Last 90 days
        return widget.selectedDate.subtract(const Duration(days: 90));
      case TimeScale.year:
        // Last 365 days
        return widget.selectedDate.subtract(const Duration(days: 365));
    }
  }

  DateTime _getEndDate() {
    // For all scales, end at the selected date
    return widget.selectedDate;
  }

  Widget _buildTimeSeriesChart(List<Vice> vices, Map<String, List<ViceActivity>> viceActivities) {
    final Map<String, List<FlSpot>> viceDataPoints = {};
    final List<Color> viceColors = [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.cyan,
      Colors.pink,
      Colors.yellow,
    ];

    // Initialize data points for each vice
    for (int i = 0; i < vices.length; i++) {
      viceDataPoints[vices[i].id] = [];
    }

    // Generate data points based on selected time scale
    final List<DateTime> timePoints = _generateTimePoints();
    final Map<String, String> timeLabels = _generateTimeLabels(timePoints);

    // Check if we have any data points
    if (timePoints.isEmpty) {
      return const InfoBox(
        message: 'No time points available for the selected scale.',
        color: Colors.orange,
      );
    }

    for (int i = 0; i < timePoints.length; i++) {
      final DateTime timePoint = timePoints[i];
      
      for (final Vice vice in vices) {
        final List<ViceActivity> activities = viceActivities[vice.id] ?? [];
        final int quantity = _aggregateQuantityForTimePoint(activities, timePoint);
        viceDataPoints[vice.id]!.add(FlSpot(i.toDouble(), quantity.toDouble()));
      }
    }

    // Create line chart data
    final List<LineChartBarData> lines = [];
    for (int i = 0; i < vices.length; i++) {
      final Vice vice = vices[i];
      final List<FlSpot> spots = viceDataPoints[vice.id]!;
      final Color color = viceColors[i % viceColors.length];

      lines.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: color,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(
            show: true,
            color: color.withOpacity(0.1),
          ),
        ),
      );
    }

    final ThemeData theme = Theme.of(context);

    return Column(
      children: [
        // Legend
        Wrap(
          spacing: 16,
          children: vices.asMap().entries.map((entry) {
            final int index = entry.key;
            final Vice vice = entry.value;
            final Color color = viceColors[index % viceColors.length];
            
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(vice.name),
              ],
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        // Chart
        Expanded(
          child: LineChart(
            LineChartData(
              lineBarsData: lines,
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        value.toInt().toString(),
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: _getBottomTitleInterval(timePoints.length),
                    getTitlesWidget: (value, meta) {
                      final int index = value.toInt();
                      if (index >= 0 && index < timePoints.length) {
                        final String label = timeLabels[timePoints[index].toString()] ?? '';
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            label,
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontSize: 10,
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(
                  color: theme.colorScheme.outline,
                  width: 1,
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                drawHorizontalLine: true,
                horizontalInterval: 1,
                verticalInterval: 1,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: theme.colorScheme.outline.withOpacity(0.3),
                    strokeWidth: 1,
                  );
                },
                getDrawingVerticalLine: (value) {
                  return FlLine(
                    color: theme.colorScheme.outline.withOpacity(0.3),
                    strokeWidth: 1,
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<DateTime> _generateTimePoints() {
    final DateTime startDate = _getStartDate();
    final DateTime endDate = _getEndDate();
    final List<DateTime> points = [];

    switch (selectedTimeScale) {
      case TimeScale.day:
        // Generate hourly points for last 24 hours
        for (int hour = 0; hour < 24; hour++) {
          points.add(startDate.add(Duration(hours: hour)));
        }
        break;
      case TimeScale.week:
        // Generate daily points for last 7 days
        for (int day = 0; day < 7; day++) {
          points.add(startDate.add(Duration(days: day)));
        }
        break;
      case TimeScale.month:
        // Generate daily points for last 30 days
        for (int day = 0; day < 30; day++) {
          points.add(startDate.add(Duration(days: day)));
        }
        break;
      case TimeScale.quarter:
        // Generate weekly points for last 90 days (~13 weeks)
        for (int week = 0; week < 13; week++) {
          points.add(startDate.add(Duration(days: week * 7)));
        }
        break;
      case TimeScale.year:
        // Generate monthly points for last 365 days (~12 months)
        // Start from selected date and go back month by month
        DateTime current = DateTime(endDate.year, endDate.month, 1);
        for (int month = 0; month < 12; month++) {
          points.add(current);
          // Go back one month
          if (current.month == 1) {
            current = DateTime(current.year - 1, 12, 1);
          } else {
            current = DateTime(current.year, current.month - 1, 1);
          }
        }
        // Reverse to have chronological order
        points.sort();
        break;
    }

    return points;
  }

  Map<String, String> _generateTimeLabels(List<DateTime> timePoints) {
    final Map<String, String> labels = {};

    for (final DateTime point in timePoints) {
      String label;
      switch (selectedTimeScale) {
        case TimeScale.day:
          label = DateFormat('HH:mm').format(point);
          break;
        case TimeScale.week:
          label = DateFormat('E').format(point);
          break;
        case TimeScale.month:
          label = DateFormat('d').format(point);
          break;
        case TimeScale.quarter:
          label = DateFormat('M/d').format(point);
          break;
        case TimeScale.year:
          label = DateFormat('MMM').format(point);
          break;
      }
      labels[point.toString()] = label;
    }

    return labels;
  }

  double _getBottomTitleInterval(int pointCount) {
    if (pointCount <= 7) return 1;
    if (pointCount <= 14) return 2;
    if (pointCount <= 31) return pointCount > 20 ? 5 : 3;
    return (pointCount / 6).ceil().toDouble();
  }

  int _aggregateQuantityForTimePoint(List<ViceActivity> activities, DateTime timePoint) {
    int totalQuantity = 0;

    for (final ViceActivity activity in activities) {
      final DateTime activityDate = activity.createdAt.toDate();
      
      bool includeActivity = false;
      switch (selectedTimeScale) {
        case TimeScale.day:
          // Include if within the same hour
          includeActivity = activityDate.year == timePoint.year &&
              activityDate.month == timePoint.month &&
              activityDate.day == timePoint.day &&
              activityDate.hour == timePoint.hour;
          break;
        case TimeScale.week:
        case TimeScale.month:
          // Include if on the same day
          includeActivity = activityDate.year == timePoint.year &&
              activityDate.month == timePoint.month &&
              activityDate.day == timePoint.day;
          break;
        case TimeScale.quarter:
          // Include if within the same week
          final int activityWeek = _getWeekOfYear(activityDate);
          final int timePointWeek = _getWeekOfYear(timePoint);
          includeActivity = activityDate.year == timePoint.year &&
              activityWeek == timePointWeek;
          break;
        case TimeScale.year:
          // Include if within the same month
          includeActivity = activityDate.year == timePoint.year &&
              activityDate.month == timePoint.month;
          break;
      }

      if (includeActivity) {
        totalQuantity += activity.quantity;
      }
    }

    return totalQuantity;
  }

  int _getWeekOfYear(DateTime date) {
    // ISO 8601 week calculation
    final DateTime jan1 = DateTime(date.year, 1, 1);
    final int daysFromJan1 = date.difference(jan1).inDays;
    final int jan1Weekday = jan1.weekday;
    
    // Adjust for the first week of the year
    final int weekNumber = ((daysFromJan1 + jan1Weekday - 1) / 7).floor() + 1;
    
    return weekNumber;
  }
}