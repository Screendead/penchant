import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/reminder/daily_nudge.dart';
import 'package:tracker/widgets/settings_card.dart';

/// The time as the device writes it, in 12- or 24-hour form.
String nudgeTimeLabel(BuildContext context, TimeOfDay time) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      time,
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

/// Settings › Reminder: one optional notification a day.
class ReminderSettings extends ConsumerStatefulWidget {
  const ReminderSettings({super.key});

  static const String route = '/settings/reminder';
  static const String switchLabel = 'Daily reminder';
  static const String timeLabel = 'Time';
  static const String foot =
      'One quiet notification a day. Press and hold it to log something or '
      'to mark a clean day. Saved on this device only.';

  @override
  ConsumerState<ReminderSettings> createState() => _ReminderSettingsState();
}

class _ReminderSettingsState extends ConsumerState<ReminderSettings> {
  bool _asking = false;
  bool _refused = false;
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
      ],
    );
  }
}
