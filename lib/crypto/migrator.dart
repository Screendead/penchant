import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tracker/crypto/journal_cipher.dart';
import 'package:tracker/crypto/key_store.dart';

class MigrationReport {
  MigrationReport({this.skipped = false, this.vices = 0, this.activities = 0});

  final bool skipped;
  final int vices;
  final int activities;

  @override
  String toString() => skipped
      ? 'migration skipped: already done on this device'
      : 'migrated $vices vices and $activities activities';
}

/// Seals the user's plaintext documents on first launch: one update each
/// that adds `enc` and deletes the plaintext fields (rules R1's migration
/// branch). Documents that already have `enc` are skipped, which is what
/// makes a second run harmless; the rules can't tell it from a rename.
class JournalMigrator {
  JournalMigrator({
    required this.cipher,
    required this.store,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore;

  final JournalCipher cipher;
  final KeyStore store;
  final FirebaseFirestore? _firestore;

  /// tests/firestore-rules/e2ee.test.js commits a batch of this size. The batch page
  /// documents no operation cap, only the 10 MiB request size
  /// (https://firebase.google.com/docs/firestore/manage-data/transactions).
  static const int pageSize = 200;

  Future<Map<String, Object>?> viceUpdate(
    String docId,
    Map<String, dynamic> json,
  ) async {
    if (json.containsKey('enc')) {
      return null;
    }

    return <String, Object>{
      'enc': Blob(
        await cipher.seal(
          collection: 'vices',
          docId: docId,
          ownerID: json['ownerID'] as String,
          fields: <String, Object?>{'n': json['name'], 'u': json['unit']},
        ),
      ),
      'name': FieldValue.delete(),
      'unit': FieldValue.delete(),
      // Vices written before `archived` existed get it here (C18's migrator).
      if (!json.containsKey('archived')) 'archived': false,
    };
  }

  Future<Map<String, Object>?> activityUpdate(
    String docId,
    Map<String, dynamic> json,
  ) async {
    if (json.containsKey('enc')) {
      return null;
    }

    return <String, Object>{
      'enc': Blob(
        await cipher.seal(
          collection: 'activities',
          docId: docId,
          ownerID: json['ownerID'] as String,
          viceID: json['viceID'] as String,
          fields: <String, Object?>{'q': json['quantity']},
        ),
      ),
      'quantity': FieldValue.delete(),
    };
  }

  Future<MigrationReport> run(String uid) async {
    if (await store.isMigrated(uid)) {
      return MigrationReport(skipped: true);
    }

    final FirebaseFirestore firestore = _firestore ?? FirebaseFirestore.instance;
    final int vices = await _migrate(
      firestore.collection('vices'),
      uid,
      viceUpdate,
    );
    final int activities = await _migrate(
      firestore.collection('activities'),
      uid,
      activityUpdate,
    );

    await store.markMigrated(uid);
    return MigrationReport(vices: vices, activities: activities);
  }

  // Firestore can't query for a missing field, so every document is paged
  // through and the sealed ones skipped. Ordered by createdAt for
  // startAfterDocument; a document without createdAt is not returned.
  Future<int> _migrate(
    CollectionReference<Map<String, dynamic>> collection,
    String uid,
    Future<Map<String, Object>?> Function(String, Map<String, dynamic>) update,
  ) async {
    int migrated = 0;
    DocumentSnapshot<Map<String, dynamic>>? last;

    while (true) {
      Query<Map<String, dynamic>> page = collection
          .where('ownerID', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(pageSize);
      if (last != null) {
        page = page.startAfterDocument(last);
      }

      final QuerySnapshot<Map<String, dynamic>> snapshot = await page.get(
        const GetOptions(source: Source.server),
      );
      if (snapshot.docs.isEmpty) {
        return migrated;
      }

      final WriteBatch batch = collection.firestore.batch();
      int writes = 0;
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs) {
        final Map<String, Object>? data = await update(doc.id, doc.data());
        if (data != null) {
          batch.update(doc.reference, data);
          writes++;
        }
      }
      if (writes > 0) {
        await batch.commit();
      }

      migrated += writes;
      last = snapshot.docs.last;
    }
  }
}
