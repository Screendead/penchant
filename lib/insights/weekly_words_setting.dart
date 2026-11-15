import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/widgets/settings_card.dart';

/// Whether this device sends last week's figures to be put into words: off
/// until the person turns it on in Settings, kept on this device only.
final weeklyWordsEnabledProvider = NotifierProvider<WeeklyWordsEnabled, bool>(
  WeeklyWordsEnabled.new,
);

class WeeklyWordsEnabled extends Notifier<bool> {
  static const String key = 'weeklyWords';

  bool _chosen = false;

  @override
  bool build() {
    _load();
    return false;
  }

  // A failed read leaves it off.
  Future<void> _load() async {
    final bool? saved;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      saved = prefs.getBool(key);
    } catch (e, stack) {
      reportError(e, stack, context: 'while reading the weekly words choice');
      return;
    }
    // A choice made while the read was in flight is newer than what it read.
    if (saved != null && !_chosen) {
      state = saved;
    }
  }

  Future<void> choose(bool on) async {
    _chosen = true;
    state = on;
    // A failed save still applies the choice until the app closes.
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, on);
    } catch (e, stack) {
      reportError(e, stack, context: 'while saving the weekly words choice');
    }
  }
}

/// The Settings row for [weeklyWordsEnabledProvider]. Turning it on first
/// says what is sent and what is not, and asks again; turning it off needs no
/// asking.
class WeeklyWordsSetting extends ConsumerWidget {
  const WeeklyWordsSetting({super.key});

  static const String label = 'Last week in words';
  static const String subtitle =
      'Claude writes the week’s figures as a short paragraph.';
  static const String disclosureTitle = 'Send last week’s figures?';
  static const String disclosure =
      'When you open Last week, the figures it lists are sent to Penchant’s '
      'server and on to Anthropic’s Claude, which writes them as a short '
      'paragraph: each habit’s total, usual week, entries and days, the '
      'busiest hours, the tags from Penchant’s list, and the summary lines of '
      'findings that are new or no longer hold. Habits go as Habit A, '
      'Habit B, with their units, including any you named. Your habits’ '
      'names, entries, notes, tags in your own words (only how many) and Health '
      'values are not sent (a mood finding is said in words); the names are put back on this device. Anthropic does not use it '
      'for training. Switch this off to stop sending.';
  static const String turnOn = 'Turn on';
  static const String notNow = 'Not now';

  Future<void> _set(BuildContext context, WidgetRef ref, bool on) async {
    final WeeklyWordsEnabled notifier = ref.read(
      weeklyWordsEnabledProvider.notifier,
    );
    if (!on) {
      await notifier.choose(false);
      return;
    }
    final bool? agreed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text(disclosureTitle),
        content: const Text(disclosure),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(notNow),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(turnOn),
          ),
        ],
      ),
    );
    if (agreed ?? false) await notifier.choose(true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool on = ref.watch(weeklyWordsEnabledProvider);
    return MergeSemantics(
      child: CardRow(
        label: label,
        subtitle: subtitle,
        onTap: () => _set(context, ref, !on),
        trailing: Switch.adaptive(
          value: on,
          activeTrackColor: Theme.of(context).colorScheme.primary,
          onChanged: (bool value) => _set(context, ref, value),
        ),
      ),
    );
  }
}
