import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final userProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

// A User is a snapshot: profile updates and reload() reach only this stream.
// It also fires on every token refresh, so the provider chain stays on
// userProvider and only screens that show the profile watch this one.
final userProfileProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.userChanges();
});
