import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/crypto/sealed_files.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/insights/daily_series.dart' as series;
import 'package:tracker/insights/experiment.dart';
import 'package:tracker/insights/experiment_file.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/providers/device_files_provider.dart';
import 'package:tracker/providers/insights_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/reminder/daily_nudge.dart';

final experimentFileProvider = Provider<ExperimentFile?>((ref) {
  final SealedFiles? files = ref.watch(keptSealedFilesProvider);
  return files == null ? null : ExperimentFile(files);
});

/// The signed-in user's experiments, on this device only. Empty while no key
/// is loaded. Each build moves a plan whose last measure is in to the
/// finished ones and tops up its notifications.
final experimentProvider = AsyncNotifierProvider<Experiments, ExperimentStore>(
  Experiments.new,
);

class Experiments extends AsyncNotifier<ExperimentStore> {
  ExperimentFile? _file;

  @override
  Future<ExperimentStore> build() async {
    final ExperimentFile? file = _file = ref.watch(experimentFileProvider);
    final DateTime today = ref.watch(todayProvider);
    if (file == null) return ExperimentStore.empty;
    final ExperimentStore loaded = await file.load();
    final ExperimentStore settled = loaded.settled(today);
    if (!identical(settled, loaded)) {
      await _save(settled);
      await _cancel();
    }
    if (settled.active != null) unawaited(_schedule(settled.active));
    return settled;
  }

  ExperimentStore get _current => state.value ?? ExperimentStore.empty;

  Future<void> start(ExperimentPlan plan) async {
    await _commit(ExperimentStore(active: plan, finished: _current.finished));
    await _schedule(plan);
  }

  Future<void> stop() async {
    await _commit(ExperimentStore(finished: _current.finished));
    await _cancel();
  }

  /// [plan], finished and unclear, run on for [experimentExtendWeeks] more.
  Future<void> runOn(ExperimentPlan plan) async {
    if (_current.active != null) return;
    final ExperimentPlan next = plan.extended(
      experimentExtendWeeks,
      today: ref.read(todayProvider),
    );
    await _commit(
      ExperimentStore(
        active: next,
        finished: <ExperimentPlan>[
          for (final ExperimentPlan p in _current.finished)
            if (!identical(p, plan)) p,
        ],
      ),
    );
    await _schedule(next);
  }

  /// The running plan's notification time, or off with null.
  Future<void> setNotify(int? minutes) async {
    final ExperimentPlan? plan = _current.active;
    if (plan == null) return;
    final ExperimentPlan next = plan.copyWith(notifyMinutes: () => minutes);
    await _commit(ExperimentStore(active: next, finished: _current.finished));
    await _schedule(next);
  }

  /// Shows the system prompt the first time. False if refused or failed.
  Future<bool> askToNotify() async {
    try {
      return await ref.read(nudgeSchedulerProvider).requestPermission();
    } catch (e, stack) {
      reportError(e, stack, context: 'while asking to send notifications');
      return false;
    }
  }

  Future<void> _commit(ExperimentStore next) async {
    state = AsyncData<ExperimentStore>(next);
    await _save(next);
  }

  Future<void> _save(ExperimentStore next) async {
    try {
      await _file?.save(next);
    } catch (e, stack) {
      // Kept in memory until the app closes.
      reportError(e, stack, context: 'while saving the experiment');
    }
  }

  Future<void> _schedule(ExperimentPlan? plan) async {
    if (plan == null) return;
    try {
      await ref
          .read(nudgeSchedulerProvider)
          .scheduleExperiment(experimentNotices(plan, DateTime.now()));
    } catch (e, stack) {
      reportError(e, stack, context: 'while scheduling the experiment');
    }
  }

  Future<void> _cancel() async {
    try {
      await ref.read(nudgeSchedulerProvider).cancelExperiment();
    } catch (e, stack) {
      reportError(e, stack, context: 'while cancelling the experiment');
    }
  }
}

/// [metricId]'s Health values by local day, several in a day averaged.
Map<DateTime, double> experimentOutcomes(
  List<DailyOutcome> values,
  String metricId,
) => series.OutcomeSeries.fromOutcomes(<series.DailyOutcome>[
  for (final DailyOutcome o in values)
    if (o.metricId == metricId)
      series.DailyOutcome(date: o.date, metricId: o.metricId, value: o.value),
]).days(metricId);

typedef ExperimentCard = ({ExperimentPlan plan, ExperimentResult result});

/// Each finished plan's result, newest first, from Health and the journal
/// as Insights reads them; null while either loads.
final experimentResultsProvider = Provider.autoDispose<List<ExperimentCard>?>((
  ref,
) {
  final List<ExperimentPlan> finished =
      ref.watch(experimentProvider).value?.finished ?? const <ExperimentPlan>[];
  if (finished.isEmpty) return const <ExperimentCard>[];
  final HealthState? health = ref.watch(healthStateProvider).value;
  if (health is! HealthReady) return null;
  final DateTime today = ref.watch(todayProvider);
  final List<ViceActivity>? journal = ref
      .watch(viceActivityRangeProvider(insightsRange(today)))
      .value;
  if (journal == null) return null;
  return <ExperimentCard>[
    for (final ExperimentPlan plan in finished)
      (
        plan: plan,
        result: analyseExperiment(
          plan,
          outcomes: experimentOutcomes(health.values, plan.metricId),
          uses: <DateTime>[
            for (final ViceActivity a in journal)
              if (a.viceID == plan.habitId &&
                  a.measure > 0 &&
                  !a.createdAt.toDate().isBefore(plan.start))
                a.createdAt.toDate(),
          ],
        ),
      ),
  ];
});

/// [metricId]'s spread over the last 90 days, for the plan screen; null
/// while Health loads or with too few values.
final experimentSpreadProvider = Provider.autoDispose.family<double?, String>((
  ref,
  metricId,
) {
  final HealthState? health = ref.watch(healthStateProvider).value;
  if (health is! HealthReady) return null;
  return experimentSpread(
    experimentOutcomes(health.values, metricId),
    startOfDay(ref.watch(todayProvider)),
  );
});
