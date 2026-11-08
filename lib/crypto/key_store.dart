import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tracker/crypto/journal_key.dart';

enum KeyLocation {
  /// iCloud Keychain carries it to the user's other Apple devices.
  synced,

  /// The keychain refused a synced item, so this device alone holds it.
  thisDevice,
}

class StoredKey {
  StoredKey({
    required this.journalKey,
    this.recoveryKey,
    required this.location,
  });

  final JournalKey journalKey;

  /// Kept so Settings can show it again; null until one has been made.
  final Uint8List? recoveryKey;

  final KeyLocation location;
}

/// Saving a journal key over a different one would orphan everything sealed
/// under the first.
class KeyConflictException implements Exception {
  KeyConflictException(this.uid);

  final String uid;

  @override
  String toString() =>
      'KeyConflictException: a different journal key is stored for $uid';
}

/// One keychain item per uid, written synchronizable so iCloud Keychain
/// syncs it; where the keychain refuses that, a this-device-only item.
class KeyStore {
  KeyStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  // A read, write or delete must pass the attributes the item was written
  // with, or the keychain query misses it. Synced items cannot use a
  // this-device-only accessibility.
  static const IOSOptions _syncedIOS = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
    synchronizable: true,
  );
  static const MacOsOptions _syncedMac = MacOsOptions(
    accessibility: KeychainAccessibility.first_unlock,
    synchronizable: true,
  );
  static const IOSOptions _localIOS = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );
  static const MacOsOptions _localMac = MacOsOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );

  static String itemName(String uid) => 'penchant.journal-key.$uid';

  static const int _formatVersion = 1;

  Future<StoredKey?> read(String uid) async => (await _read(uid)).stored;

  // A keychain that refuses synced items refuses the synced lookup too
  // (errSecMissingEntitlement), so that refusal must not hide the
  // this-device item behind it.
  Future<({StoredKey? stored, bool syncedRefused})> _read(String uid) async {
    bool syncedRefused = false;
    try {
      final String? synced = await _storage.read(
        key: itemName(uid),
        iOptions: _syncedIOS,
        mOptions: _syncedMac,
      );
      if (synced != null) {
        return (
          stored: _decode(synced, KeyLocation.synced),
          syncedRefused: false,
        );
      }
    } on PlatformException {
      syncedRefused = true;
    }

    final String? local = await _storage.read(
      key: itemName(uid),
      iOptions: _localIOS,
      mOptions: _localMac,
    );
    return (
      stored: local == null ? null : _decode(local, KeyLocation.thisDevice),
      syncedRefused: syncedRefused,
    );
  }

  /// Stores [journalKey] for [uid], with [recoveryKey] when given, and says
  /// where it landed. Throws [KeyConflictException] if a different journal
  /// key is already stored; deleting it first is the caller's explicit act.
  Future<StoredKey> save(
    String uid, {
    required JournalKey journalKey,
    Uint8List? recoveryKey,
  }) async {
    final (:StoredKey? stored, :bool syncedRefused) = await _read(uid);
    final StoredKey? existing = stored;
    if (existing != null && !existing.journalKey.sameAs(journalKey)) {
      throw KeyConflictException(uid);
    }

    final String value = jsonEncode(<String, Object?>{
      'v': _formatVersion,
      'key': base64.encode(journalKey.bytes),
      'recovery': switch (recoveryKey ?? existing?.recoveryKey) {
        final Uint8List r => base64.encode(r),
        null => null,
      },
    });

    // Writing synced after a refused synced lookup could replace a synced
    // item that lookup failed to see.
    if (!syncedRefused && existing?.location != KeyLocation.thisDevice) {
      try {
        await _storage.write(
          key: itemName(uid),
          value: value,
          iOptions: _syncedIOS,
          mOptions: _syncedMac,
        );
        return _decode(value, KeyLocation.synced);
      } on PlatformException {
        // Falls through to a this-device item, which needs no iCloud
        // Keychain support from the signing team or the account.
      }
    }

    await _storage.write(
      key: itemName(uid),
      value: value,
      iOptions: _localIOS,
      mOptions: _localMac,
    );
    return _decode(value, KeyLocation.thisDevice);
  }

  /// Deleting the synced item deletes it from every device on the Apple ID.
  Future<void> delete(String uid) async {
    await _storage.delete(
      key: itemName(uid),
      iOptions: _syncedIOS,
      mOptions: _syncedMac,
    );
    await _storage.delete(
      key: itemName(uid),
      iOptions: _localIOS,
      mOptions: _localMac,
    );
  }

  static StoredKey _decode(String value, KeyLocation location) {
    final Object? map = jsonDecode(value);
    if (map is! Map<String, dynamic> ||
        map['v'] != _formatVersion ||
        map['key'] is! String) {
      throw const FormatException('Unreadable journal key item');
    }

    final Object? recovery = map['recovery'];
    return StoredKey(
      journalKey: JournalKey(base64.decode(map['key'] as String)),
      recoveryKey: recovery is String ? base64.decode(recovery) : null,
      location: location,
    );
  }
}
