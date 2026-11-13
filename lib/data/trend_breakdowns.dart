import 'package:tracker/data/trigger_tree.dart';
import 'package:tracker/data/usage_series.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/insights/health_source.dart';

// [metricId]'s mean over the days of each bucket that have a value; null for
// a bucket with none, which is no data rather than zero.
List<double?> bucketHealth(
  UsageRange range,
  Iterable<DailyOutcome> values,
  String metricId,
) {
  final List<double> sums = List<double>.filled(range.bucketCount, 0);
  final List<int> counts = List<int>.filled(range.bucketCount, 0);
  for (final DailyOutcome v in values) {
    if (v.metricId != metricId) {
      continue;
    }
    final int? bucket = range.bucketOf(v.date);
    if (bucket != null) {
      sums[bucket] += v.value;
      counts[bucket]++;
    }
  }
  return <double?>[
    for (int i = 0; i < sums.length; i++)
      counts[i] == 0 ? null : sums[i] / counts[i],
  ];
}

// The area a free-text trigger counts under.
const String ownWordsArea = '~own';
// The areas past [triggerShares]' maxAreas, merged.
const String otherArea = '~other';

String triggerAreaLabel(String area) => switch (area) {
  ownWordsArea => 'Own words',
  otherArea => 'Other',
  _ => triggerLabels(area)?.single ?? area,
};

// The top-level trigger areas of one entry: the root of each tree path, and
// [ownWordsArea] for free text.
Set<String> triggerAreas(List<String> triggers) => <String>{
  for (final String t in triggers)
    if (triggerLabels(t) == null)
      ownWordsArea
    else
      t.split(triggerPathSeparator).first,
};

typedef TriggerShares = ({
  // Most tagged first; [otherArea], if present, last.
  List<String> areas,
  // Entries with any trigger, per bucket.
  List<int> tagged,
  // Per bucket, each area's share of its tagged entries, in [areas]' order;
  // summing to 1 where any are tagged.
  List<List<double>> shares,
  // Each area's share over the whole range.
  List<double> overall,
});

// Which areas a habit's tagged entries fall in, bucket by bucket. An entry
// tagged in several areas counts a equal part towards each, so a bucket's
// shares sum to 1. Past [maxAreas], the least tagged merge into [otherArea].
TriggerShares triggerShares(
  UsageRange range,
  Iterable<ViceActivity> activities, {
  int maxAreas = 4,
}) {
  final int n = range.bucketCount;
  final List<int> tagged = List<int>.filled(n, 0);
  final List<Map<String, double>> weights = <Map<String, double>>[
    for (int i = 0; i < n; i++) <String, double>{},
  ];
  final Map<String, double> totals = <String, double>{};
  for (final ViceActivity a in activities) {
    final Set<String> areas = triggerAreas(a.triggers);
    final int? bucket = areas.isEmpty
        ? null
        : range.bucketOf(a.createdAt.toDate());
    if (bucket == null) {
      continue;
    }
    tagged[bucket]++;
    for (final String area in areas) {
      final double w = 1 / areas.length;
      weights[bucket][area] = (weights[bucket][area] ?? 0) + w;
      totals[area] = (totals[area] ?? 0) + w;
    }
  }
  final List<String> ranked = totals.keys.toList()
    ..sort((String a, String b) {
      final int byWeight = totals[b]!.compareTo(totals[a]!);
      return byWeight != 0 ? byWeight : a.compareTo(b);
    });
  final List<String> areas = ranked.length <= maxAreas
      ? ranked
      : <String>[...ranked.take(maxAreas - 1), otherArea];
  final Set<String> kept = areas.toSet();
  String keyOf(String area) => kept.contains(area) ? area : otherArea;
  final int all = tagged.fold<int>(0, (int a, int b) => a + b);

  return (
    areas: areas,
    tagged: tagged,
    shares: <List<double>>[
      for (int i = 0; i < n; i++)
        <double>[
          for (final String area in areas)
            tagged[i] == 0
                ? 0
                : weights[i].entries
                          .where((e) => keyOf(e.key) == area)
                          .fold<double>(0, (double s, e) => s + e.value) /
                      tagged[i],
        ],
    ],
    overall: <double>[
      for (final String area in areas)
        all == 0
            ? 0
            : totals.entries
                      .where((e) => keyOf(e.key) == area)
                      .fold<double>(0, (double s, e) => s + e.value) /
                  all,
    ],
  );
}
