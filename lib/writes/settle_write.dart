import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

const Duration writeTimeout = Duration(seconds: 10);

const String queuedMessage =
    'Saved on this device. It will sync when you are back online.';

const String queuedDeleteMessage =
    'Deleted on this device. It will sync when you are back online.';

/// Waits up to [writeTimeout] for the server to acknowledge [write]. Returns
/// true once it has, and false when it has not yet: the write stays queued in
/// the SDK and commits once the device reconnects, so a timeout is not a
/// failure. A [FirebaseException] before the timeout throws; one after it,
/// when the server refuses the queued write, goes to [onRejectedLater].
Future<bool> settleWrite(
  Future<void> write, {
  required void Function(FirebaseException error) onRejectedLater,
}) async {
  bool timedOut = false;
  // Future.timeout discards an error that arrives after its timer fired, so
  // only a listener on [write] itself hears the server refuse it.
  unawaited(
    write.then<void>(
      (_) {},
      onError: (Object error) {
        if (timedOut && error is FirebaseException) {
          onRejectedLater(error);
        }
      },
    ),
  );
  await write.timeout(
    writeTimeout,
    onTimeout: () {
      timedOut = true;
    },
  );
  return !timedOut;
}
