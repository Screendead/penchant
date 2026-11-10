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

/// How far a control day's waking may be from its use day's, in minutes: the
/// control sits as long after waking as the use, and within this of its
/// clock time.
const int hoursAfterMaxWakeShiftMinutes = 120;

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
    this.maxStepsPerMinute = 60,
    this.activityLingerMinutes = 30,
    this.level = 0.95,
  });

  /// In the baseline and in the window, each.
  final int minSamples;
  final int minEventDays;
  final int minControlDays;

  /// A moment is left out for a window when any 10 minutes of its baseline,
  /// or from [activityLingerMinutes] before the window to its end, averaged
  /// more steps a minute than this: the heart rate then says how far you
  /// walked, and it stays up for a while after.
  final double maxStepsPerMinute;
  final int activityLingerMinutes;
  final double level;
}

/// One moment [hoursAfter] measures around: a use, or as long after waking
/// on a nearby day clear of the habit.
class HoursAfterPoint {
  const HoursAfterPoint(this.habitId, this.at, {required this.control});

  final String habitId;
  final DateTime at;
  final bool control;
}

class HoursAfterPlan {
  const HoursAfterPlan(
    this.points,
    this.reads, {
    this.useDays = const <String, int>{},
    this.dropped = const <String, Map<(HoursAfterShortfall, bool), int>>{},
  });

  final List<HoursAfterPoint> points;

  /// The spans to read samples for, oldest first, none overlapping: one per
  /// day with a point at most, so a year costs at most a call a day per
  /// measure (more only when a day's span holds over a page).
  final List<({DateTime start, DateTime end})> reads;

  /// Per habit, the days with a use clear of it in the 4 hours before.
  final Map<String, int> useDays;

  /// Per habit, the moments left out before any sample was read, by cause
  /// and whether a control: a use without a known waking or too near sleep,
  /// and ([HoursAfterShortfall.controls]) a use no control was found for.
  final Map<String, Map<(HoursAfterShortfall, bool), int>> dropped;
}

/// When the person was in bed, from [HealthSampleMetric.bed].
class _Bed {
  _Bed(List<HealthSample> spans)
    : _spans = List<HealthSample>.of(spans)
        ..sort((a, b) => a.start.compareTo(b.start));

  final List<HealthSample> _spans;

  /// The end of the longest span ending from 18:00 the evening before [day]
  /// up to 15:00 on it: the main sleep, not a nap.
  DateTime? wake(DateTime day) {
    final DateTime from = DateTime(day.year, day.month, day.day - 1, 18);
    final DateTime to = DateTime(day.year, day.month, day.day, 15);
    HealthSample? main;
    for (final HealthSample s in _spans) {
      if (!s.end.isAfter(from) || s.end.isAfter(to)) continue;
      if (main == null ||
          s.end.difference(s.start) > main.end.difference(main.start)) {
        main = s;
      }
    }
    return main?.end;
  }

  /// Null when [at]'s hour before and every window fall after [wake] and
  /// clear of bed.
  HoursAfterShortfall? check(DateTime at, DateTime? wake) {
    if (wake == null) return HoursAfterShortfall.noSleep;
    final DateTime from = at.subtract(
      const Duration(minutes: hoursAfterBaselineMinutes),
    );
    final DateTime to = at.add(Duration(minutes: hoursAfterWindows.last.end));
    if (wake.isAfter(from)) return HoursAfterShortfall.nearSleep;
    for (final HealthSample s in _spans) {
      if (!s.start.isBefore(to)) break;
      if (s.end.isAfter(from)) return HoursAfterShortfall.nearSleep;
    }
    return null;
  }
}

/// Which moments to measure and which samples to read for them, from [uses]
/// up to [through] (exclusive), given when the person was in [bed]. Each
/// habit's events are its uses with none of it in the
/// [hoursAfterClearMinutes] before and every window ended by [through], from
/// the last [hoursAfterLookbackDays] days, at most [hoursAfterMaxEvents] of
/// them, most recent first.
///
/// Heart rate climbs for a while after waking, whatever the clock says, so
/// a moment is placed by its time since that day's waking (the end of its
/// main sleep): an event needs a known waking before its hour before, and no
/// time in bed from then to its last window's end. Each event gets one
/// control: as long after waking on the nearest day within
/// [hoursAfterControlReachDays] whose waking is within
/// [hoursAfterMaxWakeShiftMinutes] of the event's, under the same sleep
/// condition, with no use of the habit within [hoursAfterClearMinutes] either
/// side of it, inside the habit's span from its first use to its last. A day
/// with the habit at another time can serve, so a habit used every day still
/// has controls unless it is used at nearly the same time every day.
HoursAfterPlan planHoursAfter(
  List<HabitUse> uses,
  DateTime through, {
  List<HealthSample> bed = const <HealthSample>[],
}) {
  final _Bed sleep = _Bed(bed);
  final DateTime since = addDays(startOfDay(through), -hoursAfterLookbackDays);
  final Map<String, List<DateTime>> byHabit = <String, List<DateTime>>{};
  for (final HabitUse u in uses) {
    if (u.amount > 0) byHabit.putIfAbsent(u.habitId, () => []).add(u.at);
  }
  const Duration clear = Duration(minutes: hoursAfterClearMinutes);
  final Duration last = Duration(minutes: hoursAfterWindows.last.end);
  const Duration maxShift = Duration(minutes: hoursAfterMaxWakeShiftMinutes);
  final List<HoursAfterPoint> points = <HoursAfterPoint>[];
  final Map<String, int> useDays = <String, int>{};
  final Map<String, Map<(HoursAfterShortfall, bool), int>> dropped =
      <String, Map<(HoursAfterShortfall, bool), int>>{};
  final List<String> ids = byHabit.keys.toList()..sort();
  for (final String id in ids) {
    final List<DateTime> times = byHabit[id]!..sort();
    bool clearAround(DateTime at, Duration before, Duration after) =>
        !anyTimeIn(times, at.subtract(before), at.add(after));
    final Map<(HoursAfterShortfall, bool), int> drops = dropped[id] =
        <(HoursAfterShortfall, bool), int>{};
    void drop(HoursAfterShortfall why, {required bool control}) =>
        drops[(why, control)] = (drops[(why, control)] ?? 0) + 1;

    final List<DateTime> events = <DateTime>[
      for (int i = times.length - 1; i >= 0; i--)
        if (!times[i].isBefore(since) &&
            !times[i].add(last).isAfter(through) &&
            clearAround(times[i], clear, Duration.zero))
          times[i],
    ].take(hoursAfterMaxEvents).toList();
    useDays[id] = events.map(startOfDay).toSet().length;
    final Set<DateTime> taken = <DateTime>{};
    for (final DateTime at in events) {
      final DateTime day = startOfDay(at);
      final DateTime? wake = sleep.wake(day);
      if (sleep.check(at, wake) case final HoursAfterShortfall why) {
        drop(why, control: false);
        continue;
      }
      points.add(HoursAfterPoint(id, at, control: false));
      final Duration sinceWake = at.difference(wake!);
      bool found = false;
      for (int k = 1; k <= 2 * hoursAfterControlReachDays; k++) {
        final int offset = k.isOdd ? -(k + 1) ~/ 2 : k ~/ 2;
        final DateTime other = addDays(day, offset);
        final DateTime? otherWake = sleep.wake(other);
        if (otherWake == null) continue;
        final Duration shift = otherWake.difference(
          DateTime(
            wake.year,
            wake.month,
            wake.day + offset,
            wake.hour,
            wake.minute,
            wake.second,
          ),
        );
        if (shift.abs() > maxShift) continue;
        final DateTime p = otherWake.add(sinceWake);
        // Days before the first logged use or after the last are not days
        // clear of it: it may have gone unlogged.
        if (p.add(last).isAfter(through) ||
            p.isBefore(since) ||
            p.isBefore(startOfDay(times.first)) ||
            !p.isBefore(times.last) ||
            taken.contains(p) ||
            !clearAround(p, clear, clear) ||
            sleep.check(p, otherWake) != null) {
          continue;
        }
        taken.add(p);
        points.add(HoursAfterPoint(id, p, control: true));
        found = true;
        break;
      }
      if (!found) drop(HoursAfterShortfall.controls, control: true);
    }
  }
  return HoursAfterPlan(
    points,
    _reads(points),
    useDays: useDays,
    dropped: dropped,
  );
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
bool anyTimeIn(List<DateTime> times, DateTime from, DateTime to) {
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
List<double> readingsIn(List<HealthSample> samples, DateTime from, DateTime to) {
  final List<double> out = <double>[];
  for (int i = _firstFrom(samples, from); i < samples.length; i++) {
    if (!samples[i].start.isBefore(to)) break;
    out.add(samples[i].value);
  }
  return out;
}

const Duration _bin = Duration(minutes: 10);

// Step samples are counts over an interval, shared out by overlap. iPhone and
// Watch both record steps and raw samples are not merged, so a span both
// carried counts twice: too high, never too low, which errs towards leaving a
// window out.
double stepsPerMinute(
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
/// the use, on the days of use, against the same difference as long after
/// waking on the control days.
///
/// The hour before takes out the day's level (a poor night, a cold); the
/// control as long after waking takes out the climb through a morning, which
/// follows waking more than the clock. Either alone fails one of those. A
/// moment is left out when another habit was used from its baseline to its
/// window's end, when the habit was used again before the window's end,
/// when its baseline or window holds under
/// [HoursAfterGates.minSamples] readings, or when it holds a walk (see
/// [HoursAfterGates.maxStepsPerMinute]); the change in steps per minute
/// between window and baseline is in the model when it varies.
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
  // A habit whose every use was left out in planning is refused in words.
  final List<String> ids = <String>{
    ...byHabit.keys,
    for (final MapEntry<String, int> e in plan.useDays.entries)
      if (e.value > 0) e.key,
  }.toList()..sort();
  final List<HabitInsight> out = <HabitInsight>[];
  for (final HealthSampleMetric metric in hoursAfterMetrics) {
    final List<HealthSample> readings =
        samples[metric.id] ?? const <HealthSample>[];
    // No readings at all is no such device, not too few uses.
    if (readings.isEmpty) continue;
    for (final String id in ids) {
      bool otherUseIn(DateTime from, DateTime to) {
        for (final MapEntry<String, List<DateTime>> e in usesOf.entries) {
          if (e.key != id && anyTimeIn(e.value, from, to)) return true;
        }
        return false;
      }

      final List<DateTime> own = usesOf[id] ?? const <DateTime>[];
      for (final HourWindow w in hoursAfterWindows) {
        // Per day and side: the sums of the change and of the steps change.
        final Map<(DateTime, bool), List<double>> days =
            <(DateTime, bool), List<double>>{};
        final Map<(HoursAfterShortfall, bool), int> drops =
            <(HoursAfterShortfall, bool), int>{...?plan.dropped[id]};
        void drop(HoursAfterShortfall why, HoursAfterPoint p) =>
            drops[(why, p.control)] = (drops[(why, p.control)] ?? 0) + 1;
        for (final HoursAfterPoint p
            in byHabit[id] ?? const <HoursAfterPoint>[]) {
          final DateTime baseFrom = p.at.subtract(
            const Duration(minutes: hoursAfterBaselineMinutes),
          );
          final DateTime from = p.at.add(Duration(minutes: w.start));
          final DateTime to = p.at.add(Duration(minutes: w.end));
          if (otherUseIn(baseFrom, to)) {
            drop(HoursAfterShortfall.otherHabit, p);
            continue;
          }
          if (anyTimeIn(own, p.at.add(const Duration(microseconds: 1)), to)) {
            drop(HoursAfterShortfall.sameHabit, p);
            continue;
          }
          final List<double> before = readingsIn(readings, baseFrom, p.at);
          final List<double> after = readingsIn(readings, from, to);
          if (before.length < gates.minSamples ||
              after.length < gates.minSamples) {
            drop(HoursAfterShortfall.readings, p);
            continue;
          }
          final double stepsBefore = stepsPerMinute(
            steps,
            baseFrom,
            p.at,
            longestMinutes: longestStep,
          );
          final double stepsAfter = stepsPerMinute(
            steps,
            from,
            to,
            longestMinutes: longestStep,
          );
          final DateTime lingerFrom = from.subtract(
            Duration(minutes: gates.activityLingerMinutes),
          );
          bool walked(DateTime a, DateTime b) {
            for (DateTime t = a; t.isBefore(b); t = t.add(_bin)) {
              final DateTime end = t.add(_bin).isBefore(b) ? t.add(_bin) : b;
              if (stepsPerMinute(steps, t, end, longestMinutes: longestStep) >
                  gates.maxStepsPerMinute) {
                return true;
              }
            }
            return false;
          }

          if (steps.isNotEmpty &&
              (walked(baseFrom, p.at) ||
                  walked(lingerFrom.isBefore(p.at) ? p.at : lingerFrom, to))) {
            drop(HoursAfterShortfall.walk, p);
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
            useDays: plan.useDays[id] ?? 0,
            drops: drops,
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
  HoursAfterGates gates, {
  required int useDays,
  required Map<(HoursAfterShortfall, bool), int> drops,
}) {
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
    HoursAfterShortfall? shortfall,
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
    shortfall: shortfall,
  );
  // The cause that left out the most moments on that side.
  HoursAfterShortfall worst({required bool control}) {
    HoursAfterShortfall? most;
    int count = 0;
    for (final MapEntry<(HoursAfterShortfall, bool), int> e in drops.entries) {
      if (e.key.$2 == control && e.value > count) {
        most = e.key.$1;
        count = e.value;
      }
    }
    return most ??
        (control ? HoursAfterShortfall.controls : HoursAfterShortfall.uses);
  }

  if (exposed < gates.minEventDays) {
    return refuse(
      RefusalReason.tooFewDays,
      shortfall: useDays < gates.minEventDays
          ? HoursAfterShortfall.uses
          : worst(control: false),
    );
  }
  if (y.length - exposed < gates.minControlDays) {
    return refuse(RefusalReason.tooFewDays, shortfall: worst(control: true));
  }
  final bool withSteps = sampleVariance(steps) > 1e-9;
  final LinearFit? fit = fitLeastSquares(<List<double>>[
    for (int r = 0; r < y.length; r++)
      <double>[1, used[r], if (withSteps) steps[r]],
  ], y);
  if (fit == null) {
    return refuse(
      RefusalReason.tooFewDays,
      shortfall: HoursAfterShortfall.controls,
    );
  }
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
