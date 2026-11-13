import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/activity_content.dart';
import 'package:tracker/data/free_text_triggers.dart';
import 'package:tracker/data/trigger_usage.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/widgets/trigger_picker.dart';
import 'package:tracker/widgets/undo_bar.dart';
import 'package:tracker/writes/rejected_writes.dart';
import 'package:tracker/writes/log_one.dart';
import 'package:tracker/writes/settle_write.dart';
import 'package:tracker/writes/tracker_writes.dart';

const String whatWasGoingOnLabel = 'What was going on?';

/// Opens the trigger picker, with the urge and note, for the saved entry
/// [activityID] of [vice] and writes what is picked to it; dismissing the
/// picker writes nothing. The rest of the entry's sealed content (its zone,
/// write time and source) is read from the device and sealed again with the
/// answers; if the entry is not on the device, the answers are written alone.
/// [cancelled], asked once the picker closes, stops the write (an entry undone
/// meanwhile). [entry] names the entry if the server refuses the change. The
/// picker's Undo log deletes the entry through [undoLog], then calls
/// [onUndone]. [at], the entry's time, lets the calendar suggest a trigger.
Future<void> askWhatWasGoingOn(
  BuildContext context,
  WidgetRef ref, {
  required String activityID,
  required Vice vice,
  List<String> initial = const <String>[],
  DateTime? at,
  bool Function()? cancelled,
  String? entry,
  VoidCallback? onUndone,
}) async {
  final String? uid = ref.read(userProvider).value?.uid;
  if (uid == null) {
    return;
  }
  // Read before the picker opens: the caller may be gone when it closes.
  final TrackerWrites writes = ref.read(trackerWritesProvider);
  final RejectedWrites rejected = ref.read(rejectedWritesProvider.notifier);
  final FreeTextTriggers freeText = ref.read(freeTextTriggersProvider);
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);

  final TriggerPick? picked = await showTriggerPicker(
    context,
    viceID: vice.id,
    viceName: vice.name,
    initial: initial,
    answers: (urge: null, note: null),
    at: at,
    onUndoLog: messenger == null
        ? null
        : () {
            onUndone?.call();
            undoLog(
              messenger,
              writes,
              rejected,
              activityID,
              entry ?? vice.name,
            );
          },
  );
  final ActivityContent asked = ActivityContent(triggers: initial);
  final ActivityContent answered = asked.withAnswers(
    triggers: picked?.triggers ?? initial,
    urge: picked?.answers?.urge,
    note: picked?.answers?.note,
  );
  if (picked == null ||
      !answered.answersDiffer(asked) ||
      (cancelled?.call() ?? false) ||
      // The banner already says the entry was not saved.
      rejected.createRefused(activityID)) {
    return;
  }
  final ActivityContent content =
      (await writes.cachedContent(activityID))?.withAnswers(
        triggers: answered.triggers,
        urge: answered.urge,
        note: answered.note,
      ) ??
      answered;

  try {
    final bool synced = await rejected.settle(
      writes.updateActivity(activityID, content: content),
      'Change not saved: ${entry ?? vice.name}',
    );
    countFreeTextUses(freeText, uid, content.triggers, already: initial);
    if (!synced && messenger != null && messenger.mounted) {
      showUndoBar(messenger, const TextSpan(text: queuedMessage));
    }
  } on FirebaseException catch (e, stack) {
    reportError(e, stack, context: 'while saving what was going on');
    if (rejected.createRefused(activityID) ||
        messenger == null ||
        !messenger.mounted) {
      return;
    }
    showUndoBar(
      messenger,
      TextSpan(text: 'Not saved. ${firestoreErrorMessage(e)}'),
    );
  }
}

/// Counts one use of each free-text trigger in [saved] not in [already],
/// toward the picker offering it. Takes no ref, as it runs after a save.
void countFreeTextUses(
  FreeTextTriggers store,
  String uid,
  List<String> saved, {
  List<String> already = const <String>[],
}) {
  store
      .recordUses(
        uid,
        saved.where((String t) => isFreeTextTrigger(t) && !already.contains(t)),
      )
      .catchError((Object e, StackTrace stack) {
        reportError(e, stack, context: 'while counting free-text triggers');
      });
}
