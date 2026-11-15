import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/reminder/daily_nudge.dart';
import 'package:tracker/reminder/heavy_day.dart';

/// Whether today and yesterday are heavy for any unarchived habit.
typedef HeavyDayVerdict = ({bool today, bool yesterday});

/// Null while the setting is off or anything it needs is loading. Today's
/// entries come from Today's live day query; the 91 days before today from
/// one bounded `get()` (the Insights range query's shape), read again only
/// when the day moves on, so today's baseline and yesterday's both come from
/// it.
final heavyDayVerdictProvider = Provider.autoDispose<HeavyDayVerdict?>((ref) {
  if (!ref.watch(
    heavyDayNudgeProvider.select((NudgeSettings s) => s.enabled),
  )) {
    return null;
  }
  // The range query reads again once a key loads; waiting reads it once.
  if (ref.watch(sealerProvider) == null) return null;
  final DateTime today = ref.watch(todayProvider);
  final List<Vice>? habits = ref.watch(unarchivedViceListProvider).value;
  final List<ViceActivity>? todays = ref
      .watch(viceActivityDayProvider(today))
      .value;
  final List<ViceActivity>? history = ref
      .watch(
        viceActivityRangeProvider((
          start: addDays(today, -heavyWindowDays - 1),
          end: today,
        )),
      )
      .value;
  if (habits == null || todays == null || history == null) return null;
  return (
    today: heavyDayOf(
      day: today,
      habits: habits,
      entries: <ViceActivity>[...history, ...todays],
    ),
    yesterday: heavyDayOf(
      day: addDays(today, -1),
      habits: habits,
      entries: history,
    ),
  );
});

/// Settings › Reminder's heavy-day question: off by default, kept on this
/// device only, with the prompts already scheduled (dates and times only).
final heavyDayNudgeProvider = NotifierProvider<HeavyDayNudge, NudgeSettings>(
  HeavyDayNudge.new,
);

class HeavyDayNudge extends Notifier<NudgeSettings> {
  static const String enabledKey = 'heavy.enabled';
  static const String minutesKey = 'heavy.minutes';
  static const String promptsKey = 'heavy.prompts';
  static const int keptDays = 7;

  late Future<void> _loaded;
  List<HeavyPrompt> _prompts = <HeavyPrompt>[];
  HeavyDayVerdict? _last;
  // Evaluations run one at a time, so two cannot both schedule.
  Future<void> _queue = Future<void>.value();

  @override
  NudgeSettings build() {
    // The set time may have passed while hidden, with nothing else changed.
    final AppLifecycleListener lifecycle = AppLifecycleListener(
      onResume: () => _enqueue(_apply),
    );
    ref.onDispose(lifecycle.dispose);
    _loaded = _load();
    return NudgeSettings.off;
  }

  Future<void> _load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final int? minutes = prefs.getInt(minutesKey);
      _prompts = <HeavyPrompt>[
        for (final String s in prefs.getStringList(promptsKey) ?? <String>[])
          ?HeavyPrompt.decode(s),
      ];
      state = NudgeSettings(
        enabled: prefs.getBool(enabledKey) ?? false,
        time: minutes == null
            ? NudgeSettings.defaultTime
            : TimeOfDay(hour: minutes ~/ 60 % 24, minute: minutes % 60),
      );
    } catch (e, stack) {
      reportError(e, stack, context: 'while reading the heavy-day setting');
    }
  }

  /// Schedules or cancels the one notification for [verdict].
  Future<void> evaluate(HeavyDayVerdict verdict) {
    _last = verdict;
    return _enqueue(_apply);
  }

  /// Turns it on, asking for permission first. False if refused.
  Future<bool> turnOn() async {
    await _loaded;
    final bool granted;
    try {
      granted = await ref.read(nudgeSchedulerProvider).requestPermission();
    } catch (e, stack) {
      reportError(e, stack, context: 'while asking to send notifications');
      return false;
    }
    if (!granted) return false;
    state = state.copyWith(enabled: true);
    await _saveSettings();
    await _enqueue(_apply);
    return true;
  }

  Future<void> turnOff() async {
    await _loaded;
    state = state.copyWith(enabled: false);
    await _saveSettings();
    await _enqueue(_apply);
  }

  Future<void> setTime(TimeOfDay time) async {
    await _loaded;
    state = state.copyWith(time: time);
    await _saveSettings();
    await _enqueue(_apply);
  }

  /// On sign-out and deletion: the pending one goes, and with it the record.
  Future<void> forget() => _enqueue(() async {
    await _loaded;
    _last = null;
    _prompts = <HeavyPrompt>[];
    await _savePrompts();
    try {
      await ref.read(nudgeSchedulerProvider).cancelHeavyDay();
    } catch (e, stack) {
      reportError(e, stack, context: 'while cancelling the heavy-day prompt');
    }
  });

  Future<void> _enqueue(Future<void> Function() step) => _queue = _queue
      .then((_) => step())
      .catchError(
        (Object e, StackTrace stack) => reportError(
          e,
          stack,
          context: 'while updating the heavy-day prompt',
        ),
      );

  Future<void> _apply() async {
    await _loaded;
    final DateTime now = clock.now();
    final HeavyPrompt? pending = <HeavyPrompt?>[
      for (final HeavyPrompt p in _prompts)
        if (p.at.isAfter(now)) p,
      null,
    ].first;
    final List<HeavyPrompt> fired = <HeavyPrompt>[
      for (final HeavyPrompt p in _prompts)
        if (!p.at.isAfter(now)) p,
    ];
    final HeavyDayVerdict? verdict = _last;
    final HeavyPrompt? planned;
    if (!state.enabled) {
      planned = null;
    } else if (verdict == null) {
      return;
    } else {
      planned = plannedHeavyPrompt(
        now: now,
        time: state.time,
        todayHeavy: verdict.today,
        yesterdayHeavy: verdict.yesterday,
        fired: fired,
      );
    }
    if (planned == pending) return;
    final NudgeScheduler scheduler = ref.read(nudgeSchedulerProvider);
    try {
      if (planned == null) {
        await scheduler.cancelHeavyDay();
      } else {
        await scheduler.scheduleHeavyDay(planned);
      }
    } catch (e, stack) {
      reportError(e, stack, context: 'while scheduling the heavy-day prompt');
      return;
    }
    final DateTime oldest = addDays(startOfDay(now), -keptDays);
    _prompts = <HeavyPrompt>[
      for (final HeavyPrompt p in fired)
        if (!p.about.isBefore(oldest)) p,
      ?planned,
    ];
    await _savePrompts();
  }

  // A failed save still applies the choice until the app closes.
  Future<void> _saveSettings() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(enabledKey, state.enabled);
      await prefs.setInt(minutesKey, state.time.hour * 60 + state.time.minute);
    } catch (e, stack) {
      reportError(e, stack, context: 'while saving the heavy-day setting');
    }
  }

  Future<void> _savePrompts() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(promptsKey, <String>[
        for (final HeavyPrompt p in _prompts) p.encode(),
      ]);
    } catch (e, stack) {
      reportError(e, stack, context: 'while saving the heavy-day prompts');
    }
  }
}
