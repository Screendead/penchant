import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

/// `keys/{uid}`: which key the journal is sealed with, a seal that proves a
/// candidate key is that one, and the key wrapped under the recovery key.
class KeysDoc {
  KeysDoc({
    required this.keyId,
    required this.check,
    required this.recoveryWrap,
  });

  final String keyId;
  final Uint8List check;
  final Uint8List recoveryWrap;
}

class KeysDocExists implements Exception {}

abstract class KeysRemote {
  /// From the server only: a cache miss must not read as "no key yet", or a
  /// second key gets minted beside the first.
  Future<KeysDoc?> fetchFromServer(String uid);

  /// Throws [KeysDocExists] when the rules refuse because one is there.
  Future<void> create(String uid, KeysDoc doc);

  Future<void> delete(String uid);
}

class FirestoreKeysRemote implements KeysRemote {
  FirestoreKeysRemote([FirebaseFirestore? firestore])
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _ref(String uid) =>
      _firestore.collection('keys').doc(uid);

  @override
  Future<KeysDoc?> fetchFromServer(String uid) async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await _ref(
      uid,
    ).get(const GetOptions(source: Source.server));
    final Map<String, dynamic>? data = snapshot.data();

    if (data == null) {
      return null;
    }

    return KeysDoc(
      keyId: data['keyId'] as String,
      check: (data['check'] as Blob).bytes,
      recoveryWrap: (data['recoveryWrap'] as Blob).bytes,
    );
  }

  @override
  Future<void> create(String uid, KeysDoc doc) async {
    try {
      // The rules allow no update that changes keyId, so set() over an
      // existing document is refused.
      await _ref(uid).set(<String, Object>{
        'keyId': doc.keyId,
        'check': Blob(doc.check),
        'recoveryWrap': Blob(doc.recoveryWrap),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied' &&
          await fetchFromServer(uid) != null) {
        throw KeysDocExists();
      }
      rethrow;
    }
  }

  @override
  Future<void> delete(String uid) => _ref(uid).delete();
}
