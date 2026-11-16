import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/account/claude_access.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/widgets/settings_card.dart';

/// Whether this device may send a period of the journal to be written up as
/// a letter, each time only when asked: off until the person turns it on in
/// Settings, kept on this device only.
final letterEnabledProvider = NotifierProvider<LetterEnabled, bool>(
  LetterEnabled.new,
);

class LetterEnabled extends Notifier<bool> {
  static const String key = 'letter';

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
      reportError(e, stack, context: 'while reading the letter choice');
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
      reportError(e, stack, context: 'while saving the letter choice');
    }
  }
}

/// The Settings row for [letterEnabledProvider]. Turning it on first says
/// what a letter sends and asks again; turning it off needs no asking.
class LetterSetting extends ConsumerWidget {
  const LetterSetting({super.key});

  static const String label = 'Letter';
  static const String subtitle =
      'On request, Claude writes a review of a period you choose.';
  static const String disclosureTitle = 'Send your journal for a letter?';
  static const String disclosure =
      'Each time you ask for a letter, and only then, the period you choose is '
      'sent to Penchant’s server and on to Anthropic’s Claude Opus, which '
      'writes it: every note, day note and answer to a follow-up question in '
      'full, and each entry’s date, time, amount, habit name and tags, with '
      'totals worked out on this device. You see all of it before it goes. '
      'Health, places and calendar data are never sent. Anthropic does not '
      'use it for training and deletes it within 30 days. The letter is '
      'kept encrypted on this device only.';
  static const String turnOn = 'Turn on';
  static const String notNow = 'Not now';

  Future<void> _set(BuildContext context, WidgetRef ref, bool on) async {
    final LetterEnabled notifier = ref.read(
      letterEnabledProvider.notifier,
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
    if (!ref.watch(claudeAllowedProvider)) {
      return const ClaudeNeedsEmailRow(label: label);
    }
    final bool on = ref.watch(letterEnabledProvider);
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
