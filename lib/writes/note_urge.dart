import 'dart:async';

import 'package:clock/clock.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/urge.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/reminder/daily_nudge.dart';
import 'package:tracker/reminder/urge_check_in.dart';
import 'package:tracker/widgets/undo_bar.dart';
import 'package:tracker/writes/rejected_writes.dart';
import 'package:tracker/writes/settle_write.dart';
import 'package:tracker/writes/tracker_writes.dart';

// Measurement, not resistance: every message says what was recorded and
// nothing about how well it went.

const String urgeRemovedMessage = 'Urge removed';

String describeUrge(
  String viceName,
  DateTime at, {
  required bool alwaysUse24HourFormat,
}) =>
    'urge for $viceName, '
    '${formatDayAndTime(at, alwaysUse24HourFormat: alwaysUse24HourFormat)}';

InlineSpan urgeNotedMessage(
  Vice vice,
  DateTime at, {
  required bool alwaysUse24HourFormat,
}) => TextSpan(
  children: <InlineSpan>[
    const TextSpan(text: 'Urge noted for '),
    TextSpan(text: vice.name, style: undoBarBold),
    const TextSpan(text: ' at '),
    TextSpan(
      text: formatTime(at, alwaysUse24HourFormat: alwaysUse24HourFormat),
      style: undoBarBold,
    ),
  ],
);

// Bumped by each note, so one that settles late does not replace the bar of
// one made after it.
int _latestNote = 0;

/// Notes an urge of [strength] for [vice] now, with Undo, and schedules its
/// check-in when the person has turned check-ins on.
Future<void> noteUrge(
  WidgetRef ref,
  ScaffoldMessengerState messenger,
  Vice vice,
  int strength, {
  required bool alwaysUse24HourFormat,
}) async {
  final User? user = ref.read(userProvider).value;
  if (user == null) {
    showUndoBar(messenger, const TextSpan(text: 'You are signed out'));
    return;
  }
  final TrackerWrites writes = ref.read(trackerWritesProvider);
  if (!writes.canCreate) {
    showUndoBar(
      messenger,
      const TextSpan(text: 'Not noted. $noJournalKeyMessage'),
    );
    return;
  }
  final RejectedWrites rejected = ref.read(rejectedWritesProvider.notifier);
  final NudgeScheduler scheduler = ref.read(nudgeSchedulerProvider);
  final bool checkIn = ref.read(urgeCheckInProvider);
  final bool offline = ref.read(offlineProvider).value ?? false;
  final String urgeID = writes.newUrgeID();
  final DateTime at = clock.now();
  final String what = describeUrge(
    vice.name,
    at,
    alwaysUse24HourFormat: alwaysUse24HourFormat,
  );
  final int note = ++_latestNote;
  bool undone = false;

  void undo() {
    undone = true;
    unawaited(_cancelCheck(scheduler, urgeID));
    unawaited(removeUrge(messenger, writes, rejected, urgeID, what));
  }

  final SentWrite write = writes.recordUrge(
    urgeID,
    ownerID: user.uid,
    viceID: vice.id,
    createdAt: at,
    strength: strength,
  );
  showUndoBar(
    messenger,
    offline
        ? const TextSpan(text: queuedMessage)
        : urgeNotedMessage(
            vice,
            at,
            alwaysUse24HourFormat: alwaysUse24HourFormat,
          ),
    onUndo: undo,
  );
  if (checkIn) {
    try {
      await scheduler.scheduleUrgeCheck(urgeID, at.add(urgeCheckDelay));
    } catch (e, stack) {
      reportError(e, stack, context: 'while scheduling an urge check-in');
    }
  }

  try {
    final bool synced = await rejected.settle(write, 'Not saved: $what');
    if (!synced && !offline && !undone && note == _latestNote) {
      showUndoBar(messenger, const TextSpan(text: queuedMessage), onUndo: undo);
    }
  } on FirebaseException catch (e, stack) {
    reportError(e, stack, context: 'while noting an urge');
    unawaited(_cancelCheck(scheduler, urgeID));
    if (note == _latestNote && messenger.mounted) {
      showUndoBar(
        messenger,
        TextSpan(
          text: e.code == 'permission-denied'
              ? 'That habit no longer exists'
              : 'Not noted. ${firestoreErrorMessage(e)}',
        ),
      );
    }
  }
}

Future<void> _cancelCheck(NudgeScheduler scheduler, String urgeID) async {
  try {
    await scheduler.cancelUrgeCheck(urgeID);
  } catch (e, stack) {
    reportError(e, stack, context: 'while cancelling an urge check-in');
  }
}

/// Records what happened to [urge] at the time of answering, and withdraws
/// its check-in. Throws nothing; says how it went in the bar.
Future<void> answerUrge(
  WidgetRef ref,
  ScaffoldMessengerState messenger,
  Urge urge,
  UrgeOutcome outcome, {
  required String viceName,
  required bool alwaysUse24HourFormat,
}) async {
  final TrackerWrites writes = ref.read(trackerWritesProvider);
  final RejectedWrites rejected = ref.read(rejectedWritesProvider.notifier);
  unawaited(_cancelCheck(ref.read(nudgeSchedulerProvider), urge.id));
  if (urge.locked || !writes.canCreate) {
    showUndoBar(
      messenger,
      const TextSpan(text: 'Not saved. $noJournalKeyMessage'),
    );
    return;
  }
  final String what = describeUrge(
    viceName,
    urge.at,
    alwaysUse24HourFormat: alwaysUse24HourFormat,
  );
  try {
    final bool synced = await rejected.settle(
      writes.updateUrge(urge.id, urge.content.answered(outcome, clock.now())),
      'Not saved: $what',
    );
    if (messenger.mounted) {
      showUndoBar(
        messenger,
        TextSpan(
          text: synced ? 'Noted: ${outcomeWords(outcome)}' : queuedMessage,
        ),
      );
    }
  } on FirebaseException catch (e, stack) {
    reportError(e, stack, context: 'while answering an urge');
    if (messenger.mounted) {
      showUndoBar(
        messenger,
        TextSpan(text: 'Not saved. ${firestoreErrorMessage(e)}'),
      );
    }
  }
}

/// Deletes an urge and says how that went.
Future<void> removeUrge(
  ScaffoldMessengerState messenger,
  TrackerWrites writes,
  RejectedWrites rejected,
  String urgeID,
  String what,
) async {
  String? message;
  try {
    message =
        await rejected.settle(writes.deleteUrge(urgeID), 'Not deleted: $what')
        ? urgeRemovedMessage
        : queuedDeleteMessage;
  } on FirebaseException catch (e, stack) {
    reportError(e, stack, context: 'while removing an urge');
    message = rejected.createRefused(urgeID)
        ? null
        : 'Could not remove. ${firestoreErrorMessage(e)}';
  }
  if (message != null && messenger.mounted) {
    showUndoBar(messenger, TextSpan(text: message));
  }
}
