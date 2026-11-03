import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/crypto/journal_cipher.dart';
import 'package:tracker/crypto/key_service.dart';
import 'package:tracker/crypto/key_store.dart';
import 'package:tracker/crypto/keys_remote.dart';
import 'package:tracker/crypto/native_aes.dart';
import 'package:tracker/providers/user_provider.dart';

/// Set in main() from checkNativeAesGcm; null means the check never ran.
final nativeAesReportProvider = Provider<NativeAesReport?>((ref) => null);

final keyStoreProvider = Provider<KeyStore>((ref) => SecureKeyStore());

final keyServiceProvider = Provider<KeyService>(
  (ref) => KeyService(
    store: ref.watch(keyStoreProvider),
    remote: FirestoreKeysRemote(),
    aes256: nativeAesGcm(secretKeyLength: 32),
    aes128: nativeAesGcm(secretKeyLength: 16),
  ),
);

/// State changes the key screens cause (setup, unlock, start over), pushed
/// to [journalKeyProvider] after its first resolve.
class JournalKeyEvents {
  final StreamController<(String, JournalKeyState)> _events =
      StreamController<(String, JournalKeyState)>.broadcast();

  void push(String uid, JournalKeyState state) => _events.add((uid, state));

  Stream<JournalKeyState> statesFor(
    String uid,
    Future<JournalKeyState> Function() resolve,
  ) async* {
    try {
      yield await resolve();
    } catch (e) {
      yield KeyError('Could not open your journal: $e');
    }
    yield* _events.stream
        .where(((String, JournalKeyState) e) => e.$1 == uid)
        .map(((String, JournalKeyState) e) => e.$2);
  }

  Future<void> close() => _events.close();
}

final journalKeyEventsProvider = Provider<JournalKeyEvents>((ref) {
  final JournalKeyEvents events = JournalKeyEvents();
  ref.onDispose(events.close);
  return events;
});

/// Loading is AsyncLoading (value null); the rest are [JournalKeyState]s.
/// Watch it; never gate on `ref.read(journalKeyProvider.future)`.
final journalKeyProvider = StreamProvider<JournalKeyState?>((ref) {
  final User? user = ref.watch(userProvider).value;

  if (user == null) {
    return const Stream<JournalKeyState?>.empty();
  }

  final NativeAesReport? report = ref.watch(nativeAesReportProvider);

  if (report == null || !report.native) {
    return Stream<JournalKeyState?>.value(
      KeyError(
        "This device's encryption check failed, so the journal stays closed "
        'rather than fall back to slower, unaudited code. ($report)',
      ),
    );
  }

  final KeyService service = ref.watch(keyServiceProvider);
  return ref
      .watch(journalKeyEventsProvider)
      .statesFor(user.uid, () => service.resolve(user.uid));
});

/// The cipher once the journal is open; null while loading or locked, so
/// a provider that needs it stays loading.
JournalCipher? watchJournalCipher(Ref ref) {
  final JournalKeyState? state = ref.watch(journalKeyProvider).value;
  return state is KeyReady ? state.cipher : null;
}
