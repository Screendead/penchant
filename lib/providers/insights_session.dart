import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/insights/after_event.dart';
import 'package:tracker/insights/daylight.dart';
import 'package:tracker/insights/health_sample_cache.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/places.dart';
import 'package:tracker/providers/insights_provider.dart';
import 'package:tracker/providers/user_provider.dart';

/// The signed-in user's uid, for what Insights keeps between opens.
final insightsUidProvider = Provider<String?>(
  (ref) => ref.watch(
    userProvider.select((AsyncValue<User?> user) => user.value?.uid),
  ),
);

/// What Insights keeps in memory between opens, for one signed-in user. A new
/// uid gets a new, empty session, so one user's report never shows for
/// another; null while nobody is signed in.
final insightsSessionProvider = Provider<InsightsSession?>((ref) {
  final String? uid = ref.watch(insightsUidProvider);
  return uid == null ? null : InsightsSession(uid);
});

typedef SampleSpanKey = ({String metric, DateTime start, DateTime end});

class InsightsSession {
  InsightsSession(this.uid);

  final String uid;

  /// What the page last showed, kept up while the next open re-reads.
  InsightsView? lastView;

  /// The view last handed to the sealed last-report file, so a rebuild that
  /// shows the same report writes nothing.
  InsightsView? savedView;

  final List<(EngineInputs, InsightsResult)> _results =
      <(EngineInputs, InsightsResult)>[];

  // The daily report and the one with hours-after, for today and the day
  // before, are all a session needs to reuse.
  static const int _keptResults = 4;

  /// Health samples of whole days already read, by metric and span.
  final Map<SampleSpanKey, List<HealthSample>> samples =
      <SampleSpanKey, List<HealthSample>>{};

  HealthSampleCache? _loadedFrom;
  Future<void>? _loading;

  /// Fills [samples] from what [cache] holds, once per cache. Never throws.
  Future<void> loadSamples(HealthSampleCache cache) {
    if (cache.uid != uid) return Future<void>.value();
    if (identical(cache, _loadedFrom)) return _loading!;
    _loadedFrom = cache;
    return _loading = cache.load().then((
      Map<CachedSpan, List<HealthSample>> kept,
    ) {
      for (final MapEntry<CachedSpan, List<HealthSample>> e in kept.entries) {
        samples.putIfAbsent(e.key, () => e.value);
      }
    });
  }

  InsightsResult? resultFor(EngineInputs inputs) {
    for (final (EngineInputs kept, InsightsResult result) in _results) {
      if (kept == inputs) return result;
    }
    return null;
  }

  void keepResult(EngineInputs inputs, InsightsResult result) {
    _results
      ..removeWhere(((EngineInputs, InsightsResult) e) => e.$1 == inputs)
      ..add((inputs, result));
    if (_results.length > _keptResults) _results.removeAt(0);
  }
}

/// Everything the engine reads, equal when the engine would compute the same
/// report: the journal by what a use carries (habit, time, amount), not by
/// which read produced the list.
@immutable
class EngineInputs {
  const EngineInputs({
    required this.activities,
    required this.health,
    required this.samples,
    required this.today,
    required this.archived,
    required this.events,
    this.reminders = const <DailyOutcome>[],
    this.stays = const <PlaceStay>[],
    this.location,
  });

  final List<ViceActivity> activities;
  final List<DailyOutcome> health;
  final Map<String, List<HealthSample>> samples;
  final DateTime today;
  final String archived;
  final List<CalendarEvent> events;

  /// [reminderOutcomes]; empty without Reminders access.
  final List<DailyOutcome> reminders;

  /// [PlaceStore.stays]; empty without location access.
  final List<PlaceStay> stays;

  /// Where day length is worked out; null when unknown.
  final RoughLocation? location;

  @override
  bool operator ==(Object other) =>
      other is EngineInputs &&
      other.today == today &&
      other.archived == archived &&
      _sameUses(other.activities, activities) &&
      listEquals(other.health, health) &&
      _sameSamples(other.samples, samples) &&
      _sameEvents(other.events, events) &&
      listEquals(other.reminders, reminders) &&
      listEquals(other.stays, stays) &&
      other.location == location;

  @override
  int get hashCode => Object.hash(
    today,
    archived,
    activities.length,
    health.length,
    samples.length,
    events.length,
    reminders.length,
    stays.length,
    location,
  );
}

bool _sameUses(List<ViceActivity> a, List<ViceActivity> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i].viceID != b[i].viceID ||
        a[i].createdAt != b[i].createdAt ||
        a[i].measure != b[i].measure) {
      return false;
    }
  }
  return true;
}

bool _sameSamples(
  Map<String, List<HealthSample>> a,
  Map<String, List<HealthSample>> b,
) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final MapEntry<String, List<HealthSample>> e in a.entries) {
    if (!listEquals(e.value, b[e.key])) return false;
  }
  return true;
}

bool _sameEvents(List<CalendarEvent> a, List<CalendarEvent> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i].start != b[i].start || a[i].end != b[i].end) return false;
  }
  return true;
}
