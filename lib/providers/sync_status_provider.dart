import 'dart:async';

import 'package:clock/clock.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/providers/user_provider.dart';

enum SyncState {
  // Not yet known, or the wait failed (as when sign-out terminates Firestore).
  unknown,
  pending,
  synced,
}

@immutable
class SyncStatus {
  const SyncStatus(this.state, {this.lastSynced});

  final SyncState state;
  // When the last write this session was acknowledged; null if none was.
  final DateTime? lastSynced;

  @override
  bool operator ==(Object other) =>
      other is SyncStatus &&
      other.state == state &&
      other.lastSynced == lastSynced;

  @override
  int get hashCode => Object.hash(state, lastSynced);
}

// FirebaseFirestore.waitForPendingWrites: it completes once every write
// issued before the call, for the signed-in user, has been acknowledged by
// the backend, writes queued by an earlier session included, and it is
// rejected when the user changes. Tests override it.
final pendingWritesWaiterProvider = Provider<Future<void> Function()>(
  (ref) =>
      () => FirebaseFirestore.instance.waitForPendingWrites(),
);

// Whether everything written has reached the server. It waits again after
// every write (TrackerWrites reports each one), since a wait covers only the
// writes issued before it.
final syncStatusProvider = NotifierProvider<SyncTracker, SyncStatus>(
  SyncTracker.new,
);

class SyncTracker extends Notifier<SyncStatus> {
  // A first wait that takes this long has writes from an earlier session to
  // send; a quicker one never shows as pending.
  static const Duration slowAfter = Duration(seconds: 1);

  int _generation = 0;
  Timer? _slow;

  @override
  SyncStatus build() {
    final String? uid = ref.watch(
      userProvider.select((AsyncValue<User?> user) => user.value?.uid),
    );
    final int built = ++_generation;
    _slow?.cancel();
    ref.onDispose(() {
      _generation++;
      _slow?.cancel();
    });
    if (uid != null) {
      scheduleMicrotask(() {
        if (built == _generation) {
          _wait(fromWrite: false);
        }
      });
    }
    return const SyncStatus(SyncState.unknown);
  }

  void track() => _wait(fromWrite: true);

  void _wait({required bool fromWrite}) {
    final int g = ++_generation;
    _slow?.cancel();
    if (fromWrite) {
      state = SyncStatus(SyncState.pending, lastSynced: state.lastSynced);
    } else {
      _slow = Timer(slowAfter, () {
        if (g == _generation && state.state != SyncState.synced) {
          state = SyncStatus(SyncState.pending, lastSynced: state.lastSynced);
        }
      });
    }
    Future<void>.sync(ref.read(pendingWritesWaiterProvider)).then(
      (_) {
        if (g != _generation) {
          return;
        }
        _slow?.cancel();
        final bool sent = state.state == SyncState.pending;
        state = SyncStatus(
          SyncState.synced,
          lastSynced: sent ? clock.now() : state.lastSynced,
        );
      },
      onError: (Object _) {
        if (g != _generation) {
          return;
        }
        _slow?.cancel();
        state = SyncStatus(SyncState.unknown, lastSynced: state.lastSynced);
      },
    );
  }
}
