import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:tracker/crypto/journal_cipher.dart';
import 'package:tracker/crypto/key_store.dart';
import 'package:tracker/crypto/keys_remote.dart';
import 'package:tracker/crypto/recovery_key.dart';

sealed class JournalKeyState {
  const JournalKeyState();
}

/// No key anywhere and none on the server: this is a new journal.
class KeyNeedsSetup extends JournalKeyState {
  const KeyNeedsSetup();
}

/// The server has a key this device does not: ask for the recovery key.
class KeyNeedsUnlock extends JournalKeyState {
  const KeyNeedsUnlock();
}

class KeyReady extends JournalKeyState {
  const KeyReady({required this.cipher, required this.stored});

  final JournalCipher cipher;
  final StoredKey stored;
}

class KeyError extends JournalKeyState {
  const KeyError(this.message);

  final String message;
}

sealed class UnlockResult {
  const UnlockResult();
}

class Unlocked extends UnlockResult {
  const Unlocked(this.state);

  final KeyReady state;
}

class UnlockRejected extends UnlockResult {
  const UnlockRejected(this.parse);

  /// Why the text is not a recovery key; null when it is one, but for
  /// another journal.
  final RecoveryKeyParse? parse;
}

class KeyServiceRefused implements Exception {
  KeyServiceRefused(this.message);

  final String message;

  @override
  String toString() => 'KeyServiceRefused: $message';
}

/// The one rule that matters: never mint a key while `keys/{uid}` exists on
/// the server. A second key beside ciphertext under the first loses the
/// journal silently.
class KeyService {
  KeyService({
    required this.store,
    required this.remote,
    required this.aes256,
    required this.aes128,
    Random? random,
  }) : _random = random ?? Random.secure();

  final KeyStore store;
  final KeysRemote remote;
  final AesGcm aes256;
  final AesGcm aes128;
  final Random _random;

  static const String _checkText = 'tracker-journal-key-check';

  static List<int> _aad(String uid, String keyId, String purpose) =>
      utf8.encode('tracker:v1:keys:$uid:$keyId:$purpose');

  Uint8List _randomBytes(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => _random.nextInt(256)));

  KeyReady _ready(StoredKey stored) => KeyReady(
    cipher: JournalCipher(aes: aes256, key: SecretKey(stored.dek)),
    stored: stored,
  );

  static Uint8List _join(SecretBox box) =>
      Uint8List.fromList(<int>[...box.nonce, ...box.cipherText, ...box.mac.bytes]);

  static SecretBox _split(Uint8List bytes) => SecretBox(
    bytes.sublist(12, bytes.length - 16),
    nonce: bytes.sublist(0, 12),
    mac: Mac(bytes.sublist(bytes.length - 16)),
  );

  Future<bool> _opensCheck(String uid, KeysDoc doc, Uint8List dek) async {
    try {
      final List<int> text = await aes256.decrypt(
        _split(doc.check),
        secretKey: SecretKey(dek),
        aad: _aad(uid, doc.keyId, 'check'),
      );
      return utf8.decode(text) == _checkText;
    } on SecretBoxAuthenticationError {
      return false;
    }
  }

  Future<JournalKeyState> resolve(String uid) async {
    final StoredKey? local = await store.read(uid);
    KeysDoc? server;

    try {
      server = await remote.fetchFromServer(uid);
    } catch (_) {
      if (local != null) {
        return _ready(local);
      }
      return const KeyError(
        "Can't reach the server to check for your journal key. "
        'Nothing has been changed; try again when you are online.',
      );
    }

    if (local == null) {
      return server == null ? const KeyNeedsSetup() : const KeyNeedsUnlock();
    }

    if (server == null) {
      // This device holds the only copy, so it is put back rather than
      // replaced.
      await _register(uid, local);
      return _ready(local);
    }

    if (server.keyId != local.keyId ||
        !await _opensCheck(uid, server, local.dek)) {
      return const KeyNeedsUnlock();
    }

    return _ready(local);
  }

  Future<void> _register(String uid, StoredKey local) async {
    final String? formatted = local.recoveryKey;
    final RecoveryKeyParse? parsed = formatted == null
        ? null
        : RecoveryKey.parse(formatted);

    if (parsed is! RecoveryKeyOk) {
      throw KeyServiceRefused('The local key has no recovery key to re-register');
    }

    await remote.create(uid, await _keysDoc(uid, local, parsed.key));
  }

  Future<KeysDoc> _keysDoc(String uid, StoredKey key, Uint8List recovery) async {
    final SecretBox check = await aes256.encrypt(
      utf8.encode(_checkText),
      secretKey: SecretKey(key.dek),
      aad: _aad(uid, key.keyId, 'check'),
    );
    final SecretBox wrap = await aes128.encrypt(
      key.dek,
      secretKey: SecretKey(recovery),
      aad: _aad(uid, key.keyId, 'recovery'),
    );
    return KeysDoc(
      keyId: key.keyId,
      check: _join(check),
      recoveryWrap: _join(wrap),
    );
  }

  /// Mints the journal key. Refuses unless the server confirms there is no
  /// `keys/{uid}` and this device holds no key.
  Future<KeyReady> setUp(String uid) async {
    if (await store.read(uid) != null) {
      throw KeyServiceRefused('This device already holds a journal key');
    }

    // Throws when offline: no answer is not "no key".
    if (await remote.fetchFromServer(uid) != null) {
      throw KeyServiceRefused('The server already has a journal key');
    }

    final Uint8List recovery = RecoveryKey.generate(_random);
    final StoredKey key = StoredKey(
      keyId: base64Url.encode(_randomBytes(8)).replaceAll('=', ''),
      dek: _randomBytes(32),
      recoveryKey: RecoveryKey.format(recovery),
    );

    // Kept before the server knows it, so a failed create can be retried
    // from this copy by resolve() instead of losing the only key.
    await store.write(uid, key);

    try {
      await remote.create(uid, await _keysDoc(uid, key, recovery));
    } on KeysDocExists {
      await store.wipe(uid);
      throw KeyServiceRefused('Another device created the journal key first');
    }

    return _ready(key);
  }

  Future<UnlockResult> unlock(String uid, String input) async {
    final RecoveryKeyParse parsed = RecoveryKey.parse(input);

    if (parsed is! RecoveryKeyOk) {
      return UnlockRejected(parsed);
    }

    final KeysDoc? server = await remote.fetchFromServer(uid);

    if (server == null) {
      throw KeyServiceRefused('There is no journal key to unlock');
    }

    final List<int> dek;
    try {
      dek = await aes128.decrypt(
        _split(server.recoveryWrap),
        secretKey: SecretKey(parsed.key),
        aad: _aad(uid, server.keyId, 'recovery'),
      );
    } on SecretBoxAuthenticationError {
      return const UnlockRejected(null);
    }

    final StoredKey key = StoredKey(
      keyId: server.keyId,
      dek: Uint8List.fromList(dek),
      recoveryKey: RecoveryKey.format(parsed.key),
    );

    if (!await _opensCheck(uid, server, key.dek)) {
      return const UnlockRejected(null);
    }

    await store.write(uid, key);
    return Unlocked(_ready(key));
  }

  /// The only path that retires a key: the journal's documents go first, so
  /// no ciphertext outlives the key that opens it.
  Future<KeyReady> startOver(
    String uid, {
    required Future<void> Function() deleteJournal,
  }) async {
    await deleteJournal();
    await remote.delete(uid);
    await store.wipe(uid);
    return setUp(uid);
  }
}
