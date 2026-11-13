import 'dart:convert';
import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart' show lateUseCutoffHour;
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/what_follows.dart';

/// A self-experiment: on days picked at random, none of a habit from
/// [ExperimentPlan.fromHour]; on the others, as usual. The finding's measure
/// on the nights (or days) after each kind is then compared, every planned
/// day counted where it was planned, kept or not (intention to treat).

/// The rule's hour: none of the habit from 18:00 on a "none" day.
const int experimentFromHour = 18;

/// The lengths offered, in weeks.
const List<int> experimentLengths = <int>[2, 4, 6, 8];
const int experimentDefaultWeeks = 6;

/// What "Run it 4 more weeks" adds.
const int experimentExtendWeeks = 4;

/// The notification's default time, before the evening the rule covers.
const int experimentDefaultNotifyMinutes = 17 * 60 + 30;

const Set<MetricFamily> _testable = <MetricFamily>{
  MetricFamily.sleep,
  MetricFamily.heart,
  MetricFamily.activity,
};

/// Whether [finding] can be tested: a day-with-against-day-without finding
/// on a sleep, heart or activity measure read after the day, shown in
/// numbers.
bool canExperiment(HabitFinding finding) {
  if (finding.kind != InsightKind.use || finding.lagDays < 1) return false;
  if (!_testable.contains(metricFloors[finding.metricId]?.family)) {
    return false;
  }
  final MetricCopy? copy = metricCopy(finding.metricId);
  return copy != null && !copy.inWords && copy.unit.isNotEmpty;
}

// mulberry32, so a stored seed gives the same days on every build: dart:math's
// Random promises no sequence across SDK versions.
class _Draws {
  _Draws(int seed) : _state = seed & 0xFFFFFFFF;

  int _state;

  int _next() {
    _state = (_state + 0x6D2B79F5) & 0xFFFFFFFF;
    int t = _state;
    t = ((t ^ (t >>> 15)) * (t | 1)) & 0xFFFFFFFF;
    t ^= (t + (((t ^ (t >>> 7)) * (t | 61)) & 0xFFFFFFFF)) & 0xFFFFFFFF;
    return (t ^ (t >>> 14)) & 0xFFFFFFFF;
  }

  int below(int n) => _next() % n;
}

// Each pair of weeks, and each week, draws from its own stream, so adding
// weeks never changes the days already planned.
int _stream(int seed, int index, int salt) =>
    (seed ^ ((index + 1) * 0x9E3779B9) ^ (salt * 0x85EBCA6B)) & 0xFFFFFFFF;

/// Whether each day of week [week] is a "none" day: 3 or 4 of them, at
/// random places, and of each pair of weeks one has 4 and the other 3, so the
/// plan is half and half and weekends fall on both sides.
List<bool> experimentWeek(int seed, int week) {
  final bool firstHasFour = _Draws(_stream(seed, week ~/ 2, 1)).below(2) == 0;
  final int none = (week.isEven == firstHasFour) ? 4 : 3;
  final List<bool> days = <bool>[for (int i = 0; i < 7; i++) i < none];
  final _Draws draws = _Draws(_stream(seed, week, 2));
  for (int i = 6; i > 0; i--) {
    final int j = draws.below(i + 1);
    final bool swap = days[i];
    days[i] = days[j];
    days[j] = swap;
  }
  return days;
}

/// A seed for a new plan.
int newExperimentSeed([Random? random]) =>
    (random ?? Random.secure()).nextInt(1 << 32);

/// What the plan tests and when. The days come from [seed]; nothing else
/// about them is stored. [weekStarts] holds each week's first day, so a plan
/// run on for more weeks continues from the day it was extended.
class ExperimentPlan {
  const ExperimentPlan({
    required this.habitId,
    required this.metricId,
    required this.lagDays,
    required this.seed,
    required this.weekStarts,
    required this.finding,
    this.fromHour = experimentFromHour,
    this.notifyMinutes,
  });

  /// Starting the day after [today], for [weeks] weeks.
  factory ExperimentPlan.start(
    HabitFinding finding, {
    required DateTime today,
    required int weeks,
    required int seed,
    int? notifyMinutes,
  }) => ExperimentPlan(
    habitId: finding.habitId,
    metricId: finding.metricId,
    lagDays: finding.lagDays,
    seed: seed,
    weekStarts: _weeksFrom(addDays(startOfDay(today), 1), weeks),
    finding: finding.interval.low == finding.interval.high
        ? (effect: finding.effect, low: finding.effect, high: finding.effect)
        : (
            effect: finding.effect,
            low: finding.interval.low,
            high: finding.interval.high,
          ),
    notifyMinutes: notifyMinutes,
  );

  final String habitId;
  final String metricId;
  final int lagDays;
  final int seed;
  final List<DateTime> weekStarts;
  final int fromHour;

  /// Minutes after midnight for the daily notification; null when off.
  final int? notifyMinutes;

  /// The finding tested: the measure after a day with the habit less after
  /// one without, and its range.
  final ({double effect, double low, double high}) finding;

  int get weeks => weekStarts.length;
  int get days => weeks * 7;
  DateTime get start => weekStarts.first;
  DateTime get end => addDays(weekStarts.last, 6);

  /// The last day whose measure the plan reads.
  DateTime get lastOutcomeDay => addDays(end, lagDays);

  /// Every planned day in order, with whether it is a "none" day.
  List<({DateTime day, bool none})> get schedule => <({DateTime day, bool none})>[
    for (final (int w, DateTime from) in weekStarts.indexed)
      for (final (int i, bool none) in experimentWeek(seed, w).indexed)
        (day: addDays(from, i), none: none),
  ];

  /// [day]'s place in the plan from 0, or null when it is not a planned day.
  int? indexOf(DateTime day) {
    final DateTime d = startOfDay(day);
    for (final (int w, DateTime from) in weekStarts.indexed) {
      final int i = daysBetween(from, d);
      if (i >= 0 && i < 7) return w * 7 + i;
    }
    return null;
  }

  /// Whether [day] is a planned "none" day; null when it is not planned.
  bool? noneOn(DateTime day) {
    final int? i = indexOf(day);
    if (i == null) return null;
    return experimentWeek(seed, i ~/ 7)[i % 7];
  }

  /// Every planned day and the last measure after it are in by [today]: a
  /// night's sleep is in by the morning it ends, a day's measure the day
  /// after.
  bool finishedBy(DateTime today, {required bool night}) {
    final int left = daysBetween(startOfDay(today), lastOutcomeDay);
    return night ? left <= 0 : left < 0;
  }

  int get noneDays => <bool>[
    for (int w = 0; w < weeks; w++) ...experimentWeek(seed, w),
  ].where((bool n) => n).length;

  /// [extra] weeks more, from the day after [today] or straight after the
  /// plan when it is still running.
  ExperimentPlan extended(int extra, {required DateTime today}) {
    final DateTime next = addDays(end, 1);
    final DateTime tomorrow = addDays(startOfDay(today), 1);
    return copyWith(
      weekStarts: <DateTime>[
        ...weekStarts,
        ..._weeksFrom(next.isAfter(tomorrow) ? next : tomorrow, extra),
      ],
    );
  }

  ExperimentPlan copyWith({
    List<DateTime>? weekStarts,
    int? Function()? notifyMinutes,
  }) => ExperimentPlan(
    habitId: habitId,
    metricId: metricId,
    lagDays: lagDays,
    seed: seed,
    weekStarts: weekStarts ?? this.weekStarts,
    finding: finding,
    fromHour: fromHour,
    notifyMinutes: notifyMinutes == null ? this.notifyMinutes : notifyMinutes(),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'habitId': habitId,
    'metricId': metricId,
    'lagDays': lagDays,
    'seed': seed,
    'weekStarts': <String>[for (final DateTime d in weekStarts) _date(d)],
    'fromHour': fromHour,
    'notifyMinutes': notifyMinutes,
    'finding': <double>[finding.effect, finding.low, finding.high],
  };

  /// Null for anything not written by [toJson].
  static ExperimentPlan? fromJson(Object? json) {
    try {
      if (json is! Map<String, Object?>) return null;
      final List<DateTime> weeks = <DateTime>[
        for (final Object? d in json['weekStarts']! as List<Object?>)
          DateTime.parse(d! as String),
      ];
      final List<num> f = <num>[
        for (final Object? v in json['finding']! as List<Object?>) v! as num,
      ];
      if (weeks.isEmpty || f.length != 3) return null;
      return ExperimentPlan(
        habitId: json['habitId']! as String,
        metricId: json['metricId']! as String,
        lagDays: json['lagDays']! as int,
        seed: json['seed']! as int,
        weekStarts: weeks,
        fromHour: json['fromHour']! as int,
        notifyMinutes: json['notifyMinutes'] as int?,
        finding: (
          effect: f[0].toDouble(),
          low: f[1].toDouble(),
          high: f[2].toDouble(),
        ),
      );
    } catch (_) {
      return null;
    }
  }
}

List<DateTime> _weeksFrom(DateTime first, int weeks) => <DateTime>[
  for (int w = 0; w < weeks; w++) addDays(first, w * 7),
];

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The plan running, if any (one at a time), and the finished ones, newest
/// first.
class ExperimentStore {
  const ExperimentStore({
    this.active,
    this.finished = const <ExperimentPlan>[],
  });

  static const ExperimentStore empty = ExperimentStore();

  /// Finished plans kept for their result cards.
  static const int keep = 5;

  final ExperimentPlan? active;
  final List<ExperimentPlan> finished;

  /// [active] moved to [finished] once its last measure is in.
  ExperimentStore settled(DateTime today) {
    final ExperimentPlan? plan = active;
    if (plan == null) return this;
    final MetricCopy? copy = metricCopy(plan.metricId);
    if (!plan.finishedBy(today, night: copy?.night ?? true)) return this;
    return ExperimentStore(
      finished: <ExperimentPlan>[plan, ...finished].take(keep).toList(),
    );
  }

  List<int> encode() => utf8.encode(
    jsonEncode(<String, Object?>{
      'v': 1,
      'active': active?.toJson(),
      'finished': <Object?>[for (final ExperimentPlan p in finished) p.toJson()],
    }),
  );

  /// [empty] for anything unreadable.
  static ExperimentStore decode(List<int> bytes) {
    try {
      final Object? json = jsonDecode(utf8.decode(bytes));
      if (json is! Map<String, Object?> || json['v'] != 1) return empty;
      return ExperimentStore(
        active: ExperimentPlan.fromJson(json['active']),
        finished: <ExperimentPlan>[
          for (final Object? p in json['finished']! as List<Object?>)
            ?ExperimentPlan.fromJson(p),
        ],
      );
    } catch (_) {
      return empty;
    }
  }
}

enum ExperimentDay {
  none,
  usual,

  /// A "none" day with the habit logged in its evening; still counted as a
  /// "none" day.
  missed,
}

/// A finished plan's comparison.
class ExperimentResult {
  const ExperimentResult({
    required this.difference,
    required this.interval,
    required this.noneValues,
    required this.usualValues,
    required this.missing,
    required this.days,
  });

  /// The mean after "none" days less the mean after "as usual" days.
  final double difference;

  /// A 95% Welch interval for [difference]; null with under 2 values on
  /// either side.
  final Interval? interval;
  final int noneValues;
  final int usualValues;

  /// Planned days with no measure after them.
  final int missing;
  final List<ExperimentDay> days;

  int get values => noneValues + usualValues;
  int get missed => days.where((ExperimentDay d) => d == ExperimentDay.missed).length;
  int get kept => days.length - missed;

  /// The range leaves out zero.
  bool get clear => interval != null && !interval!.crossesZero;
}

/// Whether a use at [at] falls in the evening [day]'s rule covers: from
/// [fromHour] to [lateUseCutoffHour] the morning after.
bool inExperimentEvening(DateTime at, DateTime day, int fromHour) {
  final DateTime evening = startOfDay(day);
  final DateTime from = DateTime(
    evening.year,
    evening.month,
    evening.day,
    fromHour,
  );
  final DateTime to = DateTime(
    evening.year,
    evening.month,
    evening.day + 1,
    lateUseCutoffHour,
  );
  return !at.isBefore(from) && at.isBefore(to);
}

/// [plan] compared from [outcomes] (its measure by local day) and [uses]
/// (the habit's entries with a positive amount). Every planned day counts
/// where it was planned, whatever was logged.
ExperimentResult analyseExperiment(
  ExperimentPlan plan, {
  required Map<DateTime, double> outcomes,
  required Iterable<DateTime> uses,
}) {
  final List<DateTime> times = uses.toList();
  final List<double> none = <double>[], usual = <double>[];
  final List<ExperimentDay> days = <ExperimentDay>[];
  int missing = 0;
  for (final ({DateTime day, bool none}) d in plan.schedule) {
    final bool broke =
        d.none &&
        times.any((DateTime t) => inExperimentEvening(t, d.day, plan.fromHour));
    days.add(
      !d.none
          ? ExperimentDay.usual
          : broke
          ? ExperimentDay.missed
          : ExperimentDay.none,
    );
    final double? value = outcomes[addDays(d.day, plan.lagDays)];
    if (value == null) {
      missing++;
    } else {
      (d.none ? none : usual).add(value);
    }
  }
  final double difference = none.isEmpty || usual.isEmpty
      ? 0
      : mean(none) - mean(usual);
  return ExperimentResult(
    difference: difference,
    interval: welchInterval(none, usual),
    noneValues: none.length,
    usualValues: usual.length,
    missing: missing,
    days: days,
  );
}

/// A [level] Welch interval for mean([a]) less mean([b]); null with under 2
/// values on either side.
Interval? welchInterval(List<double> a, List<double> b, {double level = 0.95}) {
  if (a.length < 2 || b.length < 2) return null;
  final double d = mean(a) - mean(b);
  final double va = sampleVariance(a) / a.length;
  final double vb = sampleVariance(b) / b.length;
  final double se2 = va + vb;
  if (se2 == 0) return Interval(d, d);
  final double df =
      se2 * se2 / (va * va / (a.length - 1) + vb * vb / (b.length - 1));
  final double half = studentTQuantile(0.5 + level / 2, df) * sqrt(se2);
  return Interval(d - half, d + half);
}

/// The 95% range's half-width to expect from [weeks] weeks, half the days
/// each way, for a measure whose values spread by [spread] (a standard
/// deviation): t(2n - 2) × spread × √(2 / n).
double expectedHalfWidth(double spread, int weeks) {
  final int n = weeks * 7 ~/ 2;
  return studentTQuantile(0.975, 2 * n - 2.0) * spread * sqrt(2 / n);
}

/// About how often [weeks] weeks would give a range clear of zero if the true
/// difference were [effect]: the t approximation P(T > t₀.₉₇₅ − |effect| / se).
double expectedPower(double effect, double spread, int weeks) {
  final int n = weeks * 7 ~/ 2;
  final double df = 2 * n - 2.0;
  final double se = spread * sqrt(2 / n);
  if (se == 0) return 1;
  return studentTCdf(effect.abs() / se - studentTQuantile(0.975, df), df);
}

/// Nights (or days) needed to judge the spread.
const int experimentSpreadMinValues = 14;

/// The measure's standard deviation over the [days] days to [today]; null
/// with under [experimentSpreadMinValues] values.
double? experimentSpread(
  Map<DateTime, double> values,
  DateTime today, {
  int days = 90,
}) {
  final DateTime from = addDays(startOfDay(today), -days);
  final List<double> recent = <double>[
    for (final MapEntry<DateTime, double> e in values.entries)
      if (!e.key.isBefore(from) && !e.key.isAfter(today)) e.value,
  ];
  if (recent.length < experimentSpreadMinValues) return null;
  return sqrt(sampleVariance(recent));
}

/// The first notification's id; one per planned day after it, so a
/// reschedule replaces each day's rather than adding another.
const int experimentNoticeBase = 1000;

/// The most notifications kept scheduled at once (iOS keeps 64 per app),
/// topped up whenever the app opens.
const int experimentNoticesAhead = 7;

typedef ExperimentNotice = ({int id, DateTime at, String title, String body});

/// The next [experimentNoticesAhead] notifications after [now]; none when
/// they are off. They never name the habit.
List<ExperimentNotice> experimentNotices(ExperimentPlan plan, DateTime now) {
  final int? minutes = plan.notifyMinutes;
  if (minutes == null) return const <ExperimentNotice>[];
  final List<ExperimentNotice> out = <ExperimentNotice>[];
  for (final (int i, ({DateTime day, bool none}) d) in plan.schedule.indexed) {
    final DateTime at = DateTime(
      d.day.year,
      d.day.month,
      d.day.day,
      minutes ~/ 60,
      minutes % 60,
    );
    if (!at.isAfter(now)) continue;
    out.add((
      id: experimentNoticeBase + i,
      at: at,
      title: ExperimentCopy.noticeTitle(i + 1, plan.days),
      body: d.none
          ? ExperimentCopy.noticeNone(plan.fromHour)
          : ExperimentCopy.noticeUsual,
    ));
    if (out.length == experimentNoticesAhead) break;
  }
  return out;
}

/// The words that never name the habit: the notification's.
class ExperimentCopy {
  static String noticeTitle(int day, int of) => 'Experiment, day $day of $of';
  static String noticeNone(int fromHour) =>
      'Today is a none day, from ${fromHour.toString().padLeft(2, '0')}:00.';
  static const String noticeUsual = 'Today is an as-usual day.';
}
