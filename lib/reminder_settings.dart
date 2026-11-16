import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/reminder/check_ins.dart';
import 'package:tracker/reminder/daily_nudge.dart';
import 'package:tracker/reminder/heavy_day_nudge.dart';
import 'package:tracker/widgets/settings_card.dart';

/// The time as the device writes it, in 12- or 24-hour form.
String nudgeTimeLabel(BuildContext context, TimeOfDay time) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      time,
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

/// Settings › Reminder: one optional notification a day, one a week, the
/// heavy-day question and random check-ins.
class ReminderSettings extends ConsumerStatefulWidget {
  const ReminderSettings({super.key});

  static const String route = '/settings/reminder';
  static const String switchLabel = 'Daily reminder';
  static const String timeLabel = 'Time';
  static const String foot =
      'One quiet notification a day. Press and hold it to log something or '
      'to mark a clean day. Saved on this device only.';
  static const String reviewLabel = 'Weekly review';
  static const String reviewFoot =
      'Monday at 9:00, a note that last week’s review is ready. It says '
      'nothing about your journal. Saved on this device only.';
  static const String heavyLabel = 'Ask about heavy days';
  static const String heavyTimeLabel = 'Ask at';
  static const String heavyFoot =
      'On a day you log more of a habit than on nine in ten of your days '
      'with it in the last 90, one notification asks what was different. It '
      'never names the habit. Saved on this device only.';
  static const String checkInLabel = 'Random check-ins';
  static const String checkInFromLabel = 'From';
  static const String checkInUntilLabel = 'Until';
  static const String checkInFoot =
      'Three times a day, at moments drawn at random between these times, a '
      'quiet notification asks “Any urge right now?”. Press and hold it to '
      'answer 0 to 5. It never names a habit. Your answers are sealed in your '
      'journal, so Penchant can later compare urges at your entries with '
      'urges at ordinary moments. Turn it off here or from any check-in.';
  static const String checkInWindowTooShort =
      'Leave at least 3 hours between From and Until, on the same day.';

  @override
  ConsumerState<ReminderSettings> createState() => _ReminderSettingsState();
}

class _ReminderSettingsState extends ConsumerState<ReminderSettings> {
  bool _asking = false;
  bool _refused = false;
  bool _reviewRefused = false;
  bool _heavyRefused = false;
  bool _checkInRefused = false;
  bool _checkInWindowRefused = false;
  // Null until known. Checked on opening and on return from the system
  // Settings, where the user can withdraw it without the app hearing.
  bool? _permitted;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _checkPermission);
    _checkPermission();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _checkPermission() async {
    final bool permitted;
    try {
      permitted = await ref.read(nudgeSchedulerProvider).isPermitted();
    } catch (e, stack) {
      reportError(e, stack, context: 'while checking notification permission');
      return;
    }
    if (mounted) {
      setState(() => _permitted = permitted);
    }
  }

  Future<void> _toggle(bool on) async {
    final DailyNudge nudge = ref.read(dailyNudgeProvider.notifier);
    if (!on) {
      setState(() => _refused = false);
      await nudge.turnOff();
      return;
    }
    setState(() => _asking = true);
    final bool granted = await nudge.turnOn();
    if (mounted) {
      setState(() {
        _asking = false;
        _refused = !granted;
        _permitted = granted;
      });
    }
  }

  Future<void> _toggleReview(bool on) async {
    final WeeklyReviewReminder review = ref.read(
      weeklyReviewReminderProvider.notifier,
    );
    if (!on) {
      setState(() => _reviewRefused = false);
      await review.turnOff();
      return;
    }
    setState(() => _asking = true);
    final bool granted = await review.turnOn();
    if (mounted) {
      setState(() {
        _asking = false;
        _reviewRefused = !granted;
        _permitted = granted;
      });
    }
  }

  Future<void> _toggleHeavy(bool on) async {
    final HeavyDayNudge heavy = ref.read(heavyDayNudgeProvider.notifier);
    if (!on) {
      setState(() => _heavyRefused = false);
      await heavy.turnOff();
      return;
    }
    setState(() => _asking = true);
    final bool granted = await heavy.turnOn();
    if (mounted) {
      setState(() {
        _asking = false;
        _heavyRefused = !granted;
        _permitted = granted;
      });
    }
  }

  Future<void> _pickHeavyTime(TimeOfDay current) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: current,
    );
    if (picked != null) {
      await ref.read(heavyDayNudgeProvider.notifier).setTime(picked);
    }
  }

  Future<void> _toggleCheckIns(bool on) async {
    final CheckIns checkIns = ref.read(checkInsProvider.notifier);
    if (!on) {
      setState(() => _checkInRefused = false);
      await checkIns.turnOff();
      return;
    }
    setState(() => _asking = true);
    final bool granted = await checkIns.turnOn();
    if (mounted) {
      setState(() {
        _asking = false;
        _checkInRefused = !granted;
        _permitted = granted;
      });
    }
  }

  Future<void> _pickCheckInTime(
    CheckInWindow window, {
    required bool start,
  }) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: start ? window.start : window.end,
    );
    if (picked == null) return;
    final bool saved = await ref
        .read(checkInsProvider.notifier)
        .setWindow(
          start
              ? CheckInWindow(picked, window.end)
              : CheckInWindow(window.start, picked),
        );
    if (mounted) {
      setState(() => _checkInWindowRefused = !saved);
    }
  }

  Future<void> _pickTime(TimeOfDay current) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: current,
    );
    if (picked != null) {
      await ref.read(dailyNudgeProvider.notifier).setTime(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final NudgeSettings settings = ref.watch(dailyNudgeProvider);
    final String time = nudgeTimeLabel(context, settings.time);
    final bool withdrawn = settings.enabled && _permitted == false;
    final bool on = settings.enabled && !withdrawn;
    final bool reviewOn =
        ref.watch(weeklyReviewReminderProvider) && _permitted != false;
    final NudgeSettings heavy = ref.watch(heavyDayNudgeProvider);
    final bool heavyWithdrawn = heavy.enabled && _permitted == false;
    final bool heavyOn = heavy.enabled && !heavyWithdrawn;
    final CheckInSettings checkIns = ref.watch(checkInsProvider);
    final bool checkInsWithdrawn = checkIns.enabled && _permitted == false;
    final bool checkInsOn = checkIns.enabled && !checkInsWithdrawn;
    const TextStyle mono = TextStyle(
      fontFamily: DialFonts.mono,
      fontFeatures: DialFonts.tabular,
    );
    return CardPage(
      title: 'Reminder',
      children: <Widget>[
        DialCard(
          children: <Widget>[
            MergeSemantics(
              child: CardRow(
                label: ReminderSettings.switchLabel,
                enabled: !_asking,
                onTap: () => _toggle(!on),
                trailing: Switch.adaptive(
                  value: on,
                  activeTrackColor: Theme.of(context).colorScheme.primary,
                  onChanged: _asking ? null : _toggle,
                ),
              ),
            ),
            CardRow(
              label: ReminderSettings.timeLabel,
              value: Text(
                time,
                style: const TextStyle(
                  fontFamily: DialFonts.mono,
                  fontFeatures: DialFonts.tabular,
                ),
              ),
              glyph: DialGlyph.right,
              onTap: () => _pickTime(settings.time),
            ),
          ],
        ),
        CardFoot(
          _refused
              ? NudgeCopy.permissionDenied
              : withdrawn
              ? NudgeCopy.permissionWithdrawn
              : ReminderSettings.foot,
        ),
        DialCard(
          children: <Widget>[
            MergeSemantics(
              child: CardRow(
                label: ReminderSettings.reviewLabel,
                enabled: !_asking,
                onTap: () => _toggleReview(!reviewOn),
                trailing: Switch.adaptive(
                  value: reviewOn,
                  activeTrackColor: Theme.of(context).colorScheme.primary,
                  onChanged: _asking ? null : _toggleReview,
                ),
              ),
            ),
          ],
        ),
        CardFoot(
          _reviewRefused
              ? NudgeCopy.permissionDenied
              : ReminderSettings.reviewFoot,
        ),
        DialCard(
          children: <Widget>[
            MergeSemantics(
              child: CardRow(
                label: ReminderSettings.heavyLabel,
                enabled: !_asking,
                onTap: () => _toggleHeavy(!heavyOn),
                trailing: Switch.adaptive(
                  value: heavyOn,
                  activeTrackColor: Theme.of(context).colorScheme.primary,
                  onChanged: _asking ? null : _toggleHeavy,
                ),
              ),
            ),
            CardRow(
              label: ReminderSettings.heavyTimeLabel,
              value: Text(
                nudgeTimeLabel(context, heavy.time),
                style: const TextStyle(
                  fontFamily: DialFonts.mono,
                  fontFeatures: DialFonts.tabular,
                ),
              ),
              glyph: DialGlyph.right,
              onTap: () => _pickHeavyTime(heavy.time),
            ),
          ],
        ),
        CardFoot(
          _heavyRefused
              ? NudgeCopy.permissionDenied
              : heavyWithdrawn
              ? NudgeCopy.permissionWithdrawn
              : ReminderSettings.heavyFoot,
        ),
        DialCard(
          children: <Widget>[
            MergeSemantics(
              child: CardRow(
                label: ReminderSettings.checkInLabel,
                enabled: !_asking,
                onTap: () => _toggleCheckIns(!checkInsOn),
                trailing: Switch.adaptive(
                  value: checkInsOn,
                  activeTrackColor: Theme.of(context).colorScheme.primary,
                  onChanged: _asking ? null : _toggleCheckIns,
                ),
              ),
            ),
            CardRow(
              label: ReminderSettings.checkInFromLabel,
              value: Text(
                nudgeTimeLabel(context, checkIns.window.start),
                style: mono,
              ),
              glyph: DialGlyph.right,
              onTap: () => _pickCheckInTime(checkIns.window, start: true),
            ),
            CardRow(
              label: ReminderSettings.checkInUntilLabel,
              value: Text(
                nudgeTimeLabel(context, checkIns.window.end),
                style: mono,
              ),
              glyph: DialGlyph.right,
              onTap: () => _pickCheckInTime(checkIns.window, start: false),
            ),
          ],
        ),
        CardFoot(
          _checkInRefused
              ? NudgeCopy.permissionDenied
              : checkInsWithdrawn
              ? NudgeCopy.permissionWithdrawn
              : _checkInWindowRefused
              ? ReminderSettings.checkInWindowTooShort
              : ReminderSettings.checkInFoot,
        ),
      ],
    );
  }
}
