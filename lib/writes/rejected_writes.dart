import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/providers/user_provider.dart';

final DateFormat _activityTime = DateFormat('EEE d MMM, HH:mm');

String describeActivity(
  String viceName,
  Unit unit,
  int quantity,
  DateTime at,
) => '$viceName, ${unit.label(quantity)}, ${_activityTime.format(at)}';

// A change the device had queued and the server later refused. [what] names
// the entry as it was when written: by the time the refusal arrives the vice
// may be gone, so it cannot be looked up then.
@immutable
class RejectedWrite {
  const RejectedWrite(this.what, this.error);

  final String what;
  final FirebaseException error;

  String get reason => error.code == 'permission-denied'
      ? 'The server refused this change.'
      : 'The server refused this change: ${error.message ?? error.code}';
}

class RejectedWrites extends Notifier<List<RejectedWrite>> {
  @override
  List<RejectedWrite> build() {
    // A listen, not a watch: a rebuild would make a new notifier, and the
    // reporters handed out by the old one would write into nothing.
    ref.listen(
      userProvider.select((AsyncValue<User?> user) => user.value?.uid),
      (_, _) => state = const <RejectedWrite>[],
    );
    return const <RejectedWrite>[];
  }

  /// A callback for settleWrite's onRejectedLater. It drops a refusal that
  /// arrives once another user, or nobody, is signed in: sign-out terminates
  /// Firestore, which may fail the writes it still held.
  void Function(FirebaseException error) reporter(String what) {
    final String? uid = ref.read(userProvider).value?.uid;
    return (FirebaseException error) {
      if (!ref.mounted || ref.read(userProvider).value?.uid != uid) {
        return;
      }
      state = <RejectedWrite>[...state, RejectedWrite(what, error)];
    };
  }

  void dismiss(RejectedWrite rejected) {
    state = <RejectedWrite>[
      for (final RejectedWrite item in state)
        if (!identical(item, rejected)) item,
    ];
  }
}

final rejectedWritesProvider =
    NotifierProvider<RejectedWrites, List<RejectedWrite>>(RejectedWrites.new);
