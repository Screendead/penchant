import 'package:cloud_firestore/cloud_firestore.dart';

// Firestore's own messages name queries and documents, so only these reach
// the screen. Anything else, a parser's TypeError included, reads as the last.
String firestoreErrorMessage(Object error) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'unavailable':
      case 'deadline-exceeded':
        return 'No connection. Check your internet and try again.';
      case 'permission-denied':
        return 'This account is not allowed to do that. Sign out and in '
            'again, then retry.';
      case 'unauthenticated':
        return 'You are signed out. Sign in again, then retry.';
      case 'failed-precondition':
        return 'The server is not ready for this yet. Try again later.';
      case 'resource-exhausted':
        return 'Too many requests. Wait a minute and try again.';
      case 'not-found':
        return 'That entry no longer exists.';
    }
  }
  return 'Something went wrong. Try again.';
}

String loadErrorMessage(String what, Object error) =>
    'Could not load $what. ${firestoreErrorMessage(error)}';
