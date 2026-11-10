import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/what_follows.dart' show InsightGates;

/// How soon after one habit another must be logged to count as following it.
/// One window, so the comparison is made once per pair.
const Duration followWindow = Duration(minutes: 15);

/// The smallest share of uses, over every measure of chance, worth showing.
const double followFloor = 0.1;

/// How many days either side a day's other-day controls are drawn from.
const int followControlReach = 21;

/// The fewest other days a day needs to be judged against.
const int minFollowControls = 3;

// Same-day windows a use is also judged against, as starts in windows from
// the use: clear of the window itself and of the one before the use, where a
// follower logged first would sit.
const List<int> _earlier = <int>[-4, -7];
const List<int> _later = <int>[3, 6];

enum FollowsVerdict {
  /// Follows more often than every measure of chance, past the correction for
  /// many comparisons and [followFloor].
  found,

  /// Under [InsightGates.minDays] days with both habits, or under
  /// [InsightGates.minExposedDays] of them with the one following the other.
  tooFewDays,

  /// No more often than chance would give, or not past the correction.
  chance,

  /// Past the correction, by less than [followFloor].
  tooSmall,
}

/// How often [followerId] is logged within [followWindow] after [leadId],
/// against what each habit's own timing would give.
class HabitFollows {
  const HabitFollows({
    required this.leadId,
    required this.followerId,
    required this.days,
    required this.followedDays,
    required this.uses,
    required this.share,
    required this.chance,
    required this.pValue,
    this.verdict,
  });

  final String leadId;
  final String followerId;

  /// Days with both habits and enough other days to judge them against.
  final int days;

  /// Those of [days] on which the follower came within the window at least
  /// once.
  final int followedDays;

  /// The lead's uses on [days], a run of them inside one window counted once.
  final int uses;

  /// The share of [uses] the follower came within the window after.
  final double share;

  /// The largest share the follower's own timing gives: at the same clock
  /// times on nearby days with both habits, or on the same days a while
  /// before or a while after each use.
  final double chance;

  /// One-sided, for following more often than every measure of chance: the
  /// largest of the three. Null when there were too few days to test.
  final double? pValue;

  /// Null until [judgeHabitFollows] has run.
  final FollowsVerdict? verdict;

  double get excess => share - chance;

  HabitFollows _judged(FollowsVerdict verdict) => HabitFollows(
    leadId: leadId,
    followerId: followerId,
    days: days,
    followedDays: followedDays,
    uses: uses,
    share: share,
    chance: chance,
    pValue: pValue,
    verdict: verdict,
  );
}

/// Every ordered pair of habits in [uses], neither in [skip], on days up to
/// and including [through]. Unjudged: pass the result to [judgeHabitFollows].
///
/// A use counts on the day its evening belongs to ([lateDayOf]). Chance is
/// measured three ways, and a pair must beat all three: the same clock times
/// on other days with both habits (which a shared rhythm, or days both are
/// used, cannot beat), and the same day a while before and a while after
/// each use (which waking, bedtime or a late day cannot beat both of). Days
/// are the unit, so a run of uses in one day counts once.
List<HabitFollows> habitFollows({
  required Iterable<HabitUse> uses,
  required DateTime through,
  Set<String> skip = const <String>{},
  InsightGates gates = const InsightGates(),
}) {
  final DateTime last = startOfDay(through);
  final Map<String, List<DateTime>> times = <String, List<DateTime>>{};
  for (final HabitUse use in uses) {
    if (use.amount <= 0) continue;
    times.putIfAbsent(use.habitId, () => <DateTime>[]).add(use.at);
  }
  for (final List<DateTime> list in times.values) {
    list.sort();
  }
  final Map<String, Set<DateTime>> usedDays = <String, Set<DateTime>>{
    for (final MapEntry<String, List<DateTime>> e in times.entries)
      e.key: <DateTime>{
        for (final DateTime at in e.value)
          if (!lateDayOf(at).isAfter(last)) lateDayOf(at),
      },
  };
  final List<String> ids = <String>[
    for (final String id in times.keys)
      if (!skip.contains(id)) id,
  ]..sort();
  return <HabitFollows>[
    for (final String lead in ids)
      for (final String follower in ids)
        if (lead != follower)
          _pair(
            lead,
            follower,
            times[lead]!,
            times[follower]!,
            usedDays[lead]!.intersection(usedDays[follower]!),
            gates,
          ),
  ];
}

// Whether sorted [times] holds one after [from], up to and including [to].
bool _anyAfter(List<DateTime> times, DateTime from, DateTime to) {
  int low = 0, high = times.length;
  while (low < high) {
    final int mid = (low + high) >> 1;
    if (times[mid].isAfter(from)) {
      high = mid;
    } else {
      low = mid + 1;
    }
  }
  return low < times.length && !times[low].isAfter(to);
}

int _dayNumber(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

bool _weekend(DateTime day) => day.weekday >= DateTime.saturday;

HabitFollows _pair(
  String lead,
  String follower,
  List<DateTime> leadTimes,
  List<DateTime> followerTimes,
  Set<DateTime> bothDays,
  InsightGates gates,
) {
  final List<DateTime> days = bothDays.toList()..sort();
  final List<int> numbers = <int>[for (final DateTime d in days) _dayNumber(d)];
  final Map<DateTime, List<DateTime>> anchors = <DateTime, List<DateTime>>{};
  for (int i = 0; i < leadTimes.length; i++) {
    final DateTime at = leadTimes[i];
    if (i > 0 && leadTimes[i - 1].isAfter(at.subtract(followWindow))) continue;
    final DateTime day = lateDayOf(at);
    if (bothDays.contains(day)) {
      anchors.putIfAbsent(day, () => <DateTime>[]).add(at);
    }
  }
  bool followed(DateTime from) =>
      _anyAfter(followerTimes, from, from.add(followWindow));
  double sameDay(DateTime at, List<int> starts) =>
      starts.where((int k) => followed(at.add(followWindow * k))).length /
      starts.length;

  final List<double> overOther = <double>[];
  final List<double> overEarlier = <double>[];
  final List<double> overLater = <double>[];
  int judgedUses = 0, followedDays = 0;
  double hits = 0, other = 0, earlier = 0, later = 0;
  for (int i = 0; i < days.length; i++) {
    final List<DateTime>? atDay = anchors[days[i]];
    if (atDay == null) continue;
    final List<DateTime> controls = <DateTime>[
      for (int j = 0; j < days.length; j++)
        if (j != i &&
            (numbers[j] - numbers[i]).abs() <= followControlReach &&
            _weekend(days[j]) == _weekend(days[i]))
          days[j],
    ];
    if (controls.length < minFollowControls) continue;
    double dayHits = 0, dayOther = 0, dayEarlier = 0, dayLater = 0;
    for (final DateTime at in atDay) {
      // A use before the cutoff hour sits on the calendar day after its own.
      final int ahead = _dayNumber(at) - numbers[i];
      dayHits += followed(at) ? 1 : 0;
      dayOther +=
          controls
              .where(
                (DateTime c) => followed(
                  DateTime(
                    c.year,
                    c.month,
                    c.day + ahead,
                    at.hour,
                    at.minute,
                    at.second,
                  ),
                ),
              )
              .length /
          controls.length;
      dayEarlier += sameDay(at, _earlier);
      dayLater += sameDay(at, _later);
    }
    final int n = atDay.length;
    judgedUses += n;
    if (dayHits > 0) followedDays++;
    hits += dayHits;
    other += dayOther;
    earlier += dayEarlier;
    later += dayLater;
    overOther.add((dayHits - dayOther) / n);
    overEarlier.add((dayHits - dayEarlier) / n);
    overLater.add((dayHits - dayLater) / n);
  }
  final int judged = overOther.length;
  return HabitFollows(
    leadId: lead,
    followerId: follower,
    days: judged,
    followedDays: followedDays,
    uses: judgedUses,
    share: judgedUses == 0 ? 0 : hits / judgedUses,
    chance: judgedUses == 0 ? 0 : max(other, max(earlier, later)) / judgedUses,
    pValue: judged < gates.minDays
        ? null
        : <double>[
            _aboveZero(overOther),
            _aboveZero(overEarlier),
            _aboveZero(overLater),
          ].reduce(max),
  );
}

// One-sided p-value for the mean of [values] being above zero.
double _aboveZero(List<double> values) {
  final double m = mean(values);
  final double variance = sampleVariance(values);
  if (variance == 0) return m > 0 ? 0 : 1;
  return 1 -
      studentTCdf(m / sqrt(variance / values.length), values.length - 1.0);
}

/// [pairs] with a verdict each. A pair is found only when it passes
/// Benjamini-Hochberg at [InsightGates.falseDiscoveryRate] in one family with
/// [alongside], the p-values of the report's other comparisons; the day and
/// size gates run after, so they only hide.
List<HabitFollows> judgeHabitFollows(
  List<HabitFollows> pairs, {
  List<double> alongside = const <double>[],
  InsightGates gates = const InsightGates(),
}) {
  final List<int> tested = <int>[
    for (int i = 0; i < pairs.length; i++)
      if (pairs[i].pValue != null) i,
  ];
  final List<bool> kept = benjaminiHochberg(<double>[
    for (final int i in tested) pairs[i].pValue!,
    ...alongside,
  ], gates.falseDiscoveryRate);
  final Set<int> passed = <int>{
    for (int k = 0; k < tested.length; k++)
      if (kept[k]) tested[k],
  };
  return <HabitFollows>[
    for (final (int i, HabitFollows pair) in pairs.indexed)
      pair._judged(switch (pair) {
        HabitFollows(pValue: null) => FollowsVerdict.tooFewDays,
        _ when !passed.contains(i) || pair.excess <= 0 => FollowsVerdict.chance,
        _ when pair.followedDays < gates.minExposedDays =>
          FollowsVerdict.tooFewDays,
        _ when pair.excess < followFloor => FollowsVerdict.tooSmall,
        _ => FollowsVerdict.found,
      }),
  ];
}

/// What comes before one habit: the habits it follows, strongest first.
class FollowsCard {
  const FollowsCard({required this.headline, required this.others});

  final HabitFollows headline;
  final List<HabitFollows> others;

  String get habitId => headline.followerId;
}

/// The found pairs of [judged] as one card per following habit, by the
/// largest share over chance. Where each of two habits follows the other,
/// only the stronger way round is kept (the smaller p-value, then the larger
/// share over chance): entries made together land in either order.
List<FollowsCard> followsCards(List<HabitFollows> judged) {
  final List<HabitFollows> found = <HabitFollows>[
    for (final HabitFollows f in judged)
      if (f.verdict == FollowsVerdict.found) f,
  ];
  bool weaker(HabitFollows a, HabitFollows b) {
    final int byP = a.pValue!.compareTo(b.pValue!);
    if (byP != 0) return byP > 0;
    if (a.excess != b.excess) return a.excess < b.excess;
    return a.leadId.compareTo(b.leadId) > 0;
  }

  final List<HabitFollows> shown = <HabitFollows>[
    for (final HabitFollows f in found)
      if (!found.any(
        (HabitFollows g) =>
            g.leadId == f.followerId &&
            g.followerId == f.leadId &&
            weaker(f, g),
      ))
        f,
  ];
  int strongest(HabitFollows a, HabitFollows b) {
    final int bySize = b.excess.compareTo(a.excess);
    return bySize != 0 ? bySize : a.leadId.compareTo(b.leadId);
  }

  final Map<String, List<HabitFollows>> byFollower =
      <String, List<HabitFollows>>{};
  for (final HabitFollows f in shown) {
    byFollower.putIfAbsent(f.followerId, () => <HabitFollows>[]).add(f);
  }
  final List<FollowsCard> cards = <FollowsCard>[
    for (final List<HabitFollows> list in byFollower.values)
      FollowsCard(
        headline: (list..sort(strongest)).first,
        others: list.sublist(1),
      ),
  ];
  return cards..sort((FollowsCard a, FollowsCard b) {
    final int bySize = strongest(a.headline, b.headline);
    return bySize != 0 ? bySize : a.habitId.compareTo(b.habitId);
  });
}

String _percent(double share) => '${(share * 100).round()}%';

/// "After Coffee, you log Cigarettes within 15 minutes 62% of the time. Your
/// usual timing of each would give 18%."
String followsSentence(HabitFollows f, String lead, String follower) =>
    'After $lead, you log $follower within ${followWindow.inMinutes} minutes '
    '${_percent(f.share)} of the time. Your usual timing of each would give '
    '${_percent(f.chance)}.';

/// "After Tea: 31% of the time, against 12% by your usual timing".
String followsLine(HabitFollows f, String lead) =>
    'After $lead: ${_percent(f.share)} of the time, against '
    '${_percent(f.chance)} by your usual timing';

/// "From 84 uses of Coffee on 61 days with both".
String followsBasis(HabitFollows f, String lead) =>
    'From ${f.uses} uses of $lead on ${f.days} days with both';

/// A card as plain lines, for the copied text.
List<String> followsText(FollowsCard card, String Function(String id) nameOf) {
  final HabitFollows f = card.headline;
  final String follower = nameOf(f.followerId);
  return <String>[
    follower,
    followsSentence(f, nameOf(f.leadId), follower),
    followsBasis(f, nameOf(f.leadId)),
    for (final HabitFollows other in card.others)
      followsLine(other, nameOf(other.leadId)),
  ];
}
