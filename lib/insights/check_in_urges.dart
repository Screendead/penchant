import 'package:intl/intl.dart';
import 'package:tracker/data/check_in.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/what_follows.dart';

/// The fewest days holding both an answered check-in and an entry of the
/// habit with an urge before the two are compared.
const int minCheckInUrgeDays = 14;

/// The smallest difference worth showing: one step of the 1 to 5 scale, the
/// size of an answer. It does not rule out a person who leaves an entry's
/// urge blank when there is none: that alone puts entries higher by the
/// share of check-ins at 0 times (the mean of the rest less 1).
const double checkInUrgeFloor = 1;

/// The urge noted at a habit's entries against the urge at random check-ins:
/// a finding when [refusal] is null.
class CheckInUrge {
  const CheckInUrge({
    required this.habitId,
    required this.days,
    required this.entries,
    required this.checkIns,
    required this.noUrge,
    required this.entryMean,
    required this.checkInMean,
    this.pValue,
    this.refusal,
  });

  final String habitId;

  /// Days with both an answered check-in and an entry of the habit with an
  /// urge; the counts and means below are over these days alone.
  final int days;
  final int entries;
  final int checkIns;

  /// Those of [checkIns] answered 0.
  final int noUrge;

  /// The mean over [days] of each day's mean, on the entry's 1 to 5 scale:
  /// a check-in's 0 counts as 1.
  final double entryMean;
  final double checkInMean;

  /// Set once tested: the comparison then counts in the report's family.
  final double? pValue;
  final RefusalReason? refusal;

  bool get found => refusal == null;
  double get difference => entryMean - checkInMean;

  CheckInUrge refused(RefusalReason reason) => CheckInUrge(
    habitId: habitId,
    days: days,
    entries: entries,
    checkIns: checkIns,
    noUrge: noUrge,
    entryMean: entryMean,
    checkInMean: checkInMean,
    pValue: pValue,
    refusal: reason,
  );
}

/// For each habit in [uses] not in [skip] with an urge on an entry, the urge
/// at its entries against the urge at [checkIns], on days up to and including
/// [through]. Empty while no check-in has been answered. Unjudged: pass the
/// result to [judgeCheckInUrges].
///
/// Days are the unit, and only days holding both kinds of answer: each gives
/// one difference, its mean urge at entries less its mean at check-ins, so a
/// day of strong urges at every moment says nothing, and a day with many
/// entries counts once. An entry's scale starts at 1 and a check-in's at 0,
/// so a check-in's 0 is read as 1, the lowest an entry can say: otherwise the
/// scales alone would put entries higher. The differences are tested against
/// 0, widened for neighbouring days that resemble each other and redrawn in
/// week-long blocks, as the other day comparisons are. A check-in asks about
/// any urge and names no habit, and each habit is compared with all of them.
List<CheckInUrge> checkInUrges({
  required Iterable<HabitUse> uses,
  required Iterable<CheckInAnswer> checkIns,
  required DateTime through,
  Set<String> skip = const <String>{},
  InsightGates gates = const InsightGates(),
}) {
  final DateTime last = startOfDay(through);
  final Map<DateTime, List<int>> asked = <DateTime, List<int>>{};
  for (final CheckInAnswer c in checkIns) {
    final DateTime day = lateDayOf(c.at);
    if (day.isAfter(last)) continue;
    asked.putIfAbsent(day, () => <int>[]).add(c.strength);
  }
  if (asked.isEmpty) return const <CheckInUrge>[];
  final Map<String, Map<DateTime, List<int>>> byHabit =
      <String, Map<DateTime, List<int>>>{};
  for (final HabitUse use in uses) {
    final int? urge = use.urge;
    if (urge == null || skip.contains(use.habitId)) continue;
    final DateTime day = lateDayOf(use.at);
    if (day.isAfter(last)) continue;
    byHabit
        .putIfAbsent(use.habitId, () => <DateTime, List<int>>{})
        .putIfAbsent(day, () => <int>[])
        .add(urge);
  }
  final List<String> ids = byHabit.keys.toList()..sort();
  return <CheckInUrge>[
    for (final String id in ids) _habit(id, byHabit[id]!, asked, gates),
  ];
}

double _mean(Iterable<int> values) =>
    mean(<double>[for (final int v in values) v.toDouble()]);

CheckInUrge _habit(
  String id,
  Map<DateTime, List<int>> noted,
  Map<DateTime, List<int>> asked,
  InsightGates gates,
) {
  final List<DateTime> days = noted.keys.where(asked.containsKey).toList()
    ..sort();
  final List<double> atEntries = <double>[
    for (final DateTime d in days) _mean(noted[d]!),
  ];
  final List<double> atCheckIns = <double>[
    for (final DateTime d in days)
      _mean(asked[d]!.map((int s) => s < minUrge ? minUrge : s)),
  ];
  CheckInUrge result({RefusalReason? refusal, double? p}) => CheckInUrge(
    habitId: id,
    days: days.length,
    entries: <int>[for (final DateTime d in days) noted[d]!.length].sum,
    checkIns: <int>[for (final DateTime d in days) asked[d]!.length].sum,
    noUrge: <int>[
      for (final DateTime d in days)
        asked[d]!.where((int s) => s < minUrge).length,
    ].sum,
    entryMean: days.isEmpty ? 0 : mean(atEntries),
    checkInMean: days.isEmpty ? 0 : mean(atCheckIns),
    pValue: p,
    refusal: refusal,
  );

  if (days.length < minCheckInUrgeDays) {
    return result(refusal: RefusalReason.tooFewDays);
  }
  final List<double> y = <double>[
    for (int r = 0; r < days.length; r++) atEntries[r] - atCheckIns[r],
  ];
  final List<List<double>> design = <List<double>>[
    for (int r = 0; r < days.length; r++) <double>[1],
  ];
  final LinearFit? plain = fitLeastSquares(design, y);
  if (plain == null) return result(refusal: RefusalReason.tooFewDays);
  final (
    :LinearFit fit,
    inflation: _,
    :Interval? Function(double level) bootstrap,
  ) = judgeDays(
    design,
    y,
    plain,
    0,
    days,
    gates,
  );
  final double p = fit.pValue(0);
  if (fit.interval(0, level: gates.level).crossesZero) {
    return result(refusal: RefusalReason.withinNoise, p: p);
  }
  if (bootstrap(gates.level) case final Interval redrawn
      when redrawn.crossesZero) {
    return result(refusal: RefusalReason.withinNoise, p: p);
  }
  return result(p: p);
}

extension on List<int> {
  int get sum => fold<int>(0, (int s, int v) => s + v);
}

/// [urges] judged as part of one family with the comparisons whose p-values
/// are [alongside]: a finding that fails Benjamini-Hochberg at
/// [InsightGates.falseDiscoveryRate] over them all is refused as
/// [RefusalReason.chance], then one under [checkInUrgeFloor] as
/// [RefusalReason.tooSmall].
List<CheckInUrge> judgeCheckInUrges(
  List<CheckInUrge> urges, {
  required List<double> alongside,
  InsightGates gates = const InsightGates(),
}) {
  final List<bool> kept = benjaminiHochberg(<double>[
    ...checkInUrgePValues(urges),
    ...alongside,
  ], gates.falseDiscoveryRate);
  int k = 0;
  return <CheckInUrge>[
    for (final CheckInUrge u in urges)
      if (u.pValue == null)
        u
      else if ((kept[k++], u.found) case (final bool pass, true))
        !pass
            ? u.refused(RefusalReason.chance)
            : u.difference.abs() < checkInUrgeFloor
            ? u.refused(RefusalReason.tooSmall)
            : u
      else
        u,
  ];
}

/// The p-values [judgeCheckInUrges] tests, for the page's family.
List<double> checkInUrgePValues(List<CheckInUrge> urges) => <double>[
  for (final CheckInUrge u in urges) ?u.pValue,
];

/// The found comparisons in [judged], the largest difference first.
List<CheckInUrge> checkInUrgeCards(List<CheckInUrge> judged) =>
    <CheckInUrge>[
      for (final CheckInUrge u in judged)
        if (u.found) u,
    ]..sort((CheckInUrge a, CheckInUrge b) {
      final int bySize = b.difference.abs().compareTo(a.difference.abs());
      return bySize != 0 ? bySize : a.habitId.compareTo(b.habitId);
    });

String _number(double v, String locale) =>
    NumberFormat('0.#', locale).format(v);

/// "At entries of Wine you put the urge at 3.6 of 5 on average, against 1.4
/// at random check-ins." Says what goes together, never why.
String checkInUrgeSentence(CheckInUrge u, String habit, String locale) =>
    'At entries of $habit you put the urge at '
    '${_number(u.entryMean, locale)} of $maxUrge on average, against '
    '${_number(u.checkInMean, locale)} at random check-ins.';

/// "Over 18 days with both: 41 entries with an urge and 37 check-ins, 15 of
/// them answered 0 and counted as 1, where an entry's scale starts. Check-ins
/// ask about any urge at moments picked at random; entries are moments you
/// chose."
String checkInUrgeBasis(CheckInUrge u) =>
    'Over ${u.days} days with both: ${u.entries} '
    '${u.entries == 1 ? 'entry' : 'entries'} with an urge and ${u.checkIns} '
    '${u.checkIns == 1 ? 'check-in' : 'check-ins'}'
    '${u.noUrge == 0 ? '' : ', ${u.noUrge} of them answered 0 and counted as '
              '$minUrge, where an entry’s scale starts'}. Check-ins ask '
    'about any urge at moments picked at random; entries are moments you '
    'chose.';

/// A card as plain lines, for the copied text.
List<String> checkInUrgeText(CheckInUrge u, String habit, String locale) =>
    <String>[habit, checkInUrgeSentence(u, habit, locale), checkInUrgeBasis(u)];

/// Why [u] is not shown, led by what was compared.
String checkInUrgeRefusal(CheckInUrge u) {
  final String reason = switch (u.refusal) {
    RefusalReason.tooFewDays =>
      'too few days with both yet: ${u.days} of $minCheckInUrgeDays',
    RefusalReason.chance => 'could be chance, one of many comparisons',
    RefusalReason.tooSmall =>
      'too small to matter, under ${checkInUrgeFloor.round()} point of '
          '$maxUrge',
    _ => 'within the noise, no clear difference',
  };
  return 'Urge at entries against check-ins: $reason';
}
