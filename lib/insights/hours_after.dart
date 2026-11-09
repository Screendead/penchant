import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/what_follows.dart';

// Health values stay on the device: nothing here is logged or reported.

/// The spans after a use that [hoursAfter] judges, each on its own.
const List<HourWindow> hoursAfterWindows = <HourWindow>[
  (start: 0, end: 30),
  (start: 30, end: 60),
  (start: 60, end: 120),
  (start: 120, end: 240),
];

/// The baseline before a use, in minutes.
const int hoursAfterBaselineMinutes = 60;

/// How long a use is taken to last: no other use of the habit may fall this
/// long before an event, nor this long either side of a control.
const int hoursAfterClearMinutes = 240;

/// Uses older than this many days before the last day are not read.
const int hoursAfterLookbackDays = 365;

/// The most recent uses of each habit read, at most.
const int hoursAfterMaxEvents = 120;

/// How far from a use's day its control may be, in days.
const int hoursAfterControlReachDays = 7;

/// The sample measures judged, as [HealthSampleMetric.id].
const List<HealthSampleMetric> hoursAfterMetrics = <HealthSampleMetric>[
  HealthSampleMetric.heartRate,
  HealthSampleMetric.heartRateVariabilitySDNN,
];

class HoursAfterGates {
  const HoursAfterGates({
    this.minSamples = 3,
    this.minEventDays = 10,
    this.minControlDays = 10,
    this.maxStepsPerMinute = 40,
    this.level = 0.95,
  });

  /// In the baseline and in the window, each.
  final int minSamples;
  final int minEventDays;
  final int minControlDays;

  /// A baseline or window walked through at more than this, on average, is
  /// left out: the heart rate then says how far you walked.
  final double maxStepsPerMinute;
  final double level;
}

/// One moment [hoursAfter] measures around: a use, or the same clock time on a
/// nearby day clear of the habit.
class HoursAfterPoint {
  const HoursAfterPoint(this.habitId, this.at, {required this.control});

  final String habitId;
  final DateTime at;
  final bool control;
}

class HoursAfterPlan {
  const HoursAfterPlan(this.points, this.reads);

  final List<HoursAfterPoint> points;

  /// The spans to read samples for, oldest first, none overlapping: one per
  /// day with a point at most, so a year costs at most a call a day per
  /// measure (more only when a day's span holds over a page).
  final List<({DateTime start, DateTime end})> reads;
}

/// Which moments to measure and which samples to read for them, from [uses]
/// up to [through] (exclusive). Each habit's events are its uses with none of
/// it in the [hoursAfterClearMinutes] before, from the last
/// [hoursAfterLookbackDays] days, at most [hoursAfterMaxEvents] of them, most
/// recent first. Each event gets one control: the same clock time on the
/// nearest day, within [hoursAfterControlReachDays], with no use of the habit
/// within [hoursAfterClearMinutes] either side of it. A day with the habit at
/// another time can serve, so a habit used every day still has controls
/// unless it is used at nearly the same time every day.
HoursAfterPlan planHoursAfter(List<HabitUse> uses, DateTime through) {
  final DateTime since = addDays(startOfDay(through), -hoursAfterLookbackDays);
  final Map<String, List<DateTime>> byHabit = <String, List<DateTime>>{};
  for (final HabitUse u in uses) {
    if (u.amount > 0) byHabit.putIfAbsent(u.habitId, () => []).add(u.at);
  }
  const Duration clear = Duration(minutes: hoursAfterClearMinutes);
  final List<HoursAfterPoint> points = <HoursAfterPoint>[];
  final List<String> ids = byHabit.keys.toList()..sort();
  for (final String id in ids) {
    final List<DateTime> times = byHabit[id]!..sort();
    bool clearAround(DateTime at, Duration before, Duration after) =>
        !_anyIn(times, at.subtract(before), at.add(after));

    final List<DateTime> events = <DateTime>[
      for (int i = times.length - 1; i >= 0; i--)
        if (!times[i].isBefore(since) &&
            times[i].isBefore(through) &&
            clearAround(times[i], clear, Duration.zero))
          times[i],
    ].take(hoursAfterMaxEvents).toList();
    final Set<DateTime> taken = <DateTime>{};
    for (final DateTime at in events) {
      points.add(HoursAfterPoint(id, at, control: false));
      final DateTime day = startOfDay(at);
      for (int k = 1; k <= 2 * hoursAfterControlReachDays; k++) {
        final int offset = k.isOdd ? -(k + 1) ~/ 2 : k ~/ 2;
        final DateTime other = addDays(day, offset);
        final DateTime p = DateTime(
          other.year,
          other.month,
          other.day,
          at.hour,
          at.minute,
          at.second,
        );
        if (!p.add(const Duration(minutes: 240)).isBefore(through) ||
            p.isBefore(since) ||
            taken.contains(p) ||
            !clearAround(p, clear, clear)) {
          continue;
        }
        taken.add(p);
        points.add(HoursAfterPoint(id, p, control: true));
        break;
      }
    }
  }
  return HoursAfterPlan(points, _reads(points));
}

List<({DateTime start, DateTime end})> _reads(List<HoursAfterPoint> points) {
  final Map<DateTime, ({DateTime start, DateTime end})> byDay =
      <DateTime, ({DateTime start, DateTime end})>{};
  for (final HoursAfterPoint p in points) {
    final DateTime start = p.at.subtract(
      const Duration(minutes: hoursAfterBaselineMinutes),
    );
    final DateTime end = p.at.add(
      Duration(minutes: hoursAfterWindows.last.end),
    );
    final DateTime day = startOfDay(p.at);
    final ({DateTime start, DateTime end})? seen = byDay[day];
    byDay[day] = seen == null
        ? (start: start, end: end)
        : (
            start: start.isBefore(seen.start) ? start : seen.start,
            end: end.isAfter(seen.end) ? end : seen.end,
          );
  }
  final List<({DateTime start, DateTime end})> spans = byDay.values.toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  final List<({DateTime start, DateTime end})> merged =
      <({DateTime start, DateTime end})>[];
  for (final ({DateTime start, DateTime end}) s in spans) {
    if (merged.isNotEmpty && !s.start.isAfter(merged.last.end)) {
      final ({DateTime start, DateTime end}) last = merged.removeLast();
      merged.add((
        start: last.start,
        end: s.end.isAfter(last.end) ? s.end : last.end,
      ));
    } else {
      merged.add(s);
    }
  }
  return merged;
}

// Whether sorted [times] holds one from [from] up to [to].
bool _anyIn(List<DateTime> times, DateTime from, DateTime to) {
  int low = 0, high = times.length;
  while (low < high) {
    final int mid = (low + high) >> 1;
    if (times[mid].isBefore(from)) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low < times.length && times[low].isBefore(to);
}

// Sorted by start; binary search for the first at or after [t].
int _firstFrom(List<HealthSample> samples, DateTime t) {
  int low = 0, high = samples.length;
  while (low < high) {
    final int mid = (low + high) >> 1;
    if (samples[mid].start.isBefore(t)) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low;
}

// Instant readings, so a sample counts where it starts.
List<double> _values(List<HealthSample> samples, DateTime from, DateTime to) {
  final List<double> out = <double>[];
  for (int i = _firstFrom(samples, from); i < samples.length; i++) {
    if (!samples[i].start.isBefore(to)) break;
    out.add(samples[i].value);
  }
  return out;
}

// Step samples are counts over an interval, shared out by overlap. iPhone and
// Watch both record steps and raw samples are not merged, so a span both
// carried counts twice: too high, never too low, which errs towards leaving a
// window out.
double _stepsPerMinute(
  List<HealthSample> steps,
  DateTime from,
  DateTime to, {
  required int longestMinutes,
}) {
  double total = 0;
  final DateTime searchFrom = from.subtract(Duration(minutes: longestMinutes));
  for (int i = _firstFrom(steps, searchFrom); i < steps.length; i++) {
    final HealthSample s = steps[i];
    if (!s.start.isBefore(to)) break;
    final DateTime a = s.start.isAfter(from) ? s.start : from;
    final DateTime b = s.end.isBefore(to) ? s.end : to;
    final int length = s.end.difference(s.start).inMicroseconds;
    if (length == 0) {
      if (!s.start.isBefore(from)) total += s.value;
      continue;
    }
    final int overlap = b.difference(a).inMicroseconds;
    if (overlap > 0) total += s.value * overlap / length;
  }
  return total / to.difference(from).inMinutes;
}

/// For each habit in [plan], what each of [hoursAfterMetrics] does in each of
/// [hoursAfterWindows] after a use: the window's mean less the hour before
/// the use, on the days of use, against the same difference at the same clock
/// times on the control days.
///
/// The hour before takes out the day's level (a poor night, a cold); the
/// control at the same clock time takes out the time of day, since heart rate
/// climbs through a morning with or without coffee. Either alone fails one of
/// those. A moment is left out when another habit was used from its baseline
/// to its window's end, when its baseline or window holds under
/// [HoursAfterGates.minSamples] readings, or when either was walked through
/// faster than [HoursAfterGates.maxStepsPerMinute]; the change in steps per
/// minute between them is in the model when it varies.
///
/// Samples within a day are not independent, so moments are averaged per day
/// and the model is fitted on days: one row per day of use and per control
/// day (a day can be both, for different moments), the outcome on an
/// intercept, a use indicator and the change in steps. Results join the
/// report's false-discovery family.
List<HabitInsight> hoursAfter({
  required HoursAfterPlan plan,
  required List<HabitUse> uses,
  required Map<String, List<HealthSample>> samples,
  HoursAfterGates gates = const HoursAfterGates(),
}) {
  final Map<String, List<DateTime>> usesOf = <String, List<DateTime>>{};
  for (final HabitUse u in uses) {
    if (u.amount <= 0) continue;
    usesOf.putIfAbsent(u.habitId, () => []).add(u.at);
  }
  for (final List<DateTime> t in usesOf.values) {
    t.sort();
  }
  final List<HealthSample> steps =
      samples[HealthSampleMetric.stepCount.id] ?? const <HealthSample>[];
  int longestStep = 0;
  for (final HealthSample s in steps) {
    longestStep = max(longestStep, s.end.difference(s.start).inMinutes + 1);
  }
  final Map<String, List<HoursAfterPoint>> byHabit =
      <String, List<HoursAfterPoint>>{};
  for (final HoursAfterPoint p in plan.points) {
    byHabit.putIfAbsent(p.habitId, () => []).add(p);
  }
  final List<String> ids = byHabit.keys.toList()..sort();
  final List<HabitInsight> out = <HabitInsight>[];
  for (final HealthSampleMetric metric in hoursAfterMetrics) {
    final List<HealthSample> readings =
        samples[metric.id] ?? const <HealthSample>[];
    // No readings at all is no such device, not too few uses.
    if (readings.isEmpty) continue;
    for (final String id in ids) {
      bool otherUseIn(DateTime from, DateTime to) {
        for (final MapEntry<String, List<DateTime>> e in usesOf.entries) {
          if (e.key != id && _anyIn(e.value, from, to)) return true;
        }
        return false;
      }

      for (final HourWindow w in hoursAfterWindows) {
        // Per day and side: the sums of the change and of the steps change.
        final Map<(DateTime, bool), List<double>> days =
            <(DateTime, bool), List<double>>{};
        for (final HoursAfterPoint p in byHabit[id]!) {
          final DateTime baseFrom = p.at.subtract(
            const Duration(minutes: hoursAfterBaselineMinutes),
          );
          final DateTime from = p.at.add(Duration(minutes: w.start));
          final DateTime to = p.at.add(Duration(minutes: w.end));
          if (otherUseIn(baseFrom, to)) continue;
          final List<double> before = _values(readings, baseFrom, p.at);
          final List<double> after = _values(readings, from, to);
          if (before.length < gates.minSamples ||
              after.length < gates.minSamples) {
            continue;
          }
          final double stepsBefore = _stepsPerMinute(
            steps,
            baseFrom,
            p.at,
            longestMinutes: longestStep,
          );
          final double stepsAfter = _stepsPerMinute(
            steps,
            from,
            to,
            longestMinutes: longestStep,
          );
          if (stepsBefore > gates.maxStepsPerMinute ||
              stepsAfter > gates.maxStepsPerMinute) {
            continue;
          }
          final List<double> sums = days.putIfAbsent((
            startOfDay(p.at),
            p.control,
          ), () => <double>[0, 0, 0]);
          sums[0] += mean(after) - mean(before);
          sums[1] += stepsAfter - stepsBefore;
          sums[2] += 1;
        }
        out.add(
          _judge(
            id,
            metric,
            w,
            days.entries.toList()..sort((a, b) => a.key.$1.compareTo(b.key.$1)),
            gates,
          ),
        );
      }
    }
  }
  return out;
}

HabitInsight _judge(
  String id,
  HealthSampleMetric metric,
  HourWindow window,
  List<MapEntry<(DateTime, bool), List<double>>> days,
  HoursAfterGates gates,
) {
  final List<double> y = <double>[];
  final List<double> used = <double>[];
  final List<double> steps = <double>[];
  for (final MapEntry<(DateTime, bool), List<double>> d in days) {
    y.add(d.value[0] / d.value[2]);
    steps.add(d.value[1] / d.value[2]);
    used.add(d.key.$2 ? 0 : 1);
  }
  final int exposed = used.where((v) => v == 1).length;
  HabitRefusal refuse(
    RefusalReason reason, {
    double? effect,
    Interval? interval,
    double? pValue,
  }) => HabitRefusal(
    habitId: id,
    metricId: metric.id,
    lagDays: 0,
    usableDays: y.length,
    exposedDays: exposed,
    raw: null,
    kind: InsightKind.hoursAfter,
    window: window,
    reason: reason,
    effect: effect,
    interval: interval,
    pValue: pValue,
  );
  if (exposed < gates.minEventDays ||
      y.length - exposed < gates.minControlDays) {
    return refuse(RefusalReason.tooFewDays);
  }
  final bool withSteps = sampleVariance(steps) > 1e-9;
  final LinearFit? fit = fitLeastSquares(<List<double>>[
    for (int r = 0; r < y.length; r++)
      <double>[1, used[r], if (withSteps) steps[r]],
  ], y);
  if (fit == null) return refuse(RefusalReason.tooFewDays);
  final double effect = fit.coefficients[1];
  final Interval interval = fit.interval(1, level: gates.level);
  final double p = fit.pValue(1);
  if (interval.crossesZero) {
    return refuse(
      RefusalReason.withinNoise,
      effect: effect,
      interval: interval,
      pValue: p,
    );
  }
  final double sd = sqrt(sampleVariance(y));
  return HabitFinding(
    habitId: id,
    metricId: metric.id,
    lagDays: 0,
    usableDays: y.length,
    exposedDays: exposed,
    raw: null,
    kind: InsightKind.hoursAfter,
    window: window,
    effect: effect,
    interval: interval,
    standardized: sd == 0 ? 0 : effect / sd,
    pValue: p,
  );
}
