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
  const RejectedWrite(this.what, this.error, {this.changed});

  final String what;
  final FirebaseException error;
  final String? changed;

  String get reason => error.code == 'permission-denied'
      ? 'The server refused this change.'
      : 'The server refused this change: ${error.message ?? error.code}';
}

class RejectedWrites extends Notifier<List<RejectedWrite>> {
  // Documents whose queued create was refused. Kept past Dismiss: a change
  // queued after the create is refused later, because no document exists.
  final Set<String> _refusedCreates = <String>{};

  @override
  List<RejectedWrite> build() {
    // A listen, not a watch: a rebuild would make a new notifier, and the
    // reporters handed out by the old one would write into nothing.
    ref.listen(
      userProvider.select((AsyncValue<User?> user) => user.value?.uid),
      (_, _) {
        _refusedCreates.clear();
        state = const <RejectedWrite>[];
      },
    );
    return const <RejectedWrite>[];
  }

  /// A callback for settleWrite's onRejectedLater. It drops a refusal that
  /// arrives once another user, or nobody, is signed in: sign-out terminates
  /// Firestore, which may fail the writes it still held.
  ///
  /// [creates] is the id of the document the write creates, and [changes] the
  /// id of the one it updates or deletes. A change to a document whose create
  /// was refused is not shown: the server never held that document, and the
  /// create's own line already names the entry.
  void Function(FirebaseException error) reporter(
    String what, {
    String? creates,
    String? changes,
  }) {
    final String? uid = ref.read(userProvider).value?.uid;
    return (FirebaseException error) {
      if (!ref.mounted || ref.read(userProvider).value?.uid != uid) {
        return;
      }
      if (changes != null && _refusedCreates.contains(changes)) {
        return;
      }
      if (creates != null) {
        _refusedCreates.add(creates);
      }
      state = <RejectedWrite>[
        for (final RejectedWrite item in state)
          if (creates == null || item.changed != creates) item,
        RejectedWrite(what, error, changed: changes),
      ];
    };
  }

  /// Whether the server refused the queued create of [documentID]. A change
  /// queued after it is refused too, and can be refused before its own
  /// timeout; the SDK refuses queued writes in order, so the create's refusal
  /// has been reported by the time the change's arrives.
  bool createRefused(String documentID) => _refusedCreates.contains(documentID);

  void dismiss(RejectedWrite rejected) {
    state = <RejectedWrite>[
      for (final RejectedWrite item in state)
        if (!identical(item, rejected)) item,
    ];
  }
}

final rejectedWritesProvider =
    NotifierProvider<RejectedWrites, List<RejectedWrite>>(RejectedWrites.new);
