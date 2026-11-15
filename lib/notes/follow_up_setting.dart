import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/notes/note_reader_setting.dart';
import 'package:tracker/widgets/settings_card.dart';

/// Whether this device asks for a follow-up question when a note is read:
/// off until the person turns it on, kept on this device only, and of no
/// effect while [noteReaderEnabledProvider] is off.
final followUpEnabledProvider = NotifierProvider<FollowUpEnabled, bool>(
  FollowUpEnabled.new,
);

class FollowUpEnabled extends Notifier<bool> {
  static const String key = 'noteFollowUp';

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
      reportError(e, stack, context: 'while reading the follow-up choice');
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
      reportError(e, stack, context: 'while saving the follow-up choice');
    }
  }
}

/// The Settings row for [followUpEnabledProvider], shown under
/// [NoteReaderSetting] and disabled while that is off. Turning it on first
/// says what the question is and where the note goes, and asks again.
class FollowUpSetting extends ConsumerWidget {
  const FollowUpSetting({super.key});

  static const String label = 'Ask one question about a note';
  static const String subtitle =
      'After a note, one optional question about something you wrote.';
  static const String needsReader =
      'Turn on Suggest tags from notes to use this.';
  static const String disclosureTitle = 'Ask a question about your notes?';
  static const String disclosure =
      'When tags are read from a note, Claude may also write one question '
      'about something in it, such as who was there or what happened just '
      'before. Nothing more is sent: only the note’s text, as for tags. The '
      'question is written by a model, so now and then it may read oddly; '
      'skip any you don’t want to answer. Your answer is never sent to '
      'Claude; it is saved encrypted with the note.';
  static const String turnOn = 'Turn on';
  static const String notNow = 'Not now';

  Future<void> _set(BuildContext context, WidgetRef ref, bool on) async {
    final FollowUpEnabled notifier = ref.read(followUpEnabledProvider.notifier);
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
    final bool reader = ref.watch(noteReaderEnabledProvider);
    final bool on = reader && ref.watch(followUpEnabledProvider);
    return MergeSemantics(
      child: CardRow(
        label: label,
        subtitle: reader ? subtitle : needsReader,
        enabled: reader,
        onTap: reader ? () => _set(context, ref, !on) : null,
        trailing: Switch.adaptive(
          value: on,
          activeTrackColor: Theme.of(context).colorScheme.primary,
          onChanged: reader ? (bool value) => _set(context, ref, value) : null,
        ),
      ),
    );
  }
}
