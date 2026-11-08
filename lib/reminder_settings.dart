import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/tokens.dart';
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
    return CardPage(
      title: 'Reminder',
      children: <Widget>[
        DialCard(
          children: <Widget>[
            MergeSemantics(
              child: CardRow(
                label: ReminderSettings.switchLabel,
                enabled: !_asking,
                onTap: () => _toggle(!settings.enabled),
                trailing: Switch.adaptive(
                  value: settings.enabled,
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
        CardFoot(_refused ? NudgeCopy.permissionDenied : ReminderSettings.foot),
      ],
    );
  }
}
