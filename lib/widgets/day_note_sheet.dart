import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/day_note_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/widgets/note_panels.dart';
import 'package:tracker/widgets/undo_bar.dart';
import 'package:tracker/widgets/urge_note_fields.dart';
import 'package:tracker/writes/rejected_writes.dart';
import 'package:tracker/writes/settle_write.dart';
import 'package:tracker/writes/tracker_writes.dart';

/// The note about one local day: its text, then the tags read from it.
class DayNoteSheet extends ConsumerStatefulWidget {
  const DayNoteSheet({super.key, required this.day});

  final DateTime day;

  static const int panels = 2;
  static const Key fieldKey = ValueKey<String>('day-note-text');
  static const Key deleteKey = ValueKey<String>('day-note-delete');
  static const Key confirmDeleteKey = ValueKey<String>('day-note-confirm');
  static const String fieldHint = 'What made the day different';
  static const String savedMessage = 'Day note saved';
  static const String deletedMessage = 'Day note deleted';
  static const String lockedMessage =
      'This note was sealed with another journal key, so it cannot be opened '
      'here. You can delete it.';
  static const String loadFailed = 'Could not load the note about this day.';
  static const String confirmDelete =
      'Delete this note? This cannot be undone.';

  static String title(DateTime day, DateTime today) =>
      'Anything different about ${switch (daysBetween(day, today)) {
        0 => 'today',
        1 => 'yesterday',
        _ => DateFormat.MMMEd(formatLocale).format(day),
      }}?';

  static String notSaved(DateTime day) =>
      'Day note not saved: ${formatDate(day)}';

  static String notDeleted(DateTime day) =>
      'Day note not deleted: ${formatDate(day)}';

  @override
  ConsumerState<DayNoteSheet> createState() => _DayNoteSheetState();
}

class _DayNoteSheetState extends NotePanelsState<DayNoteSheet> {
  bool prefilled = false;
  List<String> stored = const <String>[];
  bool busy = false;
  bool confirming = false;

  @override
  String get title => DayNoteSheet.title(widget.day, ref.watch(todayProvider));

  @override
  int get panelCount => DayNoteSheet.panels;

  @override
  List<String> get initial => stored;

  DayNote? get current => ref.read(dayNoteProvider(widget.day)).value;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<DayNote?> value = ref.watch(dayNoteProvider(widget.day));
    if (!value.hasValue) {
      return sheetShell(
        context,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            header(context, steps: false),
            Expanded(
              child: Center(
                child: value.hasError
                    ? Text(DayNoteSheet.loadFailed)
                    : const CircularProgressIndicator(),
              ),
            ),
          ],
        ),
      );
    }
    final DayNote? existing = value.value;
    if (existing != null && existing.locked) {
      return sheetShell(
        context,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            header(context, steps: false),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(DialSpace.m),
                children: <Widget>[
                  Text(
                    DayNoteSheet.lockedMessage,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: DialColors.of(context).muted,
                    ),
                  ),
                ],
              ),
            ),
            confirming
                ? _confirmFooter(context)
                : footerFrame(context, <Widget>[
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: _deleteButton(context),
                    ),
                  ]),
          ],
        ),
      );
    }
    if (!prefilled) {
      prefilled = true;
      if (existing != null) {
        stored = existing.triggers;
        selected = <String>[...existing.triggers];
        note.text = existing.text;
      }
    }
    return buildPanels(context);
  }

  @override
  Widget panel(BuildContext context, int index) => switch (index) {
    0 => notePanel(
      context,
      NoteField(
        controller: note,
        label: NotePanels.noteTitle,
        hint: DayNoteSheet.fieldHint,
        inputKey: DayNoteSheet.fieldKey,
        multiline: true,
        validator: (String? text) => dayNoteError(text ?? '', const <String>[]),
      ),
    ),
    _ => tagsPanel(context),
  };

  @override
  Widget? footerLeading(BuildContext context) =>
      current == null ? null : _deleteButton(context);

  @override
  Widget footer(BuildContext context, bool cramped) =>
      confirming ? _confirmFooter(context) : super.footer(context, cramped);

  Widget _deleteButton(BuildContext context) => TextButton(
    key: DayNoteSheet.deleteKey,
    style: TextButton.styleFrom(
      minimumSize: const Size(44, 44),
      foregroundColor: Theme.of(context).colorScheme.error,
    ),
    onPressed: busy ? null : () => setState(() => confirming = true),
    child: const Text('Delete'),
  );

  Widget _confirmFooter(BuildContext context) {
    const Size target = Size(44, 44);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return footerFrame(context, <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: DialSpace.xs),
        child: Text(
          DayNoteSheet.confirmDelete,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
      Row(
        children: <Widget>[
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: target),
              onPressed: busy ? null : () => setState(() => confirming = false),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: DialSpace.xs),
          Expanded(
            flex: 2,
            child: FilledButton(
              key: DayNoteSheet.confirmDeleteKey,
              style: FilledButton.styleFrom(
                minimumSize: target,
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: busy ? null : _delete,
              child: const Text('Delete'),
            ),
          ),
        ],
      ),
    ]);
  }

  @override
  void done() {
    if (!busy) _save();
  }

  Future<void> _save() async {
    final String text = note.text.trim();
    if (dayNoteError(text, selected) case final String invalid) {
      setState(() => error = invalid);
      return;
    }
    final User? user = ref.read(userProvider).value;
    if (user == null) return;
    final TrackerWrites writes = ref.read(trackerWritesProvider);
    // The sheet stays open with what was typed, to save once the key loads.
    if (!writes.canCreate) {
      setState(() => error = 'Not saved. $noJournalKeyMessage');
      return;
    }
    final DayNote? replacing = current;
    if (replacing != null && replacing.locked) return;
    stopReading();
    final List<String> triggers = List<String>.of(selected);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final RejectedWrites rejected = ref.read(rejectedWritesProvider.notifier);
    setState(() {
      busy = true;
      error = null;
    });
    final bool synced;
    try {
      synced = await rejected.settle(
        writes.setDayNote(
          ownerID: user.uid,
          day: dayKey(widget.day),
          text: text,
          triggers: triggers,
          replacing: replacing,
        ),
        DayNoteSheet.notSaved(widget.day),
      );
    } on FirebaseException catch (e, stack) {
      reportError(e, stack, context: 'while saving a day note');
      if (mounted) {
        setState(() => error = 'Not saved. ${firestoreErrorMessage(e)}');
      }
      return;
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (!mounted) return;
    navigator.pop();
    showUndoBar(
      messenger,
      TextSpan(text: synced ? DayNoteSheet.savedMessage : queuedMessage),
    );
  }

  Future<void> _delete() async {
    final User? user = ref.read(userProvider).value;
    if (user == null) return;
    final TrackerWrites writes = ref.read(trackerWritesProvider);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final RejectedWrites rejected = ref.read(rejectedWritesProvider.notifier);
    stopReading();
    setState(() {
      busy = true;
      error = null;
    });
    final bool synced;
    try {
      synced = await rejected.settle(
        writes.deleteDayNote(ownerID: user.uid, day: dayKey(widget.day)),
        DayNoteSheet.notDeleted(widget.day),
      );
    } on FirebaseException catch (e, stack) {
      reportError(e, stack, context: 'while deleting a day note');
      if (mounted) {
        setState(() => error = 'Not deleted. ${firestoreErrorMessage(e)}');
      }
      return;
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (!mounted) return;
    navigator.pop();
    showUndoBar(
      messenger,
      TextSpan(
        text: synced ? DayNoteSheet.deletedMessage : queuedDeleteMessage,
      ),
    );
  }
}
