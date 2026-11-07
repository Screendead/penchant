import 'package:tracker/data/trigger_tree.dart';
import 'package:tracker/data/vice_activity.dart';

/// A trigger as the user reads it: a tree path's labels from the root down,
/// or a free-text trigger as written.
String triggerDisplay(String trigger) =>
    triggerLabels(trigger)?.join(' › ') ?? trigger;

/// The most specific label of [trigger], for a compact row.
String triggerShortDisplay(String trigger) =>
    triggerLabels(trigger)?.last ?? trigger;

bool isFreeTextTrigger(String trigger) => triggerLabels(trigger) == null;

/// The triggers used most often on [recent], most frequent first; a tie goes
/// to the one used most recently. Computed on the device, so nothing extra is
/// stored.
List<String> usualTriggers(List<ViceActivity> recent, {int max = 6}) {
  final Map<String, int> counts = <String, int>{};
  final Map<String, DateTime> lastUsed = <String, DateTime>{};
  for (final ViceActivity activity in recent) {
    final DateTime at = activity.createdAt.toDate();
    for (final String trigger in activity.triggers.toSet()) {
      counts[trigger] = (counts[trigger] ?? 0) + 1;
      final DateTime? seen = lastUsed[trigger];
      if (seen == null || at.isAfter(seen)) {
        lastUsed[trigger] = at;
      }
    }
  }
  final List<String> ranked = counts.keys.toList()
    ..sort((String a, String b) {
      final int byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : lastUsed[b]!.compareTo(lastUsed[a]!);
    });
  return ranked.take(max).toList();
}
