import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/crypto/e2ee_enabled.dart';
import 'package:tracker/crypto/journal_key.dart';
import 'package:tracker/crypto/key_service.dart';
import 'package:tracker/crypto/key_store.dart';
import 'package:tracker/crypto/key_wiring.dart';
import 'package:tracker/crypto/recovery_key.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/journal_key/recovery_key_state.dart';
import 'package:tracker/providers/user_provider.dart';

import '../fakes.dart';

class FakeKeyStore extends Fake implements KeyStore {
  final Map<String, StoredKey> keys = <String, StoredKey>{};

  /// Thrown by the next read, as by a keychain that refuses it once.
  Exception? nextReadError;

  @override
  Future<StoredKey?> read(String uid) async {
    final Exception? error = nextReadError;
    nextReadError = null;
    if (error != null) throw error;
    return keys[uid];
  }

  @override
  Future<StoredKey> save(
    String uid, {
    required JournalKey journalKey,
    Uint8List? recoveryKey,
  }) async {
    final StoredKey? existing = keys[uid];
    if (existing != null && !existing.journalKey.sameAs(journalKey)) {
      throw KeyConflictException(uid);
    }
    return keys[uid] = StoredKey(
      journalKey: journalKey,
      recoveryKey: recoveryKey ?? existing?.recoveryKey,
      location: KeyLocation.synced,
    );
  }

  @override
  Future<void> delete(String uid) async => keys.remove(uid);
}

class FakeKeyDirectory implements KeyDirectory {
  final Map<String, KeyRecord> records = <String, KeyRecord>{};
  bool offline = false;
  bool denied = false;

  /// Lands just before this device's create, as from another device.
  KeyRecord? racing;

  @override
  Future<KeyRecord?> fetch(String uid) async {
    if (offline || denied) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: offline ? 'unavailable' : 'permission-denied',
      );
    }
    return records[uid];
  }

  @override
  Future<KeyRecord> createIfAbsent(String uid, KeyRecord record) async {
    final KeyRecord? other = racing;
    if (other != null) {
      records[uid] = other;
    }
    return records[uid] ??= record;
  }

  @override
  Future<void> replace(String uid, KeyRecord record) async =>
      records[uid] = record;

  @override
  Future<void> setFlags(String uid, {bool? saved, bool? cardDismissed}) async {
    final KeyRecord r = records[uid]!;
    records[uid] = KeyRecord(
      keyID: r.keyID,
      wrapped: r.wrapped,
      createdAt: r.createdAt,
      saved: saved ?? r.saved,
      cardDismissed: cardDismissed ?? r.cardDismissed,
    );
  }
}

const String uid = 'u1';
final DateTime made = DateTime(2026, 11, 7, 9);

KeyService serviceOver(
  FakeKeyStore store,
  FakeKeyDirectory directory, {
  Stream<void> Function()? rechecks,
}) => KeyService(
  store: store,
  directory: directory,
  aes128: AesGcm.with128bits(),
  aes256: AesGcm.with256bits(),
  now: () => made,
  rechecks: rechecks ?? () => const Stream<void>.empty(),
);

Future<KeyRecord> recordOf(KeyService service, StoredKey stored) async =>
    KeyRecord(
      keyID: keyIDOf(stored.journalKey),
      wrapped: await stored.journalKey.wrap(
        aes128: AesGcm.with128bits(),
        recoveryKey: stored.recoveryKey!,
        uid: uid,
      ),
      createdAt: made,
    );

void main() {
  late FakeKeyStore store;
  late FakeKeyDirectory directory;
  late KeyService service;

  setUp(() {
    store = FakeKeyStore();
    directory = FakeKeyDirectory();
    service = serviceOver(store, directory);
  });

  test('the key id is 24 characters and differs between keys', () {
    final String a = keyIDOf(JournalKey.generate());
    expect(a, hasLength(24));
    expect(keyIDOf(JournalKey.generate()), isNot(a));
  });

  test('with no key anywhere, makes one, keeps it in the keychain, and '
      'records only its id and wrapped copy', () async {
    final List<JournalKeyState> states = await service.resolve(uid).toList();

    final KeyReady ready = states.single as KeyReady;
    final StoredKey stored = store.keys[uid]!;
    expect(ready.stored.journalKey.sameAs(stored.journalKey), isTrue);
    expect(stored.recoveryKey, hasLength(RecoveryKey.keyLength));
    final KeyRecord record = directory.records[uid]!;
    expect(ready.record, same(record));
    expect(record.keyID, keyIDOf(stored.journalKey));
    expect(record.createdAt, made);
    expect(record.wrapped, hasLength(61));
    final JournalKey unwrapped = await JournalKey.unwrap(
      record.wrapped,
      aes128: AesGcm.with128bits(),
      recoveryKey: stored.recoveryKey!,
      uid: uid,
    );
    expect(unwrapped.sameAs(stored.journalKey), isTrue);
  });

  test('a key in the keychain seals at once, then is checked against the '
      'server', () async {
    final StoredKey stored = await store.save(
      uid,
      journalKey: JournalKey.generate(),
      recoveryKey: RecoveryKey.generate(),
    );
    directory.records[uid] = await recordOf(service, stored);

    final List<JournalKeyState> states = await service.resolve(uid).toList();

    expect(states, hasLength(2));
    expect((states[0] as KeyReady).record, isNull);
    expect((states[1] as KeyReady).record, same(directory.records[uid]));
  });

  test('a key only in the keychain is recorded on the server', () async {
    final StoredKey stored = await store.save(
      uid,
      journalKey: JournalKey.generate(),
      recoveryKey: RecoveryKey.generate(),
    );

    final List<JournalKeyState> states = await service.resolve(uid).toList();

    expect(states.last, isA<KeyReady>());
    expect(directory.records[uid]!.keyID, keyIDOf(stored.journalKey));
  });

  test('a key on the server but not here needs the recovery key', () async {
    final StoredKey elsewhere = StoredKey(
      journalKey: JournalKey.generate(),
      recoveryKey: RecoveryKey.generate(),
      location: KeyLocation.synced,
    );
    directory.records[uid] = await recordOf(service, elsewhere);

    final List<JournalKeyState> states = await service.resolve(uid).toList();

    expect(states.single, isA<KeyNeedsRecovery>());
    expect(store.keys, isEmpty);
  });

  test('another key on the server than here needs the recovery key', () async {
    await store.save(uid, journalKey: JournalKey.generate());
    final StoredKey elsewhere = StoredKey(
      journalKey: JournalKey.generate(),
      recoveryKey: RecoveryKey.generate(),
      location: KeyLocation.synced,
    );
    directory.records[uid] = await recordOf(service, elsewhere);

    final List<JournalKeyState> states = await service.resolve(uid).toList();

    expect(states.first, isA<KeyReady>());
    expect(states.last, isA<KeyNeedsRecovery>());
  });

  group('while locked, the keychain is read again', () {
    late StreamController<void> recheck;
    late StoredKey elsewhere;
    late KeyService rechecking;

    setUp(() async {
      recheck = StreamController<void>();
      elsewhere = StoredKey(
        journalKey: JournalKey.generate(),
        recoveryKey: RecoveryKey.generate(),
        location: KeyLocation.synced,
      );
      directory.records[uid] = await recordOf(service, elsewhere);
      rechecking = serviceOver(
        store,
        directory,
        rechecks: () => recheck.stream,
      );
    });

    tearDown(() => recheck.close());

    test(
      'and the journal opens when iCloud Keychain delivers the key',
      () async {
        final StreamIterator<JournalKeyState> states =
            StreamIterator<JournalKeyState>(rechecking.resolve(uid));
        addTearDown(states.cancel);
        expect(await states.moveNext(), isTrue);
        expect(states.current, isA<KeyNeedsRecovery>());

        final Future<bool> next = states.moveNext();
        recheck.add(null);
        await pumpEventQueue();
        store.keys[uid] = elsewhere;
        recheck.add(null);

        expect(await next, isTrue);
        final KeyReady ready = states.current as KeyReady;
        expect(ready.stored.journalKey.sameAs(elsewhere.journalKey), isTrue);
        expect(ready.record, same(directory.records[uid]));
        expect(await states.moveNext(), isFalse);
        expect(recheck.hasListener, isFalse);
      },
    );

    test('past a refused read and another key, until the right one', () async {
      final StreamIterator<JournalKeyState> states =
          StreamIterator<JournalKeyState>(rechecking.resolve(uid));
      addTearDown(states.cancel);
      expect(await states.moveNext(), isTrue);
      final Future<bool> next = states.moveNext();
      bool moved = false;
      unawaited(next.then((_) => moved = true));

      store.nextReadError = PlatformException(code: '-25308');
      recheck.add(null);
      await pumpEventQueue();
      store.keys[uid] = StoredKey(
        journalKey: JournalKey.generate(),
        location: KeyLocation.synced,
      );
      recheck.add(null);
      await pumpEventQueue();
      expect(moved, isFalse);

      store.keys[uid] = elsewhere;
      recheck.add(null);
      expect(await next, isTrue);
      expect(states.current, isA<KeyReady>());
    });

    test('and stops when nothing listens any more', () async {
      final StreamSubscription<JournalKeyState> sub = rechecking
          .resolve(uid)
          .listen((_) {});
      await pumpUntil(() => recheck.hasListener);

      await sub.cancel();

      expect(recheck.hasListener, isFalse);
    });
  });

  test('a device that loses the race to make the first key adopts the '
      "other's and asks for its recovery key", () async {
    final StoredKey other = StoredKey(
      journalKey: JournalKey.generate(),
      recoveryKey: RecoveryKey.generate(),
      location: KeyLocation.synced,
    );
    directory.racing = await recordOf(service, other);

    final List<JournalKeyState> states = await service.resolve(uid).toList();

    expect(states.single, isA<KeyNeedsRecovery>());
    expect(directory.records[uid]!.keyID, keyIDOf(other.journalKey));
  });

  test('offline with no key here, nothing is made', () async {
    directory.offline = true;

    final List<JournalKeyState> states = await service.resolve(uid).toList();

    expect(states.single, isA<KeyUnknown>());
    expect(store.keys, isEmpty);
    expect(directory.records, isEmpty);
  });

  group('offline with no key here, each recheck asks again', () {
    late StreamController<void> recheck;
    late KeyService rechecking;

    setUp(() {
      directory.offline = true;
      recheck = StreamController<void>();
      rechecking = serviceOver(
        store,
        directory,
        rechecks: () => recheck.stream,
      );
    });

    tearDown(() => recheck.close());

    Future<StreamIterator<JournalKeyState>> unknown() async {
      final StreamIterator<JournalKeyState> states =
          StreamIterator<JournalKeyState>(rechecking.resolve(uid));
      addTearDown(states.cancel);
      expect(await states.moveNext(), isTrue);
      expect(states.current, isA<KeyUnknown>());
      return states;
    }

    test('and makes the first key once the server answers', () async {
      final StreamIterator<JournalKeyState> states = await unknown();
      final Future<bool> next = states.moveNext();
      recheck.add(null);
      await pumpEventQueue();
      expect(store.keys, isEmpty);

      directory.offline = false;
      recheck.add(null);

      expect(await next, isTrue);
      final KeyReady ready = states.current as KeyReady;
      expect(ready.record!.keyID, keyIDOf(store.keys[uid]!.journalKey));
      expect(await states.moveNext(), isFalse);
      expect(recheck.hasListener, isFalse);
    });

    test('and uses a key that syncs in while still offline', () async {
      final StreamIterator<JournalKeyState> states = await unknown();
      final StoredKey synced = await store.save(
        uid,
        journalKey: JournalKey.generate(),
      );
      recheck.add(null);

      expect(await states.moveNext(), isTrue);
      final KeyReady ready = states.current as KeyReady;
      expect(ready.stored.journalKey.sameAs(synced.journalKey), isTrue);
      expect(ready.record, isNull);
      expect(await states.moveNext(), isFalse);
    });

    test(
      'and locks behind the recovery key when the server names another',
      () async {
        final StreamIterator<JournalKeyState> states = await unknown();
        directory.records[uid] = await recordOf(
          service,
          StoredKey(
            journalKey: JournalKey.generate(),
            recoveryKey: RecoveryKey.generate(),
            location: KeyLocation.synced,
          ),
        );
        directory.offline = false;
        recheck.add(null);

        expect(await states.moveNext(), isTrue);
        expect(states.current, isA<KeyNeedsRecovery>());
        expect(store.keys, isEmpty);
      },
    );
  });

  test('a read denied after sign-out ends quietly and makes nothing', () async {
    directory.denied = true;

    final List<JournalKeyState> states = await service.resolve(uid).toList();

    expect(states.single, isA<KeyUnknown>());
    expect(store.keys, isEmpty);
  });

  test('offline with a key here, it is used unchecked', () async {
    await store.save(uid, journalKey: JournalKey.generate());
    directory.offline = true;

    final List<JournalKeyState> states = await service.resolve(uid).toList();

    expect((states.single as KeyReady).record, isNull);
  });

  test('the recovery key opens the wrapped copy and replaces a stale key '
      'here; another recovery key does not', () async {
    await store.save(uid, journalKey: JournalKey.generate());
    final StoredKey elsewhere = StoredKey(
      journalKey: JournalKey.generate(),
      recoveryKey: RecoveryKey.generate(),
      location: KeyLocation.synced,
    );
    final KeyRecord record = await recordOf(service, elsewhere);

    expect(await service.unlock(uid, record, RecoveryKey.generate()), isFalse);
    expect(await service.unlock(uid, record, elsewhere.recoveryKey!), isTrue);

    final StoredKey here = store.keys[uid]!;
    expect(here.journalKey.sameAs(elsewhere.journalKey), isTrue);
    expect(here.recoveryKey, elsewhere.recoveryKey);
  });

  test('a new journal replaces the key here and on the server', () async {
    await service.resolve(uid).toList();
    final String before = directory.records[uid]!.keyID;
    await service.setFlagsForTest(uid);

    await service.startNewJournal(uid);

    final KeyRecord after = directory.records[uid]!;
    expect(after.keyID, isNot(before));
    expect(after.keyID, keyIDOf(store.keys[uid]!.journalKey));
    expect(after.saved, isFalse);
    expect((await service.resolve(uid).toList()).last, isA<KeyReady>());
  });

  group('keyServiceOverrides', () {
    ProviderContainer containerWith({required bool enabled}) =>
        ProviderContainer(
          overrides: [
            ...keyServiceOverrides,
            e2eeEnabledProvider.overrideWithValue(enabled),
            keyServiceProvider.overrideWithValue(service),
            userProvider.overrideWith((ref) => Stream.value(FakeUser(uid))),
          ],
        );

    test('with E2EE off, nothing reaches the key service', () async {
      final ProviderContainer container = containerWith(enabled: false);
      addTearDown(container.dispose);
      container.listen(userProvider, (_, _) {});
      await pumpUntil(() => container.read(userProvider).hasValue);

      expect(container.read(sealerProvider), isNull);
      expect(container.read(recoveryKeyStatusProvider), isNull);
      expect(container.read(journalNeedsRecoveryKeyProvider), isFalse);
      expect(container.read(journalKeyPendingProvider), isFalse);
      await pumpEventQueue();
      expect(store.keys, isEmpty);
      expect(directory.records, isEmpty);
    });

    test('with E2EE on, the gate waits for the key, then sealing starts and '
        'the card can show', () async {
      final ProviderContainer container = containerWith(enabled: true);
      addTearDown(container.dispose);
      container.listen(sealerProvider, (_, _) {});
      container.listen(recoveryKeyStatusProvider, (_, _) {});
      container.listen(journalKeyPendingProvider, (_, _) {});
      expect(container.read(journalKeyPendingProvider), isTrue);

      await pumpUntil(() => container.read(recoveryKeyStatusProvider) != null);

      expect(container.read(sealerProvider), isNotNull);
      expect(container.read(journalKeyPendingProvider), isFalse);
      final RecoveryKeyStatus status = container.read(
        recoveryKeyStatusProvider,
      )!;
      expect(
        status.formatted,
        RecoveryKey.format(store.keys[uid]!.recoveryKey!),
      );
      expect(status.keyCreatedAt, made);

      await container.read(recoveryKeyActionsProvider).markSaved();
      await pumpUntil(
        () => container.read(recoveryKeyStatusProvider)?.saved ?? false,
      );
      expect(directory.records[uid]!.saved, isTrue);
    });

    test('with E2EE on, a key elsewhere locks the journal until the recovery '
        'key opens it', () async {
      final StoredKey elsewhere = StoredKey(
        journalKey: JournalKey.generate(),
        recoveryKey: RecoveryKey.generate(),
        location: KeyLocation.synced,
      );
      directory.records[uid] = await recordOf(service, elsewhere);
      final ProviderContainer container = containerWith(enabled: true);
      addTearDown(container.dispose);
      container.listen(sealerProvider, (_, _) {});
      container.listen(journalNeedsRecoveryKeyProvider, (_, _) {});

      await pumpUntil(() => container.read(journalNeedsRecoveryKeyProvider));
      expect(container.read(sealerProvider), isNull);

      final RecoveryKeyActions actions = container.read(
        recoveryKeyActionsProvider,
      );
      expect(
        await actions.unlock(RecoveryKey.generate()),
        isA<UnlockNotThisJournal>(),
      );
      expect(await actions.unlock(elsewhere.recoveryKey!), isA<UnlockOpened>());
      await pumpUntil(() => container.read(sealerProvider) != null);
      expect(container.read(journalNeedsRecoveryKeyProvider), isFalse);
    });

    test('with E2EE on, a key that syncs in later opens the journal with '
        'nothing typed', () async {
      final StreamController<void> recheck = StreamController<void>.broadcast();
      addTearDown(recheck.close);
      service = serviceOver(store, directory, rechecks: () => recheck.stream);
      final StoredKey elsewhere = StoredKey(
        journalKey: JournalKey.generate(),
        recoveryKey: RecoveryKey.generate(),
        location: KeyLocation.synced,
      );
      directory.records[uid] = await recordOf(service, elsewhere);
      final ProviderContainer container = containerWith(enabled: true);
      addTearDown(container.dispose);
      container.listen(sealerProvider, (_, _) {});
      container.listen(journalNeedsRecoveryKeyProvider, (_, _) {});
      await pumpUntil(() => container.read(journalNeedsRecoveryKeyProvider));

      store.keys[uid] = elsewhere;
      recheck.add(null);

      await pumpUntil(() => container.read(sealerProvider) != null);
      expect(container.read(journalNeedsRecoveryKeyProvider), isFalse);
    });

    test('with E2EE on, a lost key gives way to a new journal', () async {
      final StoredKey elsewhere = StoredKey(
        journalKey: JournalKey.generate(),
        recoveryKey: RecoveryKey.generate(),
        location: KeyLocation.synced,
      );
      directory.records[uid] = await recordOf(service, elsewhere);
      final ProviderContainer container = containerWith(enabled: true);
      addTearDown(container.dispose);
      container.listen(sealerProvider, (_, _) {});
      container.listen(journalNeedsRecoveryKeyProvider, (_, _) {});
      await pumpUntil(() => container.read(journalNeedsRecoveryKeyProvider));

      await container.read(recoveryKeyActionsProvider).startNewJournal();

      await pumpUntil(() => container.read(sealerProvider) != null);
      expect(
        directory.records[uid]!.keyID,
        keyIDOf(store.keys[uid]!.journalKey),
      );
    });
  });
}

Future<void> pumpUntil(bool Function() done) async {
  for (int i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue);
}

extension on KeyService {
  Future<void> setFlagsForTest(String uid) =>
      directory.setFlags(uid, saved: true);
}
