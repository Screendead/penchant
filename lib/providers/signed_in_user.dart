import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:tracker/providers/user_provider.dart';

// Riverpod carries a provider's last value into the loading state of a rebuild,
// so a query provider that rebuilt when the user changed would go on returning
// the previous user's data until the next user's first snapshot. Keyed on the
// uid, each user's query is a separate provider that starts with no value.
AsyncValue<T> watchForSignedInUser<T>(
  Ref ref,
  ProviderListenable<AsyncValue<T>> Function(String uid) forUser,
) {
  final String? uid = ref.watch(
    userProvider.select((AsyncValue<User?> user) => user.value?.uid),
  );

  if (uid == null) {
    return AsyncLoading<T>();
  }

  return ref.watch(forUser(uid));
}
