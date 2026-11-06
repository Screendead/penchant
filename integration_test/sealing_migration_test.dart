import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/crypto/sealer.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/main.dart';

import 'support.dart';

// Stands in for the crypto core's sealer: what this test checks is that every
// legacy document is rewritten, not the cipher.
class _JsonSealer implements Sealer {
  @override
  Future<Uint8List> seal({
    required String collection,
    required String docId,
    required String ownerID,
    String? viceID,
    required Map<String, Object?> fields,
  }) async => Uint8List.fromList(utf8.encode(jsonEncode(fields)));
}

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('a launch with a key seals every legacy plaintext document', (
    WidgetTester tester,
  ) async {
    final UserCredential credential = await FirebaseAuth.instance
        .createUserWithEmailAndPassword(
          email: 'e2e-sealing@example.com',
          password: 'e2e-password',
        );
    final String uid = credential.user!.uid;
    final FirebaseFirestore db = FirebaseFirestore.instance;
    final Timestamp at = Timestamp.now();

    // More activities than one page, so the run crosses a page boundary.
    const int activityCount = 520;
    final DocumentReference<Map<String, dynamic>> coffee = db
        .collection('vices')
        .doc();
    await coffee.set(<String, Object>{
      'name': 'Coffee',
      'unit': 'drink',
      'ownerID': uid,
      'createdAt': at,
      'archived': false,
    });
    await db.collection('vices').add(<String, Object>{
      'name': 'Tea',
      'unit': 'drink',
      'ownerID': uid,
      'createdAt': at,
      'archived': true,
    });
    for (int start = 0; start < activityCount; start += 400) {
      final WriteBatch batch = db.batch();
      for (int n = start; n < activityCount && n < start + 400; n++) {
        batch.set(db.collection('activities').doc(), <String, Object>{
          'viceID': coffee.id,
          'quantity': 1 + n % 3,
          'ownerID': uid,
          'createdAt': Timestamp.fromMillisecondsSinceEpoch(
            at.millisecondsSinceEpoch - n * 60000,
          ),
        });
      }
      await batch.commit();
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sealerProvider.overrideWithValue(_JsonSealer())],
        child: const MyApp(),
      ),
    );
    await pumpUntil(tester, find.byType(Homepage));

    Future<int> plaintextLeft() async {
      final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
          <QueryDocumentSnapshot<Map<String, dynamic>>>[
            for (final String collection in plaintextFields.keys)
              ...(await db
                      .collection(collection)
                      .where('ownerID', isEqualTo: uid)
                      .get(const GetOptions(source: Source.server)))
                  .docs,
          ];
      expect(docs, hasLength(2 + activityCount));
      return docs.where((QueryDocumentSnapshot<Map<String, dynamic>> doc) {
        final Map<String, dynamic> data = doc.data();
        return !data.containsKey(sealedField) ||
            plaintextFields.values.any(
              (List<String> fields) => fields.any(data.containsKey),
            );
      }).length;
    }

    final DateTime deadline = DateTime.now().add(timeout);
    int left = await plaintextLeft();
    while (left > 0 && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 500));
      left = await plaintextLeft();
    }
    expect(left, 0, reason: 'documents still holding plaintext');

    final Map<String, dynamic> sealedCoffee = (await coffee.get(
      const GetOptions(source: Source.server),
    )).data()!;
    expect(
      jsonDecode(utf8.decode((sealedCoffee[sealedField] as Blob).bytes)),
      <String, Object>{'name': 'Coffee', 'unit': 'drink'},
    );
    expect(sealedCoffee['archived'], false);
  });
}
