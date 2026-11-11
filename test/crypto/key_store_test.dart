import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/crypto/journal_key.dart';
import 'package:tracker/crypto/key_store.dart';
import 'package:tracker/crypto/recovery_key.dart';

/// A keychain that keeps synced and this-device items apart, as the real one
/// does, and can refuse synced items like a build without the entitlement.
class FakeKeychain extends Fake implements FlutterSecureStorage {
  FakeKeychain({
    this.refuseSynced = false,
    this.refuseSyncedReads = false,
    this.before,
  });

  /// Runs before each call, with 'read', 'write' or 'delete' and whether it
  /// names the synced item; a test throws from it or changes [items].
  final void Function(String call, bool synced)? before;

  final bool refuseSynced;

  /// The real keychain, refusing synced items, refuses the synced lookup too.
  final bool refuseSyncedReads;
  final Map<(String, bool), String> items = <(String, bool), String>{};

  static bool _synced(AppleOptions? i, AppleOptions? m) {
    expect(i?.synchronizable, m?.synchronizable, reason: 'iOS and macOS agree');
    return i?.synchronizable ?? false;
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final bool synced = _synced(iOptions, mOptions);
    before?.call('read', synced);
    if (synced && refuseSyncedReads) {
      throw PlatformException(
        code: '-34018',
        message: 'errSecMissingEntitlement',
      );
    }
    return items[(key, synced)];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final bool synced = _synced(iOptions, mOptions);
    before?.call('write', synced);
    if (synced && refuseSynced) {
      throw PlatformException(
        code: '-34018',
        message: 'errSecMissingEntitlement',
      );
    }
    items[(key, synced)] = value!;
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    before?.call('delete', _synced(iOptions, mOptions));
    // The plugin deletes the synced and the this-device item of a name
    // together, whichever the options name.
    items
      ..remove((key, true))
      ..remove((key, false));
  }
}

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

  group('promoting a this-device key', () {
    final (String, bool) localItem = (KeyStore.itemName('u1'), false);
    final (String, bool) syncedItem = (KeyStore.itemName('u1'), true);

    Future<String> localOnly(FakeKeychain keychain) async {
      final FakeKeychain refusing = FakeKeychain(refuseSynced: true);
      await KeyStore(
        refusing,
      ).save('u1', journalKey: key, recoveryKey: recovery);
      return keychain.items[localItem] = refusing.items[localItem]!;
    }

    PlatformException refusal() => PlatformException(
      code: 'Unexpected security result code',
      message: 'errSecMissingEntitlement',
      details: -34018,
    );

    test('copies it to a synced item, read back as the same key', () async {
      final FakeKeychain keychain = FakeKeychain();
      final String local = await localOnly(keychain);
      final KeyStore store = KeyStore(keychain);
      expect((await store.read('u1'))!.location, KeyLocation.thisDevice);

      final StoredKey promoted = (await store.promote('u1'))!;
      expect(promoted.location, KeyLocation.synced);
      expect(promoted.syncRefusal, isNull);
      expect(promoted.journalKey.sameAs(key), isTrue);
      expect(promoted.recoveryKey, recovery);
      expect(keychain.items[localItem], local);

      final StoredKey read = (await store.read('u1'))!;
      expect(read.location, KeyLocation.synced);
      expect(read.journalKey.sameAs(key), isTrue);
    });

    test('leaves a synced key and a missing key alone', () async {
      final FakeKeychain keychain = FakeKeychain();
      final KeyStore store = KeyStore(keychain);
      expect(await store.promote('u1'), isNull);
      expect(keychain.items, isEmpty);

      await store.save('u1', journalKey: key);
      final Map<(String, bool), String> before = <(String, bool), String>{
        ...keychain.items,
      };
      expect((await store.promote('u1'))!.location, KeyLocation.synced);
      expect(keychain.items, before);
    });

    // Each failure order: the synced lookup, the synced write, the read
    // back (refused, empty, another key, unreadable), and the plugin
    // dropping every item of the name on a failed write.
    final Map<String, void Function(FakeKeychain, int syncedReads, String call)>
    failures = <String, void Function(FakeKeychain, int syncedReads, String call)>{
      'the synced lookup is refused': (k, reads, call) {
        if (call == 'read' && reads == 1) throw refusal();
      },
      'the synced write is refused': (k, reads, call) {
        if (call == 'write') throw refusal();
      },
      'the read back is refused': (k, reads, call) {
        if (call == 'read' && reads == 2) throw refusal();
      },
      'the read back finds nothing': (k, reads, call) {
        if (call == 'read' && reads == 2) k.items.remove(syncedItem);
      },
      'the read back finds another key': (k, reads, call) {
        if (call == 'read' && reads == 2) {
          k.items[syncedItem] =
              '{"v":1,"key":"${base64.encode(JournalKey.generate(Random(9)).bytes)}",'
              '"recovery":null}';
        }
      },
      'the read back is unreadable': (k, reads, call) {
        if (call == 'read' && reads == 2) k.items[syncedItem] = '{"v":9}';
      },
      'the refused write drops every item of the name': (k, reads, call) {
        if (call == 'write') {
          k.items.clear();
          throw refusal();
        }
      },
    };

    for (final MapEntry<
          String,
          void Function(FakeKeychain, int syncedReads, String call)
        >
        failure
        in failures.entries) {
      test('keeps the this-device key when ${failure.key}', () async {
        int syncedReads = 0;
        int syncedWrites = 0;
        late final FakeKeychain keychain;
        keychain = FakeKeychain(
          before: (String call, bool synced) {
            if (!synced) return;
            if (call == 'read') syncedReads++;
            if (call == 'write') syncedWrites++;
            failure.value(keychain, syncedReads, call);
          },
        );
        final String local = await localOnly(keychain);
        final KeyStore store = KeyStore(keychain);

        final StoredKey kept = (await store.promote('u1'))!;
        expect(kept.location, KeyLocation.thisDevice);
        expect(kept.journalKey.sameAs(key), isTrue);
        expect(kept.recoveryKey, recovery);
        expect(kept.syncRefusal, isNotNull);
        expect(keychain.items[localItem], local);

        // No second attempt this launch, whatever the synced item now holds.
        final int writes = syncedWrites;
        try {
          await store.promote('u1');
        } on FormatException {
          // The unreadable synced item, as on any read.
        }
        expect(syncedWrites, writes);
        expect(keychain.items[localItem], local);
      });
    }

    test('reports the keychain status of the refusal, and nothing else of '
        'it', () async {
      final FakeKeychain keychain = FakeKeychain(
        before: (String call, bool synced) {
          if (synced && call == 'write') throw refusal();
        },
      );
      await localOnly(keychain);
      final KeyStore store = KeyStore(keychain);

      expect((await store.promote('u1'))!.syncRefusal!.status, -34018);
      expect((await store.read('u1'))!.syncRefusal!.status, -34018);
    });
  });

  test('a first key kept on this device says the keychain refused', () async {
    final StoredKey writeRefused = await KeyStore(
      FakeKeychain(refuseSynced: true),
    ).save('u1', journalKey: key);
    expect(writeRefused.syncRefusal!.status, -34018);

    final KeyStore store = KeyStore(
      FakeKeychain(refuseSynced: true, refuseSyncedReads: true),
    );
    expect(
      (await store.save('u1', journalKey: key)).syncRefusal!.status,
      -34018,
    );
    expect((await store.read('u1'))!.syncRefusal!.status, -34018);
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
