import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';

// Health values stay on the device: ReportProviderErrors sends every provider
// failure to Crashlytics, so nothing below that reads or derives from Health
// may fail. Each returns its failure as a value instead.

final healthSourceProvider = Provider<HealthSource>(
  (ref) => ChannelHealthSource(),
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
  } catch (_) {
    // Asked again next launch.
  }
  container.invalidate(healthConnectedProvider);
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

final healthStateProvider = FutureProvider.autoDispose<HealthState>((
  ref,
) async {
  if (defaultTargetPlatform == TargetPlatform.macOS) {
    return const HealthOnIPhone();
  }
  final ({DateTime start, DateTime end}) range = insightsRange(
    ref.watch(todayProvider),
  );
  final HealthSource source = ref.watch(healthSourceProvider);
  final bool connected = await ref.watch(healthConnectedProvider.future);
  try {
    if (!await source.isAvailable()) return const HealthUnsupported();
    if (!connected) return const HealthNotConnected();
    return switch (await source.dailyValues(
      HealthMetric.values.toSet(),
      range.start,
      range.end,
    )) {
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
  const InsightsComputed(this.report);

  final InsightsReport report;
}

final class InsightsFailed extends InsightsResult {
  const InsightsFailed();
}

// Keyed on the very lists the watched providers hold, so a rebuild that
// changes neither reuses the result.
typedef _EngineKey = ({
  List<ViceActivity> activities,
  List<DailyOutcome> health,
  DateTime today,
});

final _engineProvider = FutureProvider.autoDispose
    .family<InsightsResult, _EngineKey>((ref, key) async {
      try {
        return InsightsComputed(
          await ref.read(insightsRunnerProvider)(
            InsightsInput.from(
              activities: key.activities,
              health: key.health,
              today: key.today,
            ),
          ),
        );
      } catch (_) {
        return const InsightsFailed();
      }
    });

/// What the Insights screen shows. Loading until Health has answered and, when
/// it has values, the journal too; a journal failure is an error. With no
/// Health values the report is null: there is nothing to compare against.
typedef InsightsView = ({HealthState health, InsightsResult? result});

final insightsProvider = Provider.autoDispose<AsyncValue<InsightsView>>((ref) {
  final HealthState? state = ref.watch(healthStateProvider).value;
  if (state == null) return const AsyncLoading<InsightsView>();
  // The year of the journal is a live query billed per document, so it is
  // opened only when there is Health data to compare it with.
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
    if (journal == null) return const AsyncLoading<InsightsView>();
    final AsyncValue<InsightsResult> result = ref.watch(
      _engineProvider((activities: journal, health: values, today: today)),
    );
    return switch (result.value) {
      final InsightsResult r => AsyncData<InsightsView>((
        health: state,
        result: r,
      )),
      null => const AsyncLoading<InsightsView>(),
    };
  }
  return AsyncData<InsightsView>((health: state, result: null));
});
