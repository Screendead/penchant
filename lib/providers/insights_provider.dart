import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/insights/after_event.dart';
import 'package:tracker/insights/from_journal.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/health_sync.dart';
import 'package:tracker/insights/hours_after.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/providers/calendar_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

// Health values stay on the device: ReportProviderErrors sends every provider
// failure to Crashlytics, so nothing below that reads or derives from Health
// may fail. Each returns its failure as a value instead.

final healthSourceProvider = Provider<HealthSource>(
  (ref) => ChannelHealthSource(),
);

final healthStoreFileProvider = Provider<HealthStoreFile>(
  (ref) => CacheHealthStoreFile(),
);

/// Whether this device has shown the Health sheet from Insights. Kept on the
/// device only; HealthKit itself never says what was allowed.
final healthConnectedProvider = FutureProvider<bool>((ref) async {
  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(healthConnectedKey) ?? false;
  } catch (_) {
    return false;
  }
});

const String healthConnectedKey = 'healthConnected';

/// Which set of read types the sheet last showed, so a later set can be asked
/// for. Raise with each change to readTypes in ios/Runner/HealthChannel.swift:
/// 2 added heart rate. Absent for anyone who connected before it was kept.
const int healthReadTypesVersion = 2;

const String healthAskedVersionKey = 'healthAskedVersion';

/// Whether Health was connected before the app read a type it reads now, so
/// the sheet would ask for the new ones. Never shows the sheet itself.
/// HealthKit answers first; the version this device last asked for decides
/// when HealthKit cannot tell.
final healthAskAgainProvider = FutureProvider.autoDispose<bool>((ref) async {
  if (defaultTargetPlatform == TargetPlatform.macOS) return false;
  final HealthSource source = ref.watch(healthSourceProvider);
  if (!await ref.watch(healthConnectedProvider.future)) return false;
  HealthRequestStatus status;
  try {
    status = await source.requestStatus();
  } catch (_) {
    status = HealthRequestStatus.unknown;
  }
  switch (status) {
    case HealthRequestStatus.shouldRequest:
      return true;
    case HealthRequestStatus.unnecessary:
      return false;
    case HealthRequestStatus.unknown:
      try {
        if (!await source.isAvailable()) return false;
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        return (prefs.getInt(healthAskedVersionKey) ?? 1) <
            healthReadTypesVersion;
      } catch (_) {
        return false;
      }
  }
});

/// Shows the Health sheet. False when it could not be shown. Takes the
/// container rather than a page's ref, which may be disposed by the time the
/// sheet closes (a sign-out pops every page).
Future<bool> connectHealth(ProviderContainer container) async {
  final bool shown;
  try {
    shown = await container.read(healthSourceProvider).requestAuthorization();
  } on PlatformException {
    return false;
  }
  if (!shown) return false;
  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(healthConnectedKey, true);
    await prefs.setInt(healthAskedVersionKey, healthReadTypesVersion);
  } catch (_) {
    // Asked again next launch.
  }
  container.invalidate(healthConnectedProvider);
  // A read refused before the sheet was answered is kept as no samples.
  container.invalidate(_samplesProvider);
  return true;
}

sealed class HealthState {
  const HealthState();
}

/// macOS: Health lives on the iPhone.
final class HealthOnIPhone extends HealthState {
  const HealthOnIPhone();
}

final class HealthUnsupported extends HealthState {
  const HealthUnsupported();
}

final class HealthNotConnected extends HealthState {
  const HealthNotConnected();
}

/// HealthKit refuses reads while the device is locked.
final class HealthLocked extends HealthState {
  const HealthLocked();
}

final class HealthFailed extends HealthState {
  const HealthFailed();
}

/// Empty when Health has nothing for the range, which is no data, not zero.
final class HealthReady extends HealthState {
  const HealthReady(this.values);

  final List<DailyOutcome> values;
}

// sleepingHeartRate's query holds up the whole read and its cost on a year
// of nights is unmeasured: measure it on a device before reading it here.
final Set<HealthMetric> _engineMetrics = {
  for (final m in HealthMetric.values)
    if (m != HealthMetric.sleepingHeartRate) m,
};

final healthStateProvider = FutureProvider.autoDispose<HealthState>((
  ref,
) async {
  if (defaultTargetPlatform == TargetPlatform.macOS) {
    return const HealthOnIPhone();
  }
  final DateTime today = ref.watch(todayProvider);
  final ({DateTime start, DateTime end}) range = insightsRange(today);
  final HealthSource source = ref.watch(healthSourceProvider);
  final HealthStoreFile file = ref.watch(healthStoreFileProvider);
  final bool connected = await ref.watch(healthConnectedProvider.future);
  try {
    if (!await source.isAvailable()) return const HealthUnsupported();
    if (!connected) return const HealthNotConnected();
    return switch (await syncHealthDaily(
      source: source,
      file: file,
      metrics: _engineMetrics,
      range: range,
      today: today,
      // Left before the read finished: the value would be thrown away.
      alive: () => ref.mounted,
    )) {
      null => const HealthFailed(),
      HealthUnavailable() => const HealthUnsupported(),
      HealthValues(:final List<DailyOutcome> values) => HealthReady(values),
    };
  } on PlatformException catch (e) {
    return switch (e.code) {
      healthDatabaseInaccessible => const HealthLocked(),
      healthNotDetermined => const HealthNotConnected(),
      _ => const HealthFailed(),
    };
  } catch (_) {
    return const HealthFailed();
  }
});

typedef _SamplesKey = ({List<ViceActivity> activities, DateTime today});

/// How long the hours-after read may take before it is left out.
const Duration hoursAfterReadTimeout = Duration(seconds: 60);

/// The Health samples around the journal's uses that [hoursAfter] needs, by
/// [HealthSampleMetric.id]: the time in bed over the past year in one read,
/// then one span a day per measure, in pages, the measures side by side.
/// Empty when any read fails or [hoursAfterReadTimeout] passes, which leaves
/// the hours-after comparisons out rather than the page: someone who
/// connected Health before heart rate was read gets `not-determined` here,
/// and the Health card already offers the sheet again.
final _samplesProvider = FutureProvider.autoDispose
    .family<Map<String, List<HealthSample>>, _SamplesKey>((ref, key) async {
      const Map<String, List<HealthSample>> none =
          <String, List<HealthSample>>{};
      final HealthSource source = ref.read(healthSourceProvider);
      Future<List<HealthSample>?> read(
        HealthSampleMetric metric,
        List<({DateTime start, DateTime end})> spans,
      ) async {
        final List<HealthSample> got = <HealthSample>[];
        for (final ({DateTime start, DateTime end}) span in spans) {
          await for (final HealthSampleRead page in healthSamplePages(
            source,
            metric,
            span.start,
            span.end,
          )) {
            if (!ref.mounted) return null;
            switch (page) {
              case HealthUnavailable():
                return null;
              case HealthSamples(:final List<HealthSample> samples):
                got.addAll(samples);
            }
          }
        }
        return got;
      }

      Future<Map<String, List<HealthSample>>> readAll() async {
        final List<HealthSample>? bed = await read(HealthSampleMetric.bed, [
          (start: insightsBedFrom(key.today), end: startOfDay(key.today)),
        ]);
        if (bed == null || !ref.mounted) return none;
        final HoursAfterPlan plan = insightsHoursAfterPlan(
          habitUsesFrom(key.activities).toList(),
          key.today,
          bed: bed,
        );
        if (plan.reads.isEmpty) return none;
        final List<List<HealthSample>?> got = await Future.wait([
          for (final HealthSampleMetric m in insightsSampleMetrics)
            read(m, plan.reads),
        ]);
        if (got.contains(null)) return none;
        return <String, List<HealthSample>>{
          HealthSampleMetric.bed.id: bed,
          for (int i = 0; i < insightsSampleMetrics.length; i++)
            insightsSampleMetrics[i].id: got[i]!,
        };
      }

      try {
        return await readAll().timeout(hoursAfterReadTimeout);
      } catch (_) {
        return none;
      }
    });

typedef InsightsRunner = Future<InsightsReport> Function(InsightsInput input);

/// Where the engine runs: another isolate, since its cost grows with the
/// square of the habit count. Tests run it in place.
final insightsRunnerProvider = Provider<InsightsRunner>(
  (ref) => _inAnotherIsolate,
);

// Top level, so the closure sent to the isolate holds the input alone.
Future<InsightsReport> _inAnotherIsolate(InsightsInput input) =>
    Isolate.run(() => computeInsights(input));

sealed class InsightsResult {
  const InsightsResult();
}

final class InsightsComputed extends InsightsResult {
  const InsightsComputed(
    this.report, {
    this.firstDays = const <String, DateTime>{},
  });

  final InsightsReport report;

  /// Each habit's first day in the journal, by vice ID.
  final Map<String, DateTime> firstDays;
}

final class InsightsFailed extends InsightsResult {
  const InsightsFailed();
}

// Keyed on the very lists the watched providers hold, so a rebuild that
// changes neither reuses the result. The archived habits are a string, since a
// Set is equal only to itself, so renaming a habit doesn't run the engine again.
typedef _EngineKey = ({
  List<ViceActivity> activities,
  List<DailyOutcome> health,
  Map<String, List<HealthSample>> samples,
  DateTime today,
  String archived,
  List<CalendarEvent> events,
});

// A Firestore document ID never holds a '/', so it parts the IDs.
const String _archivedSeparator = '/';

final _engineProvider = FutureProvider.autoDispose
    .family<InsightsResult, _EngineKey>((ref, key) async {
      try {
        return InsightsComputed(
          await ref.read(insightsRunnerProvider)(
            InsightsInput.from(
              activities: key.activities,
              health: key.health,
              today: key.today,
              samples: key.samples,
              events: key.events,
              archived: <String>{
                if (key.archived.isNotEmpty)
                  ...key.archived.split(_archivedSeparator),
              },
            ),
          ),
          firstDays: insightsFirstDays(key.activities),
        );
      } catch (_) {
        return const InsightsFailed();
      }
    });

/// What the Insights screen shows. Loading until Health has answered and, when
/// it has values, the journal too; a journal failure is an error. With no
/// Health values the report is null: there is nothing to compare against.
/// The daily report shows first; while [hoursPending] the hours-after read
/// is still going, and the report is computed again once it lands, so a
/// daily finding can then move into the many-comparisons correction's
/// "could be chance".
typedef InsightsView = ({
  HealthState health,
  InsightsResult? result,
  bool hoursPending,
});

final insightsProvider = Provider.autoDispose<AsyncValue<InsightsView>>((ref) {
  final HealthState? state = ref.watch(healthStateProvider).value;
  if (state == null) return const AsyncLoading<InsightsView>();
  // The whole journal is read once per open, billed per document, so it is
  // read only when there is Health data to compare it with.
  if (state case HealthReady(
    :final List<DailyOutcome> values,
  ) when values.isNotEmpty) {
    final DateTime today = ref.watch(todayProvider);
    final AsyncValue<List<ViceActivity>> activities = ref.watch(
      viceActivityRangeProvider(insightsRange(today)),
    );
    if (activities case AsyncError(
      :final Object error,
      :final StackTrace stackTrace,
    )) {
      return AsyncError<InsightsView>(error, stackTrace);
    }
    final List<ViceActivity>? journal = activities.value;
    // The page says when the habits fail to load.
    final List<Vice>? vices = ref.watch(viceListProvider).value;
    if (journal == null || vices == null) {
      return const AsyncLoading<InsightsView>();
    }
    final String archived = ([
      for (final Vice v in vices)
        if (v.archived) v.id,
    ]..sort()).join(_archivedSeparator);
    final Map<String, List<HealthSample>>? samples = ref
        .watch(_samplesProvider((activities: journal, today: today)))
        .value;
    // Until the calendar answers, the report goes without it.
    final DateTime? firstDay = insightsFirstDay(
      insightsFirstDays(journal),
      (_) => true,
    );
    final List<CalendarEvent> events = firstDay == null
        ? noCalendarEvents
        : ref
                  .watch(
                    calendarEventsProvider((from: firstDay, today: today)),
                  )
                  .value ??
              noCalendarEvents;
    InsightsResult? report(Map<String, List<HealthSample>> read) => ref
        .watch(
          _engineProvider((
            activities: journal,
            health: values,
            samples: read,
            today: today,
            archived: archived,
            events: events,
          )),
        )
        .value;
    const Map<String, List<HealthSample>> none = <String, List<HealthSample>>{};
    // The daily report stays up while the one with hours-after computes.
    final InsightsResult? full = samples == null ? null : report(samples);
    final InsightsResult? shown = full ?? report(none);
    if (shown == null) return const AsyncLoading<InsightsView>();
    return AsyncData<InsightsView>((
      health: state,
      result: shown,
      hoursPending: full == null,
    ));
  }
  return AsyncData<InsightsView>((
    health: state,
    result: null,
    hoursPending: false,
  ));
});
