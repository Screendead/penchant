import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/crypto/sealer.dart';

/// Where the migrator reads the user's documents and writes their sealed
/// form. [FirestoreMigrationSource] in the app; a map in tests.
abstract interface class MigrationSource {
  /// Up to [limit] of [uid]'s documents in [collection], in document id
  /// order, after the one with id [after]. From the server, so that offline
  /// it fails rather than answer from a partial cache.
  Future<List<StoredDocument>> page(
    String collection,
    String uid, {
    String? after,
    required int limit,
  });

  /// Applies every update in one batch.
  Future<void> commit(
    String collection,
    Map<String, Map<String, Object>> updates,
  );
}

class FirestoreMigrationSource implements MigrationSource {
  FirestoreMigrationSource(this._firestore);

  final FirebaseFirestore _firestore;

  // Equality on ownerID ordered by document id is served by the automatic
  // single-field index, as Account._readOwned is.
  @override
  Future<List<StoredDocument>> page(
    String collection,
    String uid, {
    String? after,
    required int limit,
  }) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection(collection)
        .where('ownerID', isEqualTo: uid)
        .orderBy(FieldPath.documentId)
        .limit(limit);
    if (after != null) {
      query = query.startAfter(<Object>[after]);
    }
    final QuerySnapshot<Map<String, dynamic>> snapshot = await query.get(
      const GetOptions(source: Source.server),
    );
    return <StoredDocument>[
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs)
        (id: doc.id, data: doc.data()),
    ];
  }

  @override
  Future<void> commit(
    String collection,
    Map<String, Map<String, Object>> updates,
  ) {
    final WriteBatch batch = _firestore.batch();
    for (final MapEntry<String, Map<String, Object>>(:key, :value)
        in updates.entries) {
      batch.update(_firestore.collection(collection).doc(key), value);
    }
    return batch.commit();
  }
}

/// Rewrites each of a user's plaintext documents as sealed, deleting the
/// plaintext in the same update. A document that already has [sealedField]
/// is left alone, so a run cut short is finished by the next one and a
/// second run writes nothing; the parsers read either shape meanwhile.
class PlaintextMigrator {
  PlaintextMigrator({required this.source, required this.sealer});

  final MigrationSource source;
  final Sealer sealer;

  /// Firestore's limit on writes in one batch, as Account.deleteAccount uses.
  static const int pageSize = Account.pageSize;

  /// The update that seals [data], or null when there is nothing to seal.
  Future<Map<String, Object>?> update(
    String collection,
    String docId,
    Map<String, dynamic> data,
  ) async {
    final List<String> fields = plaintextFields[collection]!;
    if (data.containsKey(sealedField) ||
        !fields.any((String field) => data.containsKey(field))) {
      return null;
    }
    final Object? viceID = data['viceID'];
    return <String, Object>{
      sealedField: Blob(
        await sealer.seal(
          collection: collection,
          docId: docId,
          ownerID: data['ownerID'] as String,
          viceID: viceID is String ? viceID : null,
          fields: <String, Object?>{
            for (final String field in fields)
              if (data.containsKey(field)) field: data[field],
          },
        ),
      ),
      for (final String field in fields)
        if (data.containsKey(field)) field: FieldValue.delete(),
    };
  }

  /// Seals every plaintext document [uid] owns and returns how many it
  /// sealed. [onProgress] hears the running total after each batch.
  Future<int> run(String uid, {void Function(int sealed)? onProgress}) async {
    int sealed = 0;
    for (final String collection in plaintextFields.keys) {
      String? after;
      while (true) {
        final List<StoredDocument> docs = await source.page(
          collection,
          uid,
          after: after,
          limit: pageSize,
        );
        final Map<String, Map<String, Object>> updates =
            <String, Map<String, Object>>{};
        for (final StoredDocument doc in docs) {
          final Map<String, Object>? change = await update(
            collection,
            doc.id,
            doc.data,
          );
          if (change != null) {
            updates[doc.id] = change;
          }
        }
        if (updates.isNotEmpty) {
          await source.commit(collection, updates);
          sealed += updates.length;
          onProgress?.call(sealed);
        }
        if (docs.length < pageSize) {
          break;
        }
        after = docs.last.id;
      }
    }
    return sealed;
  }
}
