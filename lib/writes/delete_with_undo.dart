import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/widgets/undo_bar.dart';
import 'package:tracker/writes/rejected_writes.dart';
import 'package:tracker/writes/settle_write.dart';
import 'package:tracker/writes/tracker_writes.dart';

const String restoredMessage = 'Entry restored';

InlineSpan deletedMessage(
  Vice vice,
  ViceActivity activity, {
  required bool alwaysUse24HourFormat,
}) => TextSpan(
  children: <InlineSpan>[
    const TextSpan(text: 'Deleted '),
    TextSpan(text: vice.unit.label(activity.quantity), style: undoBarBold),
    const TextSpan(text: ' at '),
    TextSpan(
      text: formatTime(
        activity.createdAt.toDate(),
        alwaysUse24HourFormat: alwaysUse24HourFormat,
      ),
      style: undoBarBold,
    ),
  ],
);

int _latestDelete = 0;

/// Deletes [activity] and shows the bar with Undo at once, as a log does:
/// the entry leaves the device's cache as soon as the write is made. Undo
/// writes the same document back under the same id. [onFailed] runs when the
/// delete is refused, so a row hidden early can come back.
Future<void> deleteWithUndo(
  WidgetRef ref,
  ScaffoldMessengerState messenger,
  Vice vice,
  ViceActivity activity, {
  required bool alwaysUse24HourFormat,
  VoidCallback? onRestored,
  VoidCallback? onFailed,
}) async {
  final User? user = ref.read(userProvider).value;
  final TrackerWrites writes = ref.read(trackerWritesProvider);
  final RejectedWrites rejected = ref.read(rejectedWritesProvider.notifier);
  final bool offline = ref.read(offlineProvider).value ?? false;
  final String entry = describeActivity(
    vice.name,
    vice.unit,
    activity.quantity,
    activity.createdAt.toDate(),
    alwaysUse24HourFormat: alwaysUse24HourFormat,
  );
  final int delete = ++_latestDelete;
  bool undone = false;

  void showBar(InlineSpan message) => showUndoBar(
    messenger,
    message,
    onUndo: user == null
        ? null
        : () {
            undone = true;
            onRestored?.call();
            _restore(messenger, writes, rejected, user.uid, activity, entry);
          },
  );

  final SentWrite write = writes.deleteActivity(activity.id);
  showBar(
    offline
        ? const TextSpan(text: queuedDeleteMessage)
        : deletedMessage(
            vice,
            activity,
            alwaysUse24HourFormat: alwaysUse24HourFormat,
          ),
  );

  try {
    final bool synced = await rejected.settle(write, 'Not deleted: $entry');
    if (!synced && !offline && !undone && delete == _latestDelete) {
      showBar(const TextSpan(text: queuedDeleteMessage));
    }
  } on FirebaseException catch (e, stack) {
    reportError(e, stack, context: 'while deleting an activity');
    onFailed?.call();
    // The banner already says the entry was not saved.
    if (!rejected.createRefused(activity.id) && messenger.mounted) {
      showUndoBar(
        messenger,
        TextSpan(
          text: 'Could not delete this activity. ${firestoreErrorMessage(e)}',
        ),
      );
    }
  }
}

Future<void> _restore(
  ScaffoldMessengerState messenger,
  TrackerWrites writes,
  RejectedWrites rejected,
  String ownerID,
  ViceActivity activity,
  String entry,
) async {
  String message;
  try {
    message =
        await rejected.settle(
          writes.recordActivity(
            activity.id,
            ownerID: ownerID,
            viceID: activity.viceID,
            quantity: activity.quantity,
            createdAt: activity.createdAt.toDate(),
            triggers: activity.triggers,
          ),
          'Not restored: $entry',
        )
        ? restoredMessage
        : queuedMessage;
  } on FirebaseException catch (e, stack) {
    reportError(e, stack, context: 'while restoring a deleted activity');
    message = 'Could not restore. ${firestoreErrorMessage(e)}';
  }
  if (messenger.mounted) {
    showUndoBar(messenger, TextSpan(text: message));
  }
}
