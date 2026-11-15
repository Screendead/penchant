import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/widgets/settings_card.dart';

/// Whether this device sends notes to be read into tags: off until the
/// person turns it on in Settings, kept on this device only.
final noteReaderEnabledProvider = NotifierProvider<NoteReaderEnabled, bool>(
  NoteReaderEnabled.new,
);

class NoteReaderEnabled extends Notifier<bool> {
  static const String key = 'noteReader';

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
      reportError(e, stack, context: 'while reading the note reader choice');
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
      reportError(e, stack, context: 'while saving the note reader choice');
    }
  }
}

/// The Settings row for [noteReaderEnabledProvider]. Turning it on first
/// says where a note goes and asks again; turning it off needs no asking.
class NoteReaderSetting extends ConsumerWidget {
  const NoteReaderSetting({super.key});

  static const String label = 'Suggest tags from notes';
  static const String subtitle =
      'Reads what you wrote into tags for you to confirm.';
  static const String disclosureTitle = 'Send notes to suggest tags?';
  static const String disclosure =
      'When you write a note, its text is sent to Penchant’s server and on to '
      'Anthropic’s Claude, which suggests tags for you to confirm. Anthropic '
      'does not use it for training. The note you save stays encrypted. '
      'Switch this off to stop sending notes.';
  static const String turnOn = 'Turn on';
  static const String notNow = 'Not now';

  Future<void> _set(BuildContext context, WidgetRef ref, bool on) async {
    final NoteReaderEnabled notifier = ref.read(
      noteReaderEnabledProvider.notifier,
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
    final bool on = ref.watch(noteReaderEnabledProvider);
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
