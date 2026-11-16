import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/account/claude_access.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/say_it/entry_reader.dart';
import 'package:tracker/widgets/settings_card.dart';

/// Whether this device sends words to be read into entries, per feature: off
/// until turned on in Settings, kept on this device only.
final entryReadingEnabledProvider =
    NotifierProvider.family<EntryReadingEnabled, bool, EntryMode>(
      EntryReadingEnabled.new,
    );

class EntryReadingEnabled extends Notifier<bool> {
  EntryReadingEnabled(this.mode);

  final EntryMode mode;

  static String keyFor(EntryMode mode) =>
      mode == EntryMode.now ? 'sayItToLog' : 'catchUpInWords';

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
      saved = prefs.getBool(keyFor(mode));
    } catch (e, stack) {
      reportError(e, stack, context: 'while reading an entry-reading choice');
      return;
    }
    // A choice made while the read was in flight is newer than what it read.
    if (saved != null && !_chosen) state = saved;
  }

  Future<void> choose(bool on) async {
    _chosen = true;
    state = on;
    // A failed save still applies the choice until the app closes.
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyFor(mode), on);
    } catch (e, stack) {
      reportError(e, stack, context: 'while saving an entry-reading choice');
    }
  }
}

/// The Settings row for one of [entryReadingEnabledProvider]'s switches.
/// Turning it on first says what is sent and asks again; turning it off
/// needs no asking.
class EntryReadingSetting extends ConsumerWidget {
  const EntryReadingSetting(this.mode, {super.key});

  final EntryMode mode;

  static const String sayLabel = 'Say it to log';
  static const String saySubtitle =
      'Say or type what you had; check the entries, then save.';
  static const String sayTitle = 'Send what you say to be read?';
  static const String sayDisclosure =
      'When you tap Read it, the words in the box, the time now, and your '
      'unarchived habits’ names and units are sent to Penchant’s server and '
      'on to Anthropic’s Claude, which suggests entries. Habit names are '
      'encrypted everywhere else; here they leave this device. Speech is '
      'turned into words on this device: the recording never leaves it, and '
      'you see the words before anything is sent. Your entries, notes, '
      'Health, places and calendar stay here, and nothing is saved until you '
      'check the entries and tap Save. Anthropic does not use it for '
      'training and deletes it within 30 days. Switch this off to stop '
      'sending.';

  static const String catchUpLabel = 'Catch up in words';
  static const String catchUpSubtitle =
      'Describe missed days; check the entries, then save.';
  static const String catchUpTitle = 'Send your account of missed days?';
  static const String catchUpDisclosure =
      'When you tap Read it, what you typed, the days you picked, the time '
      'now, and your unarchived habits’ names and units are sent to '
      'Penchant’s server and on to Anthropic’s Claude, which suggests '
      'entries. Habit names are encrypted everywhere else; here they leave '
      'this device. Your existing entries and notes stay here, and nothing '
      'is saved until you check the entries and tap Save all. Anthropic does '
      'not use it for training and deletes it within 30 days. Switch this '
      'off to stop sending.';

  static const String turnOn = 'Turn on';
  static const String notNow = 'Not now';

  String get label => mode == EntryMode.now ? sayLabel : catchUpLabel;

  Future<void> _set(BuildContext context, WidgetRef ref, bool on) async {
    final EntryReadingEnabled notifier = ref.read(
      entryReadingEnabledProvider(mode).notifier,
    );
    if (!on) {
      await notifier.choose(false);
      return;
    }
    final bool? agreed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(mode == EntryMode.now ? sayTitle : catchUpTitle),
        content: Text(
          mode == EntryMode.now ? sayDisclosure : catchUpDisclosure,
        ),
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
      return ClaudeNeedsEmailRow(label: label);
    }
    final bool on = ref.watch(entryReadingEnabledProvider(mode));
    return MergeSemantics(
      child: CardRow(
        label: label,
        subtitle: mode == EntryMode.now ? saySubtitle : catchUpSubtitle,
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
