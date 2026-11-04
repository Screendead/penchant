import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tracker/errors/report_error.dart';

const Duration writeTimeout = Duration(seconds: 10);

const String queuedMessage =
    'Saved on this device. It will sync when you are back online.';

const String queuedDeleteMessage =
    'Deleted on this device. It will sync when you are back online.';

/// Waits up to [writeTimeout] for the server to acknowledge [write]. Returns
/// true once it has, and false when it has not yet: the write stays queued in
/// the SDK and commits once the device reconnects, so a timeout is not a
/// failure. A [FirebaseException] before the timeout throws; one after it,
/// when the server refuses the queued write, is logged and goes to
/// [onRejectedLater].
Future<bool> settleWrite(
  Future<void> write, {
  required void Function(FirebaseException error) onRejectedLater,
}) async {
  bool timedOut = false;
  // A caller's Future<DocumentReference> typed as Future<void> keeps its
  // runtime type, and Future.timeout rejects an onTimeout that returns null
  // for it, so time out a true Future<void> instead.
  final Future<void> settled = write.then<void>((_) {});
  // Future.timeout discards an error that arrives after its timer fired, so
  // only a separate listener hears the server refuse it.
  unawaited(
    settled.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        if (timedOut && error is FirebaseException) {
          reportError(
            error,
            stack,
            context: 'when the server refused a write queued on this device',
          );
          onRejectedLater(error);
        }
      },
    ),
  );
  await settled.timeout(
    writeTimeout,
    onTimeout: () {
      timedOut = true;
    },
  );
  return !timedOut;
}
