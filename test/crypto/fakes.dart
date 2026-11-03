import 'package:tracker/crypto/key_store.dart';
import 'package:tracker/crypto/keys_remote.dart';

class FakeKeyStore implements KeyStore {
  final Map<String, StoredKey> keys = <String, StoredKey>{};
  final Set<String> migrated = <String>{};

  @override
  Future<StoredKey?> read(String uid) async => keys[uid];

  @override
  Future<void> write(String uid, StoredKey key) async => keys[uid] = key;

  @override
  Future<void> wipe(String uid) async {
    keys.remove(uid);
    migrated.remove(uid);
  }

  @override
  Future<bool> isMigrated(String uid) async => migrated.contains(uid);

  @override
  Future<void> markMigrated(String uid) async => migrated.add(uid);
}

class Offline implements Exception {}

/// Behaves as the rules do: create-only, so a second create is refused.
class FakeKeysRemote implements KeysRemote {
  final Map<String, KeysDoc> docs = <String, KeysDoc>{};
  bool offline = false;
  int creates = 0;
  final List<String> log = <String>[];

  /// Simulates another device creating the doc between fetch and create.
  KeysDoc? raceWith;

  @override
  Future<KeysDoc?> fetchFromServer(String uid) async {
    if (offline) {
      throw Offline();
    }
    return docs[uid];
  }

  @override
  Future<void> create(String uid, KeysDoc doc) async {
    if (offline) {
      throw Offline();
    }
    creates++;
    if (raceWith != null) {
      docs[uid] = raceWith!;
      raceWith = null;
    }
    if (docs.containsKey(uid)) {
      throw KeysDocExists();
    }
    docs[uid] = doc;
    log.add('create keys');
  }

  @override
  Future<void> delete(String uid) async {
    docs.remove(uid);
    log.add('delete keys');
  }
}
