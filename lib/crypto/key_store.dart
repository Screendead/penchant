import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The journal key as this device holds it.
class StoredKey {
  StoredKey({required this.keyId, required this.dek, this.recoveryKey});

  final String keyId;
  final Uint8List dek;

  /// Formatted, so Settings can show it again.
  final String? recoveryKey;

  String toJson() => jsonEncode(<String, Object?>{
    'keyId': keyId,
    'dek': base64Url.encode(dek),
    'recoveryKey': recoveryKey,
  });

  static StoredKey fromJson(String json) {
    final Map<String, dynamic> map = jsonDecode(json) as Map<String, dynamic>;
    return StoredKey(
      keyId: map['keyId'] as String,
      dek: Uint8List.fromList(base64Url.decode(map['dek'] as String)),
      recoveryKey: map['recoveryKey'] as String?,
    );
  }
}

abstract class KeyStore {
  Future<StoredKey?> read(String uid);
  Future<void> write(String uid, StoredKey key);
  Future<void> wipe(String uid);
  Future<bool> isMigrated(String uid);
  Future<void> markMigrated(String uid);
}

/// Two keychain items per uid: `.sync` rides iCloud Keychain to the user's
/// other devices; `.local` stays on this device, so the key survives iCloud
/// Keychain being switched off (a manual check: it needs physical devices).
class SecureKeyStore implements KeyStore {
  SecureKeyStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  // A read must pass the same attributes the item was written with, or the
  // keychain query misses it.
  static const IOSOptions _syncIOS = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
    synchronizable: true,
  );
  static const MacOsOptions _syncMac = MacOsOptions(
    accessibility: KeychainAccessibility.first_unlock,
    synchronizable: true,
  );
  static const IOSOptions _localIOS = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );
  static const MacOsOptions _localMac = MacOsOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );

  static String syncItem(String uid) => 'tracker.journal.$uid.sync';
  static String localItem(String uid) => 'tracker.journal.$uid.local';
  static String migratedItem(String uid) => 'tracker.journal.$uid.migrated';

  Future<String?> _readSync(String uid) =>
      _storage.read(key: syncItem(uid), iOptions: _syncIOS, mOptions: _syncMac);

  Future<String?> _readLocal(String uid) => _storage.read(
    key: localItem(uid),
    iOptions: _localIOS,
    mOptions: _localMac,
  );

  @override
  Future<StoredKey?> read(String uid) async {
    final String? synced = await _readSync(uid);
    final String? local = await _readLocal(uid);
    final String? found = synced ?? local;

    if (found == null) {
      return null;
    }

    final StoredKey key = StoredKey.fromJson(found);
    if (synced == null || local == null) {
      await write(uid, key);
    }
    return key;
  }

  @override
  Future<void> write(String uid, StoredKey key) async {
    final String json = key.toJson();
    await _storage.write(
      key: syncItem(uid),
      value: json,
      iOptions: _syncIOS,
      mOptions: _syncMac,
    );
    await _storage.write(
      key: localItem(uid),
      value: json,
      iOptions: _localIOS,
      mOptions: _localMac,
    );
  }

  @override
  Future<void> wipe(String uid) async {
    await _storage.delete(
      key: syncItem(uid),
      iOptions: _syncIOS,
      mOptions: _syncMac,
    );
    await _storage.delete(
      key: localItem(uid),
      iOptions: _localIOS,
      mOptions: _localMac,
    );
    await _storage.delete(
      key: migratedItem(uid),
      iOptions: _localIOS,
      mOptions: _localMac,
    );
  }

  @override
  Future<bool> isMigrated(String uid) async =>
      await _storage.read(
        key: migratedItem(uid),
        iOptions: _localIOS,
        mOptions: _localMac,
      ) !=
      null;

  @override
  Future<void> markMigrated(String uid) => _storage.write(
    key: migratedItem(uid),
    value: '1',
    iOptions: _localIOS,
    mOptions: _localMac,
  );
}
