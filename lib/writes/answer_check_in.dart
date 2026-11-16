import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/check_in.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/reminder/check_ins.dart';
import 'package:tracker/reminder/daily_nudge.dart';
import 'package:tracker/widgets/undo_bar.dart';
import 'package:tracker/writes/rejected_writes.dart';
import 'package:tracker/writes/settle_write.dart';
import 'package:tracker/writes/tracker_writes.dart';

const String checkInRemovedMessage = 'Check-in removed';

String checkInNotedMessage(int strength) =>
    'Check-in noted: ${checkInLabel(strength)}';

/// Records a random check-in's answer, with Undo, withdraws its notification
/// and keeps the next days of prompts waiting. Throws nothing; says how it
/// went in the bar.
Future<void> answerCheckIn(
  WidgetRef ref,
  ScaffoldMessengerState messenger, {
  required String checkInID,
  required DateTime promptedAt,
  required DateTime answeredAt,
  required int strength,
  required CheckInVia via,
}) async {
  final User? user = ref.read(userProvider).value;
  final TrackerWrites writes = ref.read(trackerWritesProvider);
  final NudgeScheduler scheduler = ref.read(nudgeSchedulerProvider);
  ref.read(pendingCheckInProvider.notifier).markAnswered(checkInID);
  unawaited(_withdraw(scheduler, checkInID));
  unawaited(ref.read(checkInsProvider.notifier).topUp());
  if (user == null) {
    showUndoBar(messenger, const TextSpan(text: 'You are signed out'));
    return;
  }
  if (!writes.canCreate) {
    showUndoBar(
      messenger,
      const TextSpan(text: 'Not saved. $noJournalKeyMessage'),
    );
    return;
  }
  final RejectedWrites rejected = ref.read(rejectedWritesProvider.notifier);
  final bool offline = ref.read(offlineProvider).value ?? false;
  const String what = 'check-in';
  bool undone = false;

  void undo() {
    undone = true;
    unawaited(_remove(messenger, writes, rejected, checkInID));
  }

  final SentWrite write = writes.recordCheckIn(
    checkInID,
    ownerID: user.uid,
    createdAt: answeredAt,
    strength: strength,
    promptedAt: promptedAt,
    via: via,
  );
  showUndoBar(
    messenger,
    TextSpan(text: offline ? queuedMessage : checkInNotedMessage(strength)),
    onUndo: undo,
  );
  try {
    final bool synced = await rejected.settle(write, 'Not saved: $what');
    if (!synced && !offline && !undone && messenger.mounted) {
      showUndoBar(messenger, const TextSpan(text: queuedMessage), onUndo: undo);
    }
  } on FirebaseException catch (e, stack) {
    reportError(e, stack, context: 'while saving a check-in');
    if (messenger.mounted) {
      showUndoBar(
        messenger,
        TextSpan(text: 'Not saved. ${firestoreErrorMessage(e)}'),
      );
    }
  }
}

Future<void> _withdraw(NudgeScheduler scheduler, String id) async {
  try {
    await scheduler.withdrawCheckIn(id);
  } catch (e, stack) {
    reportError(e, stack, context: 'while withdrawing a check-in');
  }
}

Future<void> _remove(
  ScaffoldMessengerState messenger,
  TrackerWrites writes,
  RejectedWrites rejected,
  String checkInID,
) async {
  String? message;
  try {
    message =
        await rejected.settle(
          writes.deleteCheckIn(checkInID),
          'Not deleted: check-in',
        )
        ? checkInRemovedMessage
        : queuedDeleteMessage;
  } on FirebaseException catch (e, stack) {
    reportError(e, stack, context: 'while removing a check-in');
    message = rejected.createRefused(checkInID)
        ? null
        : 'Could not remove. ${firestoreErrorMessage(e)}';
  }
  if (message != null && messenger.mounted) {
    showUndoBar(messenger, TextSpan(text: message));
  }
}
