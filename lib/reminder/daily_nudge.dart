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
  static const String permissionWithdrawn =
      'Notifications are off for Penchant, so the reminder won\'t arrive. '
      'Turn them on in the system Settings and it will start again.';
  static const String reviewBody = 'Last week’s review is ready.';
}

/// What a press on the notification asks of the app.
enum NudgeAction { log, clean, review }

NudgeAction? nudgeActionFor(String? actionId, {String? payload}) =>
    switch (actionId) {
      _logActionId => NudgeAction.log,
      _cleanActionId => NudgeAction.clean,
      _ when payload == _reviewPayload => NudgeAction.review,
      _ => null,
    };

const String _category = 'daily-nudge';
const String _logActionId = 'log';
const String _cleanActionId = 'clean';
// One notification, so a reschedule replaces it rather than adding another.
const int _notificationId = 1;
const int _reviewNotificationId = 2;
const String _reviewPayload = 'weekly-review';

/// When the weekly review notification comes: Monday morning.
const int reviewWeekday = DateTime.monday;
const TimeOfDay reviewTime = TimeOfDay(hour: 9, minute: 0);

/// The platform side of the nudge, faked in tests.
abstract class NudgeScheduler {
  /// Declares the actions and starts hearing presses. Asks for nothing.
  Future<void> start(void Function(NudgeAction action) onAction);

  /// The action that launched the app, if one did.
  Future<NudgeAction?> launchAction();

  /// Shows the system prompt the first time; after that, the stored answer.
  Future<bool> requestPermission();

  /// Whether the system lets the app notify now. The user can withdraw it in
  /// the system Settings at any time, and the app hears nothing when they do.
  Future<bool> isPermitted();

  Future<void> scheduleDaily(TimeOfDay time);

  Future<void> cancel();

  /// Every [reviewWeekday] at [reviewTime], a tap opening the weekly review.
  Future<void> scheduleWeeklyReview();

  Future<void> cancelWeeklyReview();
}

class LocalNudgeScheduler implements NudgeScheduler {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // "Clean day" has no foreground option, so iOS handles it without bringing
  // the app forward. It may still wake a quit app in the background, where
  // the plugin finds no background handler registered and starts nothing.
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
        final NudgeAction? action = nudgeActionFor(
          response.actionId,
          payload: response.payload,
        );
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
    return nudgeActionFor(
      details.notificationResponse?.actionId,
      payload: details.notificationResponse?.payload,
    );
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

  @override
  Future<bool> isPermitted() async {
    final NotificationsEnabledOptions? options =
        await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.checkPermissions() ??
        await _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >()
            ?.checkPermissions();
    return options?.isEnabled ?? false;
  }

  // The trigger keeps the zone it was scheduled in, so the app schedules
  // again on every launch to follow a change of zone.
  @override
  Future<void> scheduleDaily(TimeOfDay time) async {
    await _setLocalZone();
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

  @override
  Future<void> scheduleWeeklyReview() async {
    await _setLocalZone();
    const DarwinNotificationDetails darwin = DarwinNotificationDetails(
      presentBadge: false,
    );
    await _plugin.zonedSchedule(
      id: _reviewNotificationId,
      body: NudgeCopy.reviewBody,
      payload: _reviewPayload,
      scheduledDate: nextWeekday(
        tz.TZDateTime.now(tz.local),
        reviewWeekday,
        reviewTime,
      ),
      notificationDetails: const NotificationDetails(
        iOS: darwin,
        macOS: darwin,
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  @override
  Future<void> cancelWeeklyReview() =>
      _plugin.cancel(id: _reviewNotificationId);

  Future<void> _setLocalZone() async {
    tz_data.initializeTimeZones();
    final String zone = (await FlutterTimezone.getLocalTimezone()).identifier;
    tz.setLocalLocation(tz.getLocation(zone));
  }
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

/// The first [time] on a [weekday] after [now], in [now]'s zone.
tz.TZDateTime nextWeekday(tz.TZDateTime now, int weekday, TimeOfDay time) {
  tz.TZDateTime next = nextOccurrence(now, time);
  while (next.weekday != weekday) {
    next = tz.TZDateTime(
      next.location,
      next.year,
      next.month,
      next.day + 1,
      time.hour,
      time.minute,
    );
  }
  return next;
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

  // Every change waits for this, so a change made while the saved setting is
  // still being read is not overwritten by it, nor saves defaults over it.
  late Future<void> _loaded;

  @override
  NudgeSettings build() {
    _loaded = _load();
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
    state = saved;
    if (saved.enabled) {
      await _schedule(saved.time);
    }
  }

  /// Turns the nudge on, asking for permission first. False if refused.
  Future<bool> turnOn() async {
    await _loaded;
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
    state = state.copyWith(enabled: true);
    await _save();
    await _schedule(state.time);
    return true;
  }

  Future<void> turnOff() async {
    await _loaded;
    state = state.copyWith(enabled: false);
    await _save();
    try {
      await ref.read(nudgeSchedulerProvider).cancel();
    } catch (e, stack) {
      reportError(e, stack, context: 'while cancelling the reminder');
    }
  }

  Future<void> setTime(TimeOfDay time) async {
    await _loaded;
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

/// Settings › Reminder's weekly review notification: off by default, kept on
/// this device only.
final weeklyReviewReminderProvider =
    NotifierProvider<WeeklyReviewReminder, bool>(WeeklyReviewReminder.new);

class WeeklyReviewReminder extends Notifier<bool> {
  static const String enabledKey = 'review.enabled';

  late Future<void> _loaded;

  @override
  bool build() {
    _loaded = _load();
    return false;
  }

  Future<void> _load() async {
    final bool saved;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      saved = prefs.getBool(enabledKey) ?? false;
    } catch (e, stack) {
      reportError(e, stack, context: 'while reading the review setting');
      return;
    }
    state = saved;
    if (saved) await _schedule();
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
    state = true;
    await _save();
    await _schedule();
    return true;
  }

  Future<void> turnOff() async {
    await _loaded;
    state = false;
    await _save();
    try {
      await ref.read(nudgeSchedulerProvider).cancelWeeklyReview();
    } catch (e, stack) {
      reportError(e, stack, context: 'while cancelling the review');
    }
  }

  Future<void> _schedule() async {
    try {
      await ref.read(nudgeSchedulerProvider).scheduleWeeklyReview();
    } catch (e, stack) {
      reportError(e, stack, context: 'while scheduling the review');
    }
  }

  Future<void> _save() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(enabledKey, state);
    } catch (e, stack) {
      reportError(e, stack, context: 'while saving the review setting');
    }
  }
}

/// A tap on the weekly review notification waiting for Today to open it.
final pendingWeeklyReviewProvider =
    NotifierProvider<PendingWeeklyReview, bool>(PendingWeeklyReview.new);

class PendingWeeklyReview extends Notifier<bool> {
  @override
  bool build() => false;

  void request() => state = true;

  void clear() => state = false;
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
    switch (action) {
      case NudgeAction.log:
        ref.read(pendingNudgeLogProvider.notifier).request();
      case NudgeAction.review:
        ref.read(pendingWeeklyReviewProvider.notifier).request();
      case NudgeAction.clean:
        break;
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
  ref.read(weeklyReviewReminderProvider);
});
