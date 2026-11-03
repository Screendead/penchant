import 'dart:math' as math;

/// One past use of a trigger path on one vice's activity.
class TriggerUse {
  const TriggerUse(this.path, this.at);

  final String path;
  final DateTime at;
}

class RankedTrigger {
  const RankedTrigger(this.path, this.count, this.score);

  final String path;
  final int count;
  final double score;
}

/// Ranks a vice's past trigger paths for the one-tap row above the tree: each
/// use counts for less the older it is, and for more when it was logged near
/// the current hour. Derived from history on the device; nothing is stored.
List<RankedTrigger> rankRecent(
  List<TriggerUse> uses,
  DateTime now, {
  int limit = 5,
  Duration halfLife = const Duration(days: 14),
  int hourWindow = 2,
  double sameHourBoost = 1.5,
}) {
  final Map<String, double> scores = <String, double>{};
  final Map<String, int> counts = <String, int>{};

  for (final TriggerUse use in uses) {
    final double ageDays = now.difference(use.at).inMinutes / (60 * 24);
    double weight = math.pow(0.5, ageDays / halfLife.inDays).toDouble();
    final int hourGap = (use.at.hour - now.hour).abs();

    if (math.min(hourGap, 24 - hourGap) <= hourWindow) {
      weight *= sameHourBoost;
    }

    scores[use.path] = (scores[use.path] ?? 0) + weight;
    counts[use.path] = (counts[use.path] ?? 0) + 1;
  }

  final List<RankedTrigger> ranked =
      scores.entries
          .map((e) => RankedTrigger(e.key, counts[e.key]!, e.value))
          .toList()
        ..sort((a, b) => b.score.compareTo(a.score));

  return ranked.take(limit).toList();
}
