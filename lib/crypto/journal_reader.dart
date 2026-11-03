import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/crypto/journal_cipher.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';

/// Decrypted fields by `collection/docId|blob`. Every snapshot re-delivers
/// every document, so without it each change re-decrypts the whole list.
/// Unbounded: a spike, sized by one user's journal.
typedef DecryptMemo = Map<String, Map<String, dynamic>>;

final decryptMemoProvider = Provider<DecryptMemo>(
  (ref) => <String, Map<String, dynamic>>{},
);

/// Null for a plaintext document, and for a sealed one that did not open
/// (the parsers tell the two apart by `enc`).
Future<Map<String, dynamic>?> openSealed({
  required JournalCipher cipher,
  required DecryptMemo memo,
  required String collection,
  required String docId,
  required Map<String, dynamic> json,
}) async {
  final Object? enc = json['enc'];

  if (enc is! Blob) {
    return null;
  }

  final String memoKey = '$collection/$docId|${base64.encode(enc.bytes)}';
  final Map<String, dynamic>? cached = memo[memoKey];

  if (cached != null) {
    return cached;
  }

  try {
    final Map<String, dynamic> opened = await cipher.open(
      collection: collection,
      docId: docId,
      ownerID: json['ownerID'] as String,
      viceID: collection == 'activities' ? json['viceID'] as String : null,
      blob: enc.bytes,
    );
    memo[memoKey] = opened;
    return opened;
  } catch (e) {
    // The document path only: a decrypted field must never reach a log.
    debugPrint('Unreadable $collection/$docId: ${e.runtimeType}');
    return null;
  }
}

Future<List<Vice>> openVices(
  QuerySnapshot<Map<String, dynamic>> snapshot,
  JournalCipher cipher,
  DecryptMemo memo,
) => Future.wait(
  snapshot.docs.map((QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final Map<String, dynamic> json = doc.data();
    return Vice.fromJson(
      id: doc.id,
      json: json,
      opened: await openSealed(
        cipher: cipher,
        memo: memo,
        collection: 'vices',
        docId: doc.id,
        json: json,
      ),
    );
  }),
);

Future<List<ViceActivity>> openActivities(
  QuerySnapshot<Map<String, dynamic>> snapshot,
  JournalCipher cipher,
  DecryptMemo memo,
) => Future.wait(
  snapshot.docs.map((QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final Map<String, dynamic> json = doc.data();
    return ViceActivity.fromJson(
      id: doc.id,
      json: json,
      opened: await openSealed(
        cipher: cipher,
        memo: memo,
        collection: 'activities',
        docId: doc.id,
        json: json,
      ),
    );
  }),
);

/// What add_vice.dart writes.
Future<Map<String, Object>> sealedVice({
  required JournalCipher cipher,
  required String docId,
  required String ownerID,
  required String name,
  required String unit,
}) async => <String, Object>{
  'enc': Blob(
    await cipher.seal(
      collection: 'vices',
      docId: docId,
      ownerID: ownerID,
      fields: <String, Object?>{'n': name, 'u': unit},
    ),
  ),
  'ownerID': ownerID,
  'createdAt': FieldValue.serverTimestamp(),
  'archived': false,
};

Future<Blob> sealQuantity({
  required JournalCipher cipher,
  required String docId,
  required String ownerID,
  required String viceID,
  required int quantity,
}) async => Blob(
  await cipher.seal(
    collection: 'activities',
    docId: docId,
    ownerID: ownerID,
    viceID: viceID,
    fields: <String, Object?>{'q': quantity},
  ),
);
