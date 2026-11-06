import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/writes/queued_write_journal.dart';
import 'package:tracker/writes/settle_write.dart';
import 'package:tracker/writes/tracker_writes.dart';

String describeActivity(
  String viceName,
  Unit unit,
  int quantity,
  DateTime at, {
  required bool alwaysUse24HourFormat,
}) =>
    '$viceName, ${unit.label(quantity)}, '
    '${formatDayAndTime(at, alwaysUse24HourFormat: alwaysUse24HourFormat)}';

// A change the device had queued and the server later refused. [what] names
// the entry as it was when written: by the time the refusal arrives the vice
// may be gone, so it cannot be looked up then. [error] is null for a write
// an earlier launch queued: the SDK refuses it without saying why.
@immutable
class RejectedWrite {
  const RejectedWrite(this.what, this.error, {this.changed});

  final String what;
  final FirebaseException? error;
  final String? changed;

  String get reason => switch (error) {
    null || FirebaseException(code: 'permission-denied') =>
      'The server refused this change.',
    final FirebaseException error =>
      'The server refused this change: ${error.message ?? error.code}',
  };
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
      (_, String? uid) {
        _refusedCreates.clear();
        state = const <RejectedWrite>[];
        if (uid != null) {
          unawaited(_reconcile(uid));
        }
      },
    );
    final String? uid = ref.read(userProvider).value?.uid;
    if (uid != null) {
      Future<void>.microtask(() => _reconcile(uid));
    }
    return const <RejectedWrite>[];
  }

  bool _signedIn(String? uid) =>
      ref.mounted && ref.read(userProvider).value?.uid == uid;

  /// Waits as settleWrite does for [write], and names it as [what] in the
  /// banner if the server refuses it after the timeout. Until its future
  /// completes the write is kept in the journal, so that if this launch ends
  /// first, the next one can tell whether the server took it.
  Future<bool> settle(SentWrite write, String what) {
    final String? uid = ref.read(userProvider).value?.uid;
    if (uid != null) {
      final QueuedWriteJournal journal = ref.read(queuedWriteJournalProvider);
      final QueuedWrite entry = QueuedWrite.sent(write, uid: uid, what: what);
      unawaited(journal.add(entry));
      void resolved() => unawaited(journal.remove(<QueuedWrite>[entry]));
      unawaited(
        write.done.then<void>(
          (_) => resolved(),
          onError: (Object _) => resolved(),
        ),
      );
    }
    final bool creates = write.op == WriteOp.create;
    return settleWrite(
      write.done,
      onRejectedLater: reporter(
        what,
        creates: creates ? write.id : null,
        changes: creates ? null : write.id,
      ),
    );
  }

  // Once the earlier launches' queue has drained, checks the server's copy of
  // each document they wrote. A check that fails keeps its writes for the next
  // launch.
  Future<void> _reconcile(String uid) async {
    final QueuedWriteJournal journal = ref.read(queuedWriteJournalProvider);
    final Map<String, List<QueuedWrite>> earlier = await journal.claimEarlier(
      uid,
    );
    if (earlier.isEmpty) {
      return;
    }
    final List<List<QueuedWrite>> unchecked = earlier.values.toList();
    try {
      if (!_signedIn(uid)) {
        return;
      }
      final TrackerWrites writes = ref.read(trackerWritesProvider);
      // Rejected when the user changes, which ends this check anyway.
      await writes.waitForPendingWrites();
      while (unchecked.isNotEmpty && _signedIn(uid)) {
        final List<QueuedWrite> document = unchecked.first;
        final String path = document.first.document;
        if (!journal.replaced(path)) {
          final Map<String, Object?>? server = await writes.serverDocument(
            document.first.collection,
            document.first.id,
            ownerID: uid,
          );
          if (!_signedIn(uid)) {
            return;
          }
          for (final QueuedWrite refused in refusedAmong(
            document,
            server,
            ignoring: journal.fieldsSet(path),
          )) {
            _report(
              refused.what,
              null,
              creates: refused.op == WriteOp.create ? refused.id : null,
              changes: refused.op == WriteOp.create ? null : refused.id,
            );
          }
        }
        unchecked.removeAt(0);
        unawaited(journal.remove(document));
      }
    } catch (e, stack) {
      reportError(
        e,
        stack,
        context: 'while checking the writes an earlier launch queued',
      );
    } finally {
      journal.release(unchecked.expand((List<QueuedWrite> d) => d));
    }
  }

  /// The settleWrite onRejectedLater callback [settle] passes. It drops a
  /// refusal that arrives once another user, or nobody, is signed in:
  /// sign-out terminates Firestore, which may fail the writes it still held.
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
      if (_signedIn(uid)) {
        _report(what, error, creates: creates, changes: changes);
      }
    };
  }

  void _report(
    String what,
    FirebaseException? error, {
    String? creates,
    String? changes,
  }) {
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
