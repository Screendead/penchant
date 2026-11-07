import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter/foundation.dart';
import 'package:tracker/crypto/journal_field_sealer.dart';
import 'package:tracker/crypto/journal_key.dart';
import 'package:tracker/crypto/key_store.dart';
import 'package:tracker/crypto/recovery_key.dart';
import 'package:tracker/crypto/sealer.dart';
import 'package:tracker/data/sealed.dart';

/// What the server holds about a user's journal key, in `keys/{uid}`: an id
/// to compare keys by, and the key wrapped under the recovery key, which only
/// the recovery key opens. Never the key itself.
@immutable
class KeyRecord {
  const KeyRecord({
    required this.keyID,
    required this.wrapped,
    required this.createdAt,
    this.saved = false,
    this.cardDismissed = false,
  });

  final String keyID;
  final Uint8List wrapped;
  final DateTime createdAt;

  /// The user typed back the recovery key's last group, on any device.
  final bool saved;
  final bool cardDismissed;
}

/// Not secret: SHA-256 is one-way, and the key has 256 random bits.
String keyIDOf(JournalKey key) {
  final List<int> digest = const DartSha256().hashSync(<int>[
    ...utf8.encode('penchant:v1:journal-key-id:'),
    ...key.bytes,
  ]).bytes;
  return base64Url.encode(digest.sublist(0, 16));
}

abstract interface class KeyDirectory {
  /// From the server, never the cache: a cached miss would make a second key.
  Future<KeyRecord?> fetch(String uid);

  /// Stores [record] unless one is already there, and returns the stored one.
  Future<KeyRecord> createIfAbsent(String uid, KeyRecord record);

  Future<void> replace(String uid, KeyRecord record);

  Future<void> setFlags(String uid, {bool? saved, bool? cardDismissed});
}

class FirestoreKeyDirectory implements KeyDirectory {
  FirestoreKeyDirectory(this._firestore);

  final FirebaseFirestore _firestore;

  static const String collection = 'keys';

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _firestore.collection(collection).doc(uid);

  @override
  Future<KeyRecord?> fetch(String uid) async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await _doc(
      uid,
    ).get(const GetOptions(source: Source.server));
    return _parse(snapshot.data());
  }

  // In a transaction, so two devices making a first key at once keep one.
  @override
  Future<KeyRecord> createIfAbsent(String uid, KeyRecord record) =>
      _firestore.runTransaction((Transaction tx) async {
        final DocumentSnapshot<Map<String, dynamic>> snapshot = await tx.get(
          _doc(uid),
        );
        final KeyRecord? existing = _parse(snapshot.data());
        if (existing != null) {
          return existing;
        }
        tx.set(_doc(uid), _encode(record));
        return record;
      });

  @override
  Future<void> replace(String uid, KeyRecord record) =>
      _doc(uid).set(_encode(record));

  @override
  Future<void> setFlags(String uid, {bool? saved, bool? cardDismissed}) => _doc(
    uid,
  ).update(<String, Object>{'saved': ?saved, 'cardDismissed': ?cardDismissed});

  static Map<String, Object> _encode(KeyRecord record) => <String, Object>{
    'keyID': record.keyID,
    'wrapped': Blob(record.wrapped),
    'createdAt': Timestamp.fromDate(record.createdAt),
    'saved': record.saved,
    'cardDismissed': record.cardDismissed,
  };

  static KeyRecord? _parse(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }
    final Object? keyID = data['keyID'];
    final Object? wrapped = data['wrapped'];
    final Object? createdAt = data['createdAt'];
    if (keyID is! String || wrapped is! Blob || createdAt is! Timestamp) {
      throw const FormatException('Unreadable keys document');
    }
    return KeyRecord(
      keyID: keyID,
      wrapped: wrapped.bytes,
      createdAt: createdAt.toDate(),
      saved: data['saved'] == true,
      cardDismissed: data['cardDismissed'] == true,
    );
  }
}

sealed class JournalKeyState {
  const JournalKeyState();
}

/// This device holds the journal key. [record] is null while the server has
/// not answered, so the key is used but not yet checked against it.
class KeyReady extends JournalKeyState {
  KeyReady(this.stored, this.record, AesGcm aes256)
    : sealer = JournalFieldSealer(stored.journalKey.sealer(aes256));

  final StoredKey stored;
  final KeyRecord? record;
  final FieldSealer sealer;
}

/// The server holds a key this device lacks, or another one than it holds.
class KeyNeedsRecovery extends JournalKeyState {
  const KeyNeedsRecovery(this.record);

  final KeyRecord record;
}

/// No key on this device and no answer from the server, so whether one
/// exists is unknown. Writes stay plaintext; the migrator seals them later.
class KeyUnknown extends JournalKeyState {
  const KeyUnknown();
}

/// Makes, finds and replaces the signed-in user's journal key. The key lives
/// in the keychain (synced through iCloud Keychain where it can be), the
/// server holds only [KeyRecord], and the recovery key is the backup.
class KeyService {
  KeyService({
    required this.store,
    required this.directory,
    required this.aes128,
    required this.aes256,
    DateTime Function()? now,
    this.serverWait = const Duration(seconds: 10),
  }) : _now = now ?? DateTime.now;

  final KeyStore store;
  final KeyDirectory directory;
  final AesGcm aes128;
  final AesGcm aes256;
  final DateTime Function() _now;
  final Duration serverWait;

  /// The key on this device first, so sealing never waits on the network,
  /// then what the server says about it.
  Stream<JournalKeyState> resolve(String uid) async* {
    final StoredKey? stored = await store.read(uid);
    if (stored != null) {
      yield KeyReady(stored, null, aes256);
    }

    final KeyRecord? record;
    try {
      record = await directory.fetch(uid).timeout(serverWait);
    } on TimeoutException {
      if (stored == null) yield const KeyUnknown();
      return;
    } on FirebaseException catch (e) {
      // Denied: the user signed out while the read was on its way, and this
      // provider is being thrown away.
      if (e.code != 'unavailable' && e.code != 'permission-denied') rethrow;
      if (stored == null) yield const KeyUnknown();
      return;
    }

    if (record != null) {
      yield _against(stored, record);
      return;
    }
    yield await _publish(uid, stored);
  }

  JournalKeyState _against(StoredKey? stored, KeyRecord record) =>
      stored != null && keyIDOf(stored.journalKey) == record.keyID
      ? KeyReady(stored, record, aes256)
      : KeyNeedsRecovery(record);

  // The keychain is written before the server, so a key the server names is
  // always on some device; a key saved here whose record never landed is
  // published on the next launch.
  Future<JournalKeyState> _publish(String uid, StoredKey? stored) async {
    StoredKey local =
        stored ??
        await store.save(
          uid,
          journalKey: JournalKey.generate(),
          recoveryKey: RecoveryKey.generate(),
        );
    if (local.recoveryKey == null) {
      local = await store.save(
        uid,
        journalKey: local.journalKey,
        recoveryKey: RecoveryKey.generate(),
      );
    }
    final KeyRecord mine = await _recordFor(uid, local);
    final KeyRecord kept = await directory.createIfAbsent(uid, mine);
    return _against(local, kept);
  }

  Future<KeyRecord> _recordFor(String uid, StoredKey stored) async => KeyRecord(
    keyID: keyIDOf(stored.journalKey),
    wrapped: await stored.journalKey.wrap(
      aes128: aes128,
      recoveryKey: stored.recoveryKey!,
      uid: uid,
    ),
    createdAt: _now(),
  );

  /// Opens [record]'s wrapped key with [recoveryKey] and keeps it on this
  /// device, replacing any other key stored here for [uid].
  Future<bool> unlock(
    String uid,
    KeyRecord record,
    Uint8List recoveryKey,
  ) async {
    final JournalKey key;
    try {
      key = await JournalKey.unwrap(
        record.wrapped,
        aes128: aes128,
        recoveryKey: recoveryKey,
        uid: uid,
      );
    } on SealException catch (e) {
      if (e.failure == SealFailure.notAuthentic) {
        return false;
      }
      rethrow;
    }
    final StoredKey? here = await store.read(uid);
    if (here != null && !here.journalKey.sameAs(key)) {
      await store.delete(uid);
    }
    await store.save(uid, journalKey: key, recoveryKey: recoveryKey);
    return true;
  }

  /// A new key and recovery key, on every device through iCloud Keychain and
  /// on the server. Whatever the old key sealed stays sealed under it.
  Future<void> startNewJournal(String uid) async {
    await store.delete(uid);
    final StoredKey stored = await store.save(
      uid,
      journalKey: JournalKey.generate(),
      recoveryKey: RecoveryKey.generate(),
    );
    await directory.replace(uid, await _recordFor(uid, stored));
  }
}
