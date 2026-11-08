import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:tracker/errors/report_error.dart';

/// The words of the daily nudge, kept neutral (C16): no streaks, no guilt.
class NudgeCopy {
  static const String body = 'Anything to add to today?';
  static const String logAction = 'Log something';
  static const String cleanAction = 'Clean day';
  static const String permissionDenied =
      'Notifications are off for Penchant. Turn them on in the system '
      'Settings, then try again.';
}

/// What a press on the notification asks of the app.
enum NudgeAction { log, clean }

NudgeAction? nudgeActionFor(String? actionId) => switch (actionId) {
  _logActionId => NudgeAction.log,
  _cleanActionId => NudgeAction.clean,
  _ => null,
};

const String _category = 'daily-nudge';
const String _logActionId = 'log';
const String _cleanActionId = 'clean';
// One notification, so a reschedule replaces it rather than adding another.
const int _notificationId = 1;

/// The platform side of the nudge, faked in tests.
abstract class NudgeScheduler {
  /// Declares the actions and starts hearing presses. Asks for nothing.
  Future<void> start(void Function(NudgeAction action) onAction);

  /// The action that launched the app, if one did.
  Future<NudgeAction?> launchAction();

  /// Shows the system prompt the first time; after that, the stored answer.
  Future<bool> requestPermission();

  Future<void> scheduleDaily(TimeOfDay time);

  Future<void> cancel();
}

class LocalNudgeScheduler implements NudgeScheduler {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // "Clean day" has no foreground option, so iOS handles it without opening
  // the app; with no background handler registered, nothing runs.
  static final List<DarwinNotificationCategory> _categories =
      <DarwinNotificationCategory>[
        DarwinNotificationCategory(
          _category,
          actions: <DarwinNotificationAction>[
            DarwinNotificationAction.plain(
              _logActionId,
              NudgeCopy.logAction,
              options: <DarwinNotificationActionOption>{
                DarwinNotificationActionOption.foreground,
              },
            ),
            DarwinNotificationAction.plain(
              _cleanActionId,
              NudgeCopy.cleanAction,
            ),
          ],
        ),
      ];

  @override
  Future<void> start(void Function(NudgeAction action) onAction) async {
    final DarwinInitializationSettings darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestSoundPermission: false,
      requestBadgePermission: false,
      notificationCategories: _categories,
    );
    await _plugin.initialize(
      settings: InitializationSettings(iOS: darwin, macOS: darwin),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final NudgeAction? action = nudgeActionFor(response.actionId);
        if (action != null) {
          onAction(action);
        }
      },
    );
  }

  @override
  Future<NudgeAction?> launchAction() async {
    final NotificationAppLaunchDetails? details = await _plugin
        .getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) {
      return null;
    }
    return nudgeActionFor(details.notificationResponse?.actionId);
  }

  @override
  Future<bool> requestPermission() async {
    final bool? granted =
        await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, sound: true) ??
        await _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, sound: true);
    return granted ?? false;
  }

  // The trigger keeps the zone it was scheduled in, so the app schedules
  // again on every launch to follow a change of zone.
  @override
  Future<void> scheduleDaily(TimeOfDay time) async {
    tz_data.initializeTimeZones();
    final String zone = (await FlutterTimezone.getLocalTimezone()).identifier;
    tz.setLocalLocation(tz.getLocation(zone));
    const DarwinNotificationDetails darwin = DarwinNotificationDetails(
      categoryIdentifier: _category,
      presentBadge: false,
    );
    await _plugin.zonedSchedule(
      id: _notificationId,
      body: NudgeCopy.body,
      scheduledDate: nextOccurrence(tz.TZDateTime.now(tz.local), time),
      notificationDetails: const NotificationDetails(
        iOS: darwin,
        macOS: darwin,
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  @override
  Future<void> cancel() => _plugin.cancel(id: _notificationId);
}

/// The first [time] after [now], in [now]'s zone.
tz.TZDateTime nextOccurrence(tz.TZDateTime now, TimeOfDay time) {
  final tz.TZDateTime today = tz.TZDateTime(
    now.location,
    now.year,
    now.month,
    now.day,
    time.hour,
    time.minute,
  );
  return today.isAfter(now)
      ? today
      : tz.TZDateTime(
          now.location,
          now.year,
          now.month,
          now.day + 1,
          time.hour,
          time.minute,
        );
}

final nudgeSchedulerProvider = Provider<NudgeScheduler>(
  (Ref ref) => LocalNudgeScheduler(),
);

@immutable
class NudgeSettings {
  const NudgeSettings({required this.enabled, required this.time});

  static const TimeOfDay defaultTime = TimeOfDay(hour: 21, minute: 0);
  static const NudgeSettings off = NudgeSettings(
    enabled: false,
    time: defaultTime,
  );

  final bool enabled;
  final TimeOfDay time;

  NudgeSettings copyWith({bool? enabled, TimeOfDay? time}) =>
      NudgeSettings(enabled: enabled ?? this.enabled, time: time ?? this.time);

  @override
  bool operator ==(Object other) =>
      other is NudgeSettings && other.enabled == enabled && other.time == time;

  @override
  int get hashCode => Object.hash(enabled, time);
}

/// Settings › Reminder: off by default, kept on this device only.
final dailyNudgeProvider = NotifierProvider<DailyNudge, NudgeSettings>(
  DailyNudge.new,
);

class DailyNudge extends Notifier<NudgeSettings> {
  static const String enabledKey = 'nudge.enabled';
  static const String minutesKey = 'nudge.minutes';

  bool _chosen = false;

  @override
  NudgeSettings build() {
    _load();
    return NudgeSettings.off;
  }

  Future<void> _load() async {
    final NudgeSettings saved;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final int? minutes = prefs.getInt(minutesKey);
      saved = NudgeSettings(
        enabled: prefs.getBool(enabledKey) ?? false,
        time: minutes == null
            ? NudgeSettings.defaultTime
            : TimeOfDay(hour: minutes ~/ 60 % 24, minute: minutes % 60),
      );
    } catch (e, stack) {
      reportError(e, stack, context: 'while reading the reminder setting');
      return;
    }
    // A choice made while the read was in flight is newer than what it read.
    if (_chosen) {
      return;
    }
    state = saved;
    if (saved.enabled) {
      await _schedule(saved.time);
    }
  }

  /// Turns the nudge on, asking for permission first. False if refused.
  Future<bool> turnOn() async {
    final NudgeScheduler scheduler = ref.read(nudgeSchedulerProvider);
    final bool granted;
    try {
      granted = await scheduler.requestPermission();
    } catch (e, stack) {
      reportError(e, stack, context: 'while asking to send notifications');
      return false;
    }
    if (!granted) {
      return false;
    }
    _chosen = true;
    state = state.copyWith(enabled: true);
    await _save();
    await _schedule(state.time);
    return true;
  }

  Future<void> turnOff() async {
    _chosen = true;
    state = state.copyWith(enabled: false);
    await _save();
    try {
      await ref.read(nudgeSchedulerProvider).cancel();
    } catch (e, stack) {
      reportError(e, stack, context: 'while cancelling the reminder');
    }
  }

  Future<void> setTime(TimeOfDay time) async {
    _chosen = true;
    state = state.copyWith(time: time);
    await _save();
    if (state.enabled) {
      await _schedule(time);
    }
  }

  Future<void> _schedule(TimeOfDay time) async {
    try {
      await ref.read(nudgeSchedulerProvider).scheduleDaily(time);
    } catch (e, stack) {
      reportError(e, stack, context: 'while scheduling the reminder');
    }
  }

  // A failed save still applies the choice until the app closes.
  Future<void> _save() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(enabledKey, state.enabled);
      await prefs.setInt(minutesKey, state.time.hour * 60 + state.time.minute);
    } catch (e, stack) {
      reportError(e, stack, context: 'while saving the reminder setting');
    }
  }
}

/// A "Log something" press waiting for Today to open the Log. It waits through
/// sign-in, so a press made while signed out opens it once Today shows.
final pendingNudgeLogProvider = NotifierProvider<PendingNudgeLog, bool>(
  PendingNudgeLog.new,
);

class PendingNudgeLog extends Notifier<bool> {
  @override
  bool build() => false;

  void request() => state = true;

  void clear() => state = false;
}

/// Hears the notification's actions for the life of the app; MyApp keeps it
/// alive. "Clean day" writes nothing: the press itself is the point.
final dailyNudgeStartupProvider = FutureProvider<void>((Ref ref) async {
  if (defaultTargetPlatform != TargetPlatform.iOS &&
      defaultTargetPlatform != TargetPlatform.macOS) {
    return;
  }
  final NudgeScheduler scheduler = ref.read(nudgeSchedulerProvider);
  void onAction(NudgeAction action) {
    if (action == NudgeAction.log) {
      ref.read(pendingNudgeLogProvider.notifier).request();
    }
  }

  try {
    await scheduler.start(onAction);
    final NudgeAction? launched = await scheduler.launchAction();
    if (launched != null) {
      onAction(launched);
    }
  } catch (e, stack) {
    reportError(e, stack, context: 'while starting notifications');
  }
  // Reads the saved setting, which schedules again if it is on.
  ref.read(dailyNudgeProvider);
});
