import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// A Firestore listener hears nothing more after an error, so each retry opens
// a new one: a billed read, and for a denied query a denied read. These codes
// do not clear by waiting; the screen's Retry asks again instead.
const Set<String> _finalCodes = <String>{
  'permission-denied',
  'unauthenticated',
  'failed-precondition',
  'invalid-argument',
};

Duration? firestoreRetry(int retryCount, Object error) {
  if (error is FirebaseException && _finalCodes.contains(error.code)) {
    return null;
  }
  return ProviderContainer.defaultRetry(retryCount, error);
}
