import 'package:firebase_auth/firebase_auth.dart';

// Firebase's own messages can say whether an address has an account, so none
// reaches the screen; a wrong address and a wrong password read the same.
String authErrorMessage(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'invalid-credential':
      case 'invalid-login-credentials':
      case 'wrong-password':
      case 'user-not-found':
        return 'That email and password do not match an account.';
      case 'invalid-email':
        return 'That email address is not valid.';
      case 'email-already-in-use':
        return 'That email already has an account. Sign in, or reset its '
            'password.';
      case 'weak-password':
        return 'Choose a longer password.';
      case 'user-disabled':
        return 'This account is disabled.';
      case 'requires-recent-login':
        return 'Sign in again, then retry.';
      case 'too-many-requests':
        return 'Too many attempts. Wait a few minutes and try again.';
      case 'network-request-failed':
        return 'No connection. Check your internet and try again.';
    }
  }
  if (error is FirebaseException && error.code == 'unavailable') {
    return 'No connection. Check your internet and try again.';
  }
  return 'Something went wrong. Try again.';
}
