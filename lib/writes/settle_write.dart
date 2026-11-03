import 'dart:async';

const Duration writeTimeout = Duration(seconds: 10);

const String queuedMessage =
    'Saved on this device. It will sync when you are back online.';

const String queuedDeleteMessage =
    'Deleted on this device. It will sync when you are back online.';

/// Waits up to [writeTimeout] for the server to acknowledge [write]. Returns
/// true once it has, and false when it has not yet: the write stays queued in
/// the SDK and commits once the device reconnects, so a timeout is not a
/// failure. A [FirebaseException] still throws.
Future<bool> settleWrite(Future<void> write) async {
  try {
    await write.timeout(writeTimeout);
    return true;
  } on TimeoutException {
    return false;
  }
}
