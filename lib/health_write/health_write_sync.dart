import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/habit_strength.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/data/widget_snapshot.dart';
import 'package:tracker/health_write/health_write.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

// What one entry's sample was last made to hold.
typedef HealthSample = ({HealthWriteKind kind, double value, DateTime at});

typedef HealthWriteStep = ({
  Map<String, HealthSample> write,
  Set<String> delete,
});

// What Health needs so that it matches the live window of entries: a sample
// for each entry of a chosen habit with a value, rewritten when its value or
// time changed since [written], and none for an entry [written] holds that is
// gone from a window still covering its time, or now has no value. An entry
// of a habit no longer chosen is forgotten, its sample kept: removing those is
// the person's call when they turn the switch off.
HealthWriteStep healthWriteStep({
  required Iterable<Vice> vices,
  required Iterable<ViceActivity> activities,
  required Set<String> chosen,
  required DateTime windowStart,
  required Map<String, ({String viceID, HealthSample sample})> written,
}) {
  final Map<String, HabitStrength> strengths = <String, HabitStrength>{
    for (final Vice vice in vices)
      if (chosen.contains(vice.id) && !vice.locked && vice.strength != null)
        vice.id: vice.strength!,
  };
  final Map<String, HealthSample> write = <String, HealthSample>{};
  final Set<String> delete = <String>{};
  final Set<String> seen = <String>{};
  for (final ViceActivity activity in activities) {
    seen.add(activity.id);
    final HabitStrength? strength = strengths[activity.viceID];
    if (strength == null || activity.locked) {
      continue;
    }
    final double? value = healthValueOf(strength, activity);
    final HealthSample? before = written[activity.id]?.sample;
    if (value == null) {
      if (before != null) {
        delete.add(activity.id);
      }
      continue;
    }
    final HealthSample sample = (
      kind: HealthWriteKind.of(strength)!,
      value: value,
      at: activity.createdAt.toDate(),
    );
    if (sample != before) {
      write[activity.id] = sample;
    }
  }
  for (final MapEntry<String, ({String viceID, HealthSample sample})>(
        :key,
        :value,
      )
      in written.entries) {
    if (!seen.contains(key) &&
        chosen.contains(value.viceID) &&
        !value.sample.at.isBefore(windowStart)) {
      delete.add(key);
    }
  }
  return (write: write, delete: delete);
}

// Keeps Health in step with the entries of the habits this device writes,
// over the window the widgets already listen to (so no extra reads): an entry
// logged here, flushed from a widget in the background, or written on another
// device is written when the running app sees it; an edit rewrites it; a
// delete or an Undo removes it. Remembered in memory only, so each launch
// rewrites the window once, unchanged. iOS only: the Mac never touches Health.
final healthWriteSyncProvider = Provider<void>((ref) {
  if (!healthWriteSupported) {
    return;
  }
  final _Written memory = ref.watch(_writtenProvider);
  final String? uid = ref.watch(
    userProvider.select((AsyncValue<User?> u) => u.value?.uid),
  );
  if (uid != memory.uid) {
    memory
      ..uid = uid
      ..samples.clear();
  }
  if (uid == null) {
    return;
  }
  final Set<String> chosen = ref.watch(healthWriteChoicesProvider(uid));
  if (chosen.isEmpty) {
    memory.samples.clear();
    return;
  }
  final DateTime today = ref.watch(todayProvider);
  final List<Vice>? vices = ref.watch(viceListForUserProvider(uid)).value;
  final List<ViceActivity>? activities = ref
      .watch(
        viceActivityRecentForUserProvider((
          uid: uid,
          today: today,
          days: widgetTopWindowDays,
        )),
      )
      .value;
  if (vices == null || activities == null) {
    return;
  }
  final HealthWriteStep step = healthWriteStep(
    vices: vices,
    activities: activities,
    chosen: chosen,
    windowStart: addDays(today, 1 - widgetTopWindowDays),
    written: memory.samples,
  );
  memory.samples.removeWhere(
    (String id, ({String viceID, HealthSample sample}) w) =>
        !chosen.contains(w.viceID),
  );
  final HealthWriter writer = ref.read(healthWriterProvider);
  final Map<String, String> viceOf = <String, String>{
    for (final ViceActivity a in activities) a.id: a.viceID,
  };
  for (final MapEntry<String, HealthSample>(:key, :value)
      in step.write.entries) {
    memory.samples[key] = (viceID: viceOf[key]!, sample: value);
    memory.then(
      () => writer.writeEntry(
        kind: value.kind,
        activityID: key,
        viceID: viceOf[key]!,
        value: value.value,
        at: value.at,
      ),
    );
  }
  for (final String id in step.delete) {
    memory.samples.remove(id);
    memory.then(() => writer.deleteEntry(id));
  }
});

final _writtenProvider = Provider<_Written>((ref) => _Written());

class _Written {
  String? uid;
  final Map<String, ({String viceID, HealthSample sample})> samples =
      <String, ({String viceID, HealthSample sample})>{};
  // One call at a time, in order: a delete sent while its entry's save is
  // still in flight would find nothing and leave the sample.
  Future<void> _queue = Future<void>.value();

  void then(Future<void> Function() call) {
    _queue = _queue.then((_) => call());
  }
}
