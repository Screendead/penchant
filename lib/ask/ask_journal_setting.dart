import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/widgets/settings_card.dart';

/// Whether this device sends questions to be turned into queries: off until
/// the person turns it on in Settings, kept on this device only.
final askJournalEnabledProvider = NotifierProvider<AskJournalEnabled, bool>(
  AskJournalEnabled.new,
);

class AskJournalEnabled extends Notifier<bool> {
  static const String key = 'askJournal';

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
      reportError(e, stack, context: 'while reading the ask journal choice');
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
      reportError(e, stack, context: 'while saving the ask journal choice');
    }
  }
}

/// The Settings row for [askJournalEnabledProvider]. Turning it on first
/// says what is sent, habit names included, and asks again; turning it off
/// needs no asking.
class AskJournalSetting extends ConsumerWidget {
  const AskJournalSetting({super.key});

  static const String label = 'Ask your journal';
  static const String subtitle =
      'Type a question; this device counts the answer.';
  static const String disclosureTitle = 'Send questions to be read?';
  static const String disclosure =
      'When you ask a question, its text, today’s date and your habits’ names '
      'and units are sent to Penchant’s server and on to Anthropic’s Claude, '
      'which turns the question into a query. Habit names are encrypted '
      'everywhere else; this is the one place they leave this device. Your '
      'entries, amounts, times, tags and notes are never sent, and the '
      'answer is worked out on this device. Anthropic does not use it for '
      'training. Switch this off to stop sending questions.';
  static const String turnOn = 'Turn on';
  static const String notNow = 'Not now';

  Future<void> _set(BuildContext context, WidgetRef ref, bool on) async {
    final AskJournalEnabled notifier = ref.read(
      askJournalEnabledProvider.notifier,
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
    final bool on = ref.watch(askJournalEnabledProvider);
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
