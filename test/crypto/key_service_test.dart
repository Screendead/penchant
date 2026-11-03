import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/crypto/key_service.dart';
import 'package:tracker/crypto/key_store.dart';
import 'package:tracker/crypto/keys_remote.dart';
import 'package:tracker/crypto/recovery_key.dart';

import 'fakes.dart';

const String uid = 'alice';

void main() {
  late FakeKeyStore store;
  late FakeKeysRemote remote;
  late KeyService service;

  KeyService serviceOn(FakeKeyStore s, {int seed = 1}) => KeyService(
    store: s,
    remote: remote,
    aes256: AesGcm.with256bits(),
    aes128: AesGcm.with128bits(),
    random: Random(seed),
  );

  setUp(() {
    store = FakeKeyStore();
    remote = FakeKeysRemote();
    service = serviceOn(store);
  });

  test('a new user needs setup, and setup stores the key on both sides', () async {
    expect(await service.resolve(uid), isA<KeyNeedsSetup>());

    final KeyReady ready = await service.setUp(uid);

    expect(remote.docs[uid]!.keyId, ready.stored.keyId);
    expect(store.keys[uid]!.dek, ready.stored.dek);
    expect(RecoveryKey.parse(ready.stored.recoveryKey!), isA<RecoveryKeyOk>());
    expect(await service.resolve(uid), isA<KeyReady>());
  });

  group('never mints while keys/{uid} exists', () {
    test('a second device with an empty keychain asks to unlock', () async {
      await service.setUp(uid);
      final FakeKeyStore fresh = FakeKeyStore();
      final KeyService other = serviceOn(fresh, seed: 2);

      expect(await other.resolve(uid), isA<KeyNeedsUnlock>());
      await expectLater(other.setUp(uid), throwsA(isA<KeyServiceRefused>()));
      expect(remote.creates, 1);
      expect(fresh.keys, isEmpty);
    });

    test('offline with no local key is an error, and setup refuses', () async {
      remote.offline = true;

      expect(await service.resolve(uid), isA<KeyError>());
      await expectLater(service.setUp(uid), throwsA(isA<Offline>()));
      expect(remote.creates, 0);
      expect(store.keys, isEmpty);
    });

    test('losing a race to another device wipes the local candidate', () async {
      final KeysDoc theirs = KeysDoc(
        keyId: 'theirs',
        check: Uint8List(44),
        recoveryWrap: Uint8List(60),
      );
      remote.raceWith = theirs;

      await expectLater(service.setUp(uid), throwsA(isA<KeyServiceRefused>()));
      expect(store.keys, isEmpty);
      expect(remote.docs[uid], same(theirs));
      expect(await service.resolve(uid), isA<KeyNeedsUnlock>());
    });

    test('a device holding a key refuses to mint another', () async {
      await service.setUp(uid);
      remote.docs.clear();
      await expectLater(service.setUp(uid), throwsA(isA<KeyServiceRefused>()));
    });
  });

  test('offline with a local key opens the journal', () async {
    await service.setUp(uid);
    remote.offline = true;
    expect(await service.resolve(uid), isA<KeyReady>());
  });

  test('a local key the server lost is re-registered, not replaced', () async {
    final KeyReady ready = await service.setUp(uid);
    remote.docs.clear();

    expect(await service.resolve(uid), isA<KeyReady>());
    expect(remote.docs[uid]!.keyId, ready.stored.keyId);
    expect(remote.creates, 2);
  });

  test('a stale local key (another device started over) asks to unlock', () async {
    await service.setUp(uid);
    final StoredKey stale = store.keys[uid]!;
    await serviceOn(store, seed: 3).startOver(uid, deleteJournal: () async {});
    store.keys[uid] = stale;

    expect(await service.resolve(uid), isA<KeyNeedsUnlock>());
  });

  group('unlock with the recovery key', () {
    late KeyReady original;
    late FakeKeyStore fresh;
    late KeyService newDevice;

    setUp(() async {
      original = await service.setUp(uid);
      fresh = FakeKeyStore();
      newDevice = serviceOn(fresh, seed: 9);
    });

    test('the right key restores the same journal key', () async {
      final UnlockResult result = await newDevice.unlock(
        uid,
        original.stored.recoveryKey!.toLowerCase(),
      );
      expect(result, isA<Unlocked>());
      expect(fresh.keys[uid]!.dek, original.stored.dek);
      expect(fresh.keys[uid]!.keyId, original.stored.keyId);
    });

    test('a typo is located and nothing is stored', () async {
      final String plain = RecoveryKey.normalise(original.stored.recoveryKey!);
      final String typo = plain.replaceRange(9, 10, plain[9] == 'X' ? 'Y' : 'X');

      final UnlockResult result = await newDevice.unlock(uid, typo);
      final RecoveryKeyParse? parse = (result as UnlockRejected).parse;
      expect((parse as RecoveryKeyTypo).position, 10);
      expect(fresh.keys, isEmpty);
    });

    test("another journal's valid key is rejected", () async {
      final String other = RecoveryKey.format(RecoveryKey.generate(Random(99)));
      final UnlockResult result = await newDevice.unlock(uid, other);
      expect((result as UnlockRejected).parse, isNull);
      expect(fresh.keys, isEmpty);
    });
  });

  test('starting over deletes the journal before the key, then mints anew', () async {
    final KeyReady first = await service.setUp(uid);
    final KeyReady second = await service.startOver(
      uid,
      deleteJournal: () async => remote.log.add('delete journal'),
    );

    expect(remote.log, ['create keys', 'delete journal', 'delete keys', 'create keys']);
    expect(second.stored.keyId, isNot(first.stored.keyId));
    expect(second.stored.dek, isNot(first.stored.dek));
  });
}
