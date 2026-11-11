import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/crypto/key_store.dart';
import 'package:tracker/data/day.dart';

/// What the key screens need to know about this device's journal key.
class RecoveryKeyStatus {
  const RecoveryKeyStatus({
    required this.formatted,
    required this.keyCreatedAt,
    this.firstEntryAt,
    this.saved = false,
    this.cardDismissed = false,
    this.location,
    this.syncRefused = false,
    this.syncRefusalStatus,
  });

  /// The recovery key in [RecoveryKey.format]'s groups.
  final String formatted;

  /// When this device made or received the key, as stored on the device.
  final DateTime keyCreatedAt;

  /// The account's first entry; null while unknown.
  final DateTime? firstEntryAt;

  /// The user typed back the last group.
  final bool saved;
  final bool cardDismissed;

  /// Where this device keeps the journal key; null where nothing says.
  final KeyLocation? location;

  /// The keychain refused the last synced lookup or write, with
  /// [syncRefusalStatus] when it gave a status code.
  final bool syncRefused;
  final int? syncRefusalStatus;
}

sealed class UnlockOutcome {
  const UnlockOutcome();
}

class UnlockOpened extends UnlockOutcome {
  const UnlockOpened();
}

/// A well-formed recovery key that opens some other journal.
class UnlockNotThisJournal extends UnlockOutcome {
  const UnlockNotThisJournal();
}

class UnlockFailed extends UnlockOutcome {
  const UnlockFailed(this.message);

  final String message;
}

abstract class RecoveryKeyActions {
  Future<void> markSaved();
  Future<void> dismissCard();
  Future<UnlockOutcome> unlock(Uint8List recoveryKey);

  /// Replaces the journal key with a new one, leaving every entry sealed
  /// under the old key unreadable. Throws when it cannot.
  Future<void> startNewJournal();
}

class _NoKeyActions implements RecoveryKeyActions {
  const _NoKeyActions();

  @override
  Future<void> markSaved() async {}

  @override
  Future<void> dismissCard() async {}

  @override
  Future<UnlockOutcome> unlock(Uint8List recoveryKey) async =>
      const UnlockFailed('This build has no journal key to open.');

  @override
  Future<void> startNewJournal() =>
      Future<void>.error(StateError('This build has no journal key service.'));
}

// The key service (`keyServiceOverrides`) overrides these. Until it does there is no key: the
// card and the gate stay out of the way and the screen says so.
final recoveryKeyStatusProvider = Provider<RecoveryKeyStatus?>((ref) => null);

final recoveryKeyActionsProvider = Provider<RecoveryKeyActions>(
  (ref) => const _NoKeyActions(),
);

/// True when the server holds a journal key this device lacks, so nothing
/// opens until the recovery key is entered.
final journalNeedsRecoveryKeyProvider = Provider<bool>((ref) => false);

/// True while whether this device holds the journal's key is not yet known,
/// so nothing is written until it is.
final journalKeyPendingProvider = Provider<bool>((ref) => false);

/// Hides the card at once on a tap, before the stored flag comes back.
final recoveryCardHiddenProvider = NotifierProvider<RecoveryCardHidden, bool>(
  RecoveryCardHidden.new,
);

class RecoveryCardHidden extends Notifier<bool> {
  @override
  bool build() => false;

  void hide() => state = true;
}

const int recoveryCardDelayDays = 7;

/// Whether Today offers the recovery key: seven local days after the first
/// entry, or after the key's creation when no entry is known.
bool recoveryCardDue(RecoveryKeyStatus? status, DateTime today) {
  if (status == null || status.saved || status.cardDismissed) {
    return false;
  }
  final DateTime from = status.firstEntryAt ?? status.keyCreatedAt;
  return !today.isBefore(addDays(startOfDay(from), recoveryCardDelayDays));
}
