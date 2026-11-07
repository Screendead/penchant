import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/crypto/journal_key.dart';
import 'package:tracker/crypto/key_store.dart';
import 'package:tracker/crypto/recovery_key.dart';

import '../fake_keychain.dart';

void main() {
  final JournalKey key = JournalKey.generate(Random(1));
  final Uint8List recovery = RecoveryKey.generate(Random(2));

  test('reads nothing for a uid with no key', () async {
    expect(await KeyStore(FakeKeychain()).read('u1'), isNull);
  });

  test('saves a synced item and reads it back', () async {
    final FakeKeychain keychain = FakeKeychain();
    final KeyStore store = KeyStore(keychain);

    final StoredKey saved = await store.save(
      'u1',
      journalKey: key,
      recoveryKey: recovery,
    );
    expect(saved.location, KeyLocation.synced);
    expect(keychain.items.keys, <(String, bool)>[
      (KeyStore.itemName('u1'), true),
    ]);

    final StoredKey read = (await store.read('u1'))!;
    expect(read.journalKey.sameAs(key), isTrue);
    expect(read.recoveryKey, recovery);
    expect(read.location, KeyLocation.synced);
  });

  test('keeps the key on this device when synced items are refused', () async {
    final FakeKeychain keychain = FakeKeychain(refuseSynced: true);
    final KeyStore store = KeyStore(keychain);

    expect(
      (await store.save('u1', journalKey: key)).location,
      KeyLocation.thisDevice,
    );
    expect(keychain.items.keys, <(String, bool)>[
      (KeyStore.itemName('u1'), false),
    ]);
    expect((await store.read('u1'))!.location, KeyLocation.thisDevice);
  });

  test(
    'reaches the this-device item when synced lookups are refused too',
    () async {
      final FakeKeychain keychain = FakeKeychain(
        refuseSynced: true,
        refuseSyncedReads: true,
      );
      final KeyStore store = KeyStore(keychain);

      expect(
        (await store.save('u1', journalKey: key)).location,
        KeyLocation.thisDevice,
      );
      final StoredKey read = (await store.read('u1'))!;
      expect(read.journalKey.sameAs(key), isTrue);
      expect(read.location, KeyLocation.thisDevice);
      await expectLater(
        store.save('u1', journalKey: JournalKey.generate(Random(5))),
        throwsA(isA<KeyConflictException>()),
      );
    },
  );

  test('never writes synced after the synced lookup was refused', () async {
    final FakeKeychain keychain = FakeKeychain(refuseSyncedReads: true);
    keychain.items[(KeyStore.itemName('u1'), true)] = 'unseen';

    final StoredKey saved = await KeyStore(
      keychain,
    ).save('u1', journalKey: key);
    expect(saved.location, KeyLocation.thisDevice);
    expect(keychain.items[(KeyStore.itemName('u1'), true)], 'unseen');
  });

  test('keeps one key per uid', () async {
    final KeyStore store = KeyStore(FakeKeychain());
    final JournalKey other = JournalKey.generate(Random(3));
    await store.save('u1', journalKey: key);
    await store.save('u2', journalKey: other);

    expect((await store.read('u1'))!.journalKey.sameAs(key), isTrue);
    expect((await store.read('u2'))!.journalKey.sameAs(other), isTrue);
  });

  test('refuses to replace a journal key with a different one', () async {
    final KeyStore store = KeyStore(FakeKeychain());
    await store.save('u1', journalKey: key);

    await expectLater(
      store.save('u1', journalKey: JournalKey.generate(Random(4))),
      throwsA(isA<KeyConflictException>()),
    );
    expect((await store.read('u1'))!.journalKey.sameAs(key), isTrue);
  });

  test('adds a recovery key to a stored journal key and keeps it', () async {
    final KeyStore store = KeyStore(FakeKeychain());
    await store.save('u1', journalKey: key);
    await store.save('u1', journalKey: key, recoveryKey: recovery);
    await store.save('u1', journalKey: key);

    expect((await store.read('u1'))!.recoveryKey, recovery);
  });

  test('a key kept on this device stays there on a later save', () async {
    final FakeKeychain keychain = FakeKeychain(refuseSynced: true);
    final KeyStore store = KeyStore(keychain);
    await store.save('u1', journalKey: key);

    final StoredKey saved = await KeyStore(
      FakeKeychain()..items.addAll(keychain.items),
    ).save('u1', journalKey: key, recoveryKey: recovery);
    expect(saved.location, KeyLocation.thisDevice);
  });

  test('deletes both kinds of item', () async {
    final FakeKeychain keychain = FakeKeychain();
    final KeyStore store = KeyStore(keychain);
    await store.save('u1', journalKey: key);
    keychain.items[(KeyStore.itemName('u1'), false)] =
        keychain.items[(KeyStore.itemName('u1'), true)]!;

    await store.delete('u1');
    expect(keychain.items, isEmpty);
    expect(await store.read('u1'), isNull);
  });

  test('an unreadable item is a format error, not a silent miss', () async {
    final FakeKeychain keychain = FakeKeychain();
    keychain.items[(KeyStore.itemName('u1'), true)] = '{"v":9}';
    await expectLater(KeyStore(keychain).read('u1'), throwsFormatException);
  });
}
