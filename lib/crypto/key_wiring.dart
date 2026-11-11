import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:tracker/crypto/e2ee_enabled.dart';
import 'package:tracker/crypto/key_service.dart';
import 'package:tracker/crypto/key_store.dart';
import 'package:tracker/crypto/native_aes.dart';
import 'package:tracker/crypto/recovery_key.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/journal_key/recovery_key_state.dart';
import 'package:tracker/providers/signed_in_user.dart';
import 'package:tracker/providers/user_provider.dart';

final keyServiceProvider = Provider<KeyService>(
  (ref) => KeyService(
    store: KeyStore(),
    directory: FirestoreKeyDirectory(FirebaseFirestore.instance),
    aes128: nativeAesGcm(secretKeyLength: 16),
    aes256: nativeAesGcm(secretKeyLength: 32),
    rechecks: keychainRechecks,
  ),
);

/// Every few seconds and on app resume, for as long as it is listened to.
/// iOS suspends timers in the background, so the resume event matters there.
/// Used while the journal is locked, and while no key is known.
Stream<void> keychainRechecks({Duration every = const Duration(seconds: 5)}) {
  Timer? timer;
  AppLifecycleListener? lifecycle;
  late final StreamController<void> controller;
  controller = StreamController<void>(
    onListen: () {
      // A recheck while the last one runs is dropped, not queued behind it.
      void recheck() {
        if (!controller.isPaused) {
          controller.add(null);
        }
      }

      timer = Timer.periodic(every, (_) => recheck());
      lifecycle = AppLifecycleListener(onResume: recheck);
    },
    onCancel: () {
      timer?.cancel();
      lifecycle?.dispose();
    },
  );
  return controller.stream;
}

final journalKeyForUserProvider = StreamProvider.autoDispose
    .family<JournalKeyState, String>(
      (ref, uid) => ref.watch(keyServiceProvider).resolve(uid),
    );

final journalKeyProvider = Provider.autoDispose<AsyncValue<JournalKeyState>>(
  (ref) => watchForSignedInUser(ref, journalKeyForUserProvider.call),
);

JournalKeyState? _enabledState(Ref ref) =>
    ref.watch(e2eeEnabledProvider) ? ref.watch(journalKeyProvider).value : null;

class _ServiceKeyActions implements RecoveryKeyActions {
  _ServiceKeyActions(this._ref);

  final Ref _ref;

  KeyService get _service => _ref.read(keyServiceProvider);

  String get _uid {
    final String? uid = _ref.read(userProvider).value?.uid;
    if (uid == null) {
      throw StateError('No user is signed in.');
    }
    return uid;
  }

  void _refresh(String uid) => _ref.invalidate(journalKeyForUserProvider(uid));

  @override
  Future<void> markSaved() async {
    final String uid = _uid;
    await _service.directory.setFlags(uid, saved: true);
    _refresh(uid);
  }

  @override
  Future<void> dismissCard() async {
    final String uid = _uid;
    await _service.directory.setFlags(uid, cardDismissed: true);
    _refresh(uid);
  }

  @override
  Future<UnlockOutcome> unlock(Uint8List recoveryKey) async {
    final String uid = _uid;
    final JournalKeyState? state = _ref.read(journalKeyProvider).value;
    if (state is! KeyNeedsRecovery) {
      return const UnlockFailed('There is no locked journal to open.');
    }
    try {
      if (!await _service.unlock(uid, state.record, recoveryKey)) {
        return const UnlockNotThisJournal();
      }
    } catch (e) {
      return const UnlockFailed(
        "Couldn't keep the key on this device. Try again.",
      );
    }
    _refresh(uid);
    return const UnlockOpened();
  }

  @override
  Future<void> startNewJournal() async {
    final String uid = _uid;
    await _service.startNewJournal(uid);
    _refresh(uid);
  }
}

/// The key service in place of the inert defaults. Every override reads
/// [e2eeEnabledProvider] first, so with E2EE off none of them reaches the
/// keychain or Firestore and the app behaves as with no overrides.
final List<Override> keyServiceOverrides = <Override>[
  sealerProvider.overrideWith(
    (ref) => switch (_enabledState(ref)) {
      final KeyReady ready => ready.sealer,
      _ => null,
    },
  ),
  recoveryKeyStatusProvider.overrideWith(
    (ref) => switch (_enabledState(ref)) {
      KeyReady(
        stored: StoredKey(
          recoveryKey: final Uint8List recovery,
          :final KeyLocation location,
          :final SyncRefusal? syncRefusal,
        ),
        record: final KeyRecord record,
      ) =>
        RecoveryKeyStatus(
          formatted: RecoveryKey.format(recovery),
          location: location,
          syncRefused: syncRefusal != null,
          syncRefusalStatus: syncRefusal?.status,
          keyCreatedAt: record.createdAt,
          saved: record.saved,
          cardDismissed: record.cardDismissed,
        ),
      _ => null,
    },
  ),
  recoveryKeyActionsProvider.overrideWith(_ServiceKeyActions.new),
  journalNeedsRecoveryKeyProvider.overrideWith(
    (ref) => _enabledState(ref) is KeyNeedsRecovery,
  ),
  journalKeyAwaitingSyncProvider.overrideWith(
    (ref) => switch (_enabledState(ref)) {
      KeyNeedsRecovery(otherKeyHere: false) => true,
      _ => false,
    },
  ),
  // No key here and the server not yet asked: nothing can be saved, since the
  // rules refuse a create without its sealed field.
  journalKeyPendingProvider.overrideWith(
    (ref) =>
        ref.watch(e2eeEnabledProvider) &&
        !ref.watch(journalKeyProvider).hasValue &&
        !ref.watch(journalKeyProvider).hasError,
  ),
];
