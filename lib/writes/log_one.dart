import 'package:clock/clock.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/widgets/bead_arrivals.dart';
import 'package:tracker/widgets/undo_bar.dart';
import 'package:tracker/writes/rejected_writes.dart';
import 'package:tracker/writes/settle_write.dart';
import 'package:tracker/writes/tracker_writes.dart';

// What a tally's + and a tap on a Log-fan wedge record.
const int defaultQuantity = 1;

const String removedMessage = 'Activity removed';

String logOneLabel(Vice vice) =>
    'Log ${vice.unit.label(defaultQuantity)} of ${vice.name}';

InlineSpan loggedMessage(
  Vice vice,
  int quantity,
  DateTime at, {
  required bool alwaysUse24HourFormat,
}) => TextSpan(
  children: <InlineSpan>[
    const TextSpan(text: 'Logged '),
    TextSpan(text: vice.unit.label(quantity), style: undoBarBold),
    TextSpan(text: ' of ${vice.name} at '),
    TextSpan(
      text: formatTime(at, alwaysUse24HourFormat: alwaysUse24HourFormat),
      style: undoBarBold,
    ),
  ],
);

// Bumped by each log, so a log that settles late does not replace the bar of
// one made after it.
int _latestLog = 0;

/// Logs [defaultQuantity] of [vice] now. The bar says so at once, since the
/// entry is on the device as soon as it is written, and says it is queued if
/// the server has not answered by [writeTimeout]. Each call takes its own id,
/// so two taps are two entries. [from], in global coordinates, is where the
/// dial's bead flies in from. Given [offerUndo], the caller shows the Undo
/// where the log was made, and the bar carries notices only.
Future<void> logOne(
  WidgetRef ref,
  ScaffoldMessengerState messenger,
  Vice vice, {
  Offset? from,
  required bool alwaysUse24HourFormat,
  void Function(VoidCallback undo)? offerUndo,
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
      const TextSpan(text: 'Not logged. $noJournalKeyMessage'),
    );
    return;
  }
  final RejectedWrites rejected = ref.read(rejectedWritesProvider.notifier);
  final bool offline = ref.read(offlineProvider).value ?? false;
  final String activityID = writes.newActivityID();
  final DateTime at = clock.now();
  final String entry = describeActivity(
    vice.name,
    vice.unit,
    defaultQuantity,
    at,
    alwaysUse24HourFormat: alwaysUse24HourFormat,
  );
  final int log = ++_latestLog;
  bool undone = false;

  void undo() {
    undone = true;
    undoLog(messenger, writes, rejected, activityID, entry);
  }

  void showBar(InlineSpan message) =>
      showUndoBar(messenger, message, onUndo: offerUndo == null ? undo : null);

  if (from != null) {
    ref.read(beadArrivalsProvider).launch(activityID, from);
  }
  final SentWrite write = writes.recordActivity(
    activityID,
    ownerID: user.uid,
    viceID: vice.id,
    quantity: defaultQuantity,
    createdAt: at,
  );
  if (offerUndo == null) {
    showBar(
      offline
          ? const TextSpan(text: queuedMessage)
          : loggedMessage(
              vice,
              defaultQuantity,
              at,
              alwaysUse24HourFormat: alwaysUse24HourFormat,
            ),
    );
  } else {
    offerUndo(undo);
    if (offline) {
      showBar(const TextSpan(text: queuedMessage));
    }
  }

  try {
    final bool synced = await rejected.settle(write, 'Not saved: $entry');
    if (!synced && !offline && !undone && log == _latestLog) {
      showBar(const TextSpan(text: queuedMessage));
    }
  } on FirebaseException catch (e, stack) {
    reportError(e, stack, context: 'while logging one');
    if (log == _latestLog && messenger.mounted) {
      // The rules deny a habit that was deleted after this list loaded.
      showUndoBar(
        messenger,
        TextSpan(
          text: e.code == 'permission-denied'
              ? 'That habit no longer exists'
              : 'Not logged. ${firestoreErrorMessage(e)}',
        ),
      );
    }
  }
}

/// Deletes the entry a log just wrote, and says how that went.
Future<void> undoLog(
  ScaffoldMessengerState messenger,
  TrackerWrites writes,
  RejectedWrites rejected,
  String activityID,
  String entry, {
  void Function(VoidCallback undo)? offerUndo,
}) async {
  String? message;

  try {
    message =
        await rejected.settle(
          writes.deleteActivity(activityID),
          'Not deleted: $entry',
        )
        ? removedMessage
        : queuedDeleteMessage;
  } on FirebaseException catch (e, stack) {
    reportError(e, stack, context: 'while undoing a recorded activity');
    // The banner already says the entry was not saved.
    message = rejected.createRefused(activityID)
        ? null
        : 'Could not undo. ${firestoreErrorMessage(e)}';
  }

  if (message != null && messenger.mounted) {
    showUndoBar(messenger, TextSpan(text: message));
  }
}
