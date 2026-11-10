import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/insights_report.dart';

// Health values stay on the device: the store is a file in Caches, which iOS
// leaves out of backups, so nothing read from Health reaches iCloud.

/// Where the daily values kept between opens of Insights live.
abstract interface class HealthStoreFile {
  /// Null when there is no store yet.
  Future<String?> read();

  Future<void> write(String contents);
}

class CacheHealthStoreFile implements HealthStoreFile {
  Future<File> get _file async =>
      File('${(await getApplicationCacheDirectory()).path}/health-daily.json');

  @override
  Future<String?> read() async {
    final File file = await _file;
    return await file.exists() ? await file.readAsString() : null;
  }

  @override
  Future<void> write(String contents) async {
    final File file = await _file;
    await file.parent.create(recursive: true);
    final File next = File('${file.path}.next');
    await next.writeAsString(contents, flush: true);
    await next.rename(file.path);
  }
}

/// The days read so far, by metric id, up to (not including) [through].
@immutable
class HealthDailyStore {
  const HealthDailyStore({
    required this.metrics,
    required this.through,
    required this.built,
    required this.values,
  });

  static const int version = 1;

  final Set<String> metrics;
  final DateTime through;

  /// When it was last read in full.
  final DateTime built;
  final Map<String, Map<DateTime, double>> values;

  String encode() => jsonEncode(<String, Object>{
    'version': version,
    'metrics': metrics.toList()..sort(),
    'through': healthDayKey(through),
    'built': healthDayKey(built),
    'values': <String, Object>{
      for (final MapEntry<String, Map<DateTime, double>> m in values.entries)
        m.key: <String, double>{
          for (final MapEntry<DateTime, double> d in m.value.entries)
            healthDayKey(d.key): d.value,
        },
    },
  });

  /// Null for anything but a store this version wrote.
  static HealthDailyStore? decode(String contents) {
    final Object? json;
    try {
      json = jsonDecode(contents);
    } on FormatException {
      return null;
    }
    if (json case {
      'version': version,
      'metrics': final List<Object?> metrics,
      'through': final String through,
      'built': final String built,
      'values': final Map<String, Object?> values,
    }) {
      final DateTime? throughDay = parseHealthDayKey(through);
      final DateTime? builtDay = parseHealthDayKey(built);
      if (throughDay == null || builtDay == null) return null;
      final Map<String, Map<DateTime, double>> read =
          <String, Map<DateTime, double>>{};
      for (final MapEntry<String, Object?> m in values.entries) {
        final Object? days = m.value;
        if (days is! Map<String, Object?>) return null;
        final Map<DateTime, double> byDay = <DateTime, double>{};
        for (final MapEntry<String, Object?> d in days.entries) {
          final DateTime? day = parseHealthDayKey(d.key);
          final Object? value = d.value;
          if (day == null || value is! num || !value.isFinite) return null;
          byDay[day] = value.toDouble();
        }
        read[m.key] = byDay;
      }
      return HealthDailyStore(
        metrics: {
          for (final Object? m in metrics)
            if (m is String) m,
        },
        through: throughDay,
        built: builtDay,
        values: read,
      );
    }
    return null;
  }
}

/// A store older than this is read again in full, in case a change slipped
/// past the anchors (access changed in Settings, say).
const int healthStoreRebuildDays = 30;

/// Above this many separate runs of changed days in one metric, its changed
/// calendar years are read instead.
const int _maxRuns = 12;

/// Metrics read from the sleep samples, whose nights depend on which source
/// each year's read prefers, so a change rereads its calendar year, as the
/// whole read splits them.
final Set<String> _byYear = <String>{
  HealthMetric.sleepInBed.id,
  HealthMetric.sleepAsleep.id,
  HealthMetric.sleepAwake.id,
  HealthMetric.sleepCore.id,
  HealthMetric.sleepDeep.id,
  HealthMetric.sleepREM.id,
  HealthMetric.sleepOnset.id,
  HealthMetric.sleepEnd.id,
  HealthMetric.sleepingHeartRate.id,
};

typedef _Span = ({DateTime start, DateTime end});

/// Every value of [metrics] for [range], reading from Health only what
/// changed since the last call: the days HealthKit's anchors name, the days
/// since, and in full a metric not read before or with a deletion. The rest
/// comes from [file]. HealthKit is asked what changed before any read, so a
/// change during the reads is named again next time; it is told the changes
/// were handled only once the store is written.
///
/// Null when [alive] turns false between reads. Throws as
/// [HealthSource.dailyValues] does; a store that cannot be read or written
/// costs a full read, never a value.
Future<HealthRead?> syncHealthDaily({
  required HealthSource source,
  required HealthStoreFile file,
  required Set<HealthMetric> metrics,
  required ({DateTime start, DateTime end}) range,
  required DateTime today,
  bool Function()? alive,
}) async {
  final HealthChanges? changes = await source.changes(metrics);
  if (changes == null) return const HealthUnavailable();
  final Set<String> ids = {for (final m in metrics) m.id};
  HealthDailyStore? stored;
  try {
    final String? contents = await file.read();
    stored = contents == null ? null : HealthDailyStore.decode(contents);
  } catch (_) {
    stored = null;
  }
  if (stored != null &&
      (!setEquals(stored.metrics, ids) ||
          stored.through.isAfter(range.end) ||
          !stored.through.isAfter(range.start) ||
          addDays(stored.built, healthStoreRebuildDays).isBefore(today) ||
          stored.built.isAfter(today))) {
    stored = null;
  }

  final Map<_Span, Set<String>> reads = <_Span, Set<String>>{};
  void add(Iterable<_Span> spans, Iterable<String> metricIds) {
    if (metricIds.isEmpty) return;
    for (final _Span span in spans) {
      (reads[span] ??= <String>{}).addAll(metricIds);
    }
  }

  final List<_Span> years = insightsHealthChunks(range);
  if (stored == null) {
    add(years, ids);
  } else {
    final DateTime through = stored.through;
    final Set<String> whole = ids.intersection(changes.whole);
    add(years, whole);
    add(
      insightsHealthChunks((start: through, end: range.end)),
      ids.difference(whole),
    );
    final List<_Span> kept = insightsHealthChunks((
      start: range.start,
      end: through,
    ));
    for (final String id in ids.difference(whole)) {
      final List<DateTime> days =
          (changes.days[id] ?? const <DateTime>{})
              .where((d) => !d.isBefore(range.start) && d.isBefore(through))
              .toList()
            ..sort();
      if (days.isEmpty) continue;
      final List<_Span> runs = _runs(days);
      if (_byYear.contains(id) || runs.length > _maxRuns) {
        add(
          kept.where(
            (y) => days.any((d) => !d.isBefore(y.start) && d.isBefore(y.end)),
          ),
          [id],
        );
      } else {
        add(runs, [id]);
      }
    }
  }

  final Map<String, Map<DateTime, double>> values =
      <String, Map<DateTime, double>>{
        for (final String id in ids)
          id: <DateTime, double>{...?stored?.values[id]},
      };
  final List<_Span> order = reads.keys.toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  for (final _Span span in order) {
    if (alive != null && !alive()) return null;
    final Set<String> wanted = reads[span]!;
    final HealthRead read = await source.dailyValues(
      {
        for (final m in metrics)
          if (wanted.contains(m.id)) m,
      },
      span.start,
      span.end,
    );
    switch (read) {
      case HealthUnavailable():
        return read;
      case HealthValues(values: final List<DailyOutcome> got):
        for (final String id in wanted) {
          values[id]!.removeWhere(
            (d, _) => !d.isBefore(span.start) && d.isBefore(span.end),
          );
        }
        for (final DailyOutcome v in got) {
          if (wanted.contains(v.metricId)) {
            values[v.metricId]![v.date] = v.value;
          }
        }
    }
  }

  final HealthDailyStore next = HealthDailyStore(
    metrics: ids,
    through: range.end,
    built: stored?.built ?? startOfDay(today),
    values: values,
  );
  try {
    await file.write(next.encode());
    await source.changesHandled(changes.generation);
  } catch (_) {
    // Named again next time.
  }
  return HealthValues(<DailyOutcome>[
    for (final MapEntry<String, Map<DateTime, double>> m in values.entries)
      for (final MapEntry<DateTime, double> d in m.value.entries)
        if (!d.key.isBefore(range.start) && d.key.isBefore(range.end))
          DailyOutcome(d.key, m.key, d.value),
  ]);
}

/// Consecutive days, as spans of local midnights.
List<_Span> _runs(List<DateTime> sorted) {
  final List<_Span> runs = <_Span>[];
  for (final DateTime day in sorted) {
    if (runs.isNotEmpty && runs.last.end == day) {
      runs[runs.length - 1] = (start: runs.last.start, end: addDays(day, 1));
    } else if (runs.isEmpty || runs.last.end.isBefore(day)) {
      runs.add((start: day, end: addDays(day, 1)));
    }
  }
  return runs;
}
