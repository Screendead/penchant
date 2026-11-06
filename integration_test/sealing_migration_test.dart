import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/main.dart';

import '../test/fake_sealer.dart';
import 'support.dart';

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('a launch with a key seals every legacy plaintext vice', (
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

    // More vices than one page, so the run crosses a page boundary.
    const int viceCount = 520;
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
    for (int start = 1; start < viceCount; start += 400) {
      final WriteBatch batch = db.batch();
      for (int n = start; n < viceCount && n < start + 400; n++) {
        batch.set(db.collection('vices').doc(), <String, Object>{
          'name': 'Habit $n',
          'unit': 'item',
          'ownerID': uid,
          'createdAt': at,
          'archived': true,
        });
      }
      await batch.commit();
    }
    await db.collection('activities').add(<String, Object>{
      'viceID': coffee.id,
      'quantity': 2,
      'ownerID': uid,
      'createdAt': at,
    });

    final FakeSealer sealer = FakeSealer();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sealerProvider.overrideWithValue(sealer)],
        child: const MyApp(),
      ),
    );
    await pumpUntil(tester, find.byType(Homepage));

    Future<int> plaintextLeft() async {
      final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
          (await db
                  .collection('vices')
                  .where('ownerID', isEqualTo: uid)
                  .get(const GetOptions(source: Source.server)))
              .docs;
      expect(docs, hasLength(viceCount));
      return docs.where((QueryDocumentSnapshot<Map<String, dynamic>> doc) {
        final Map<String, dynamic> data = doc.data();
        return !data.containsKey(sealedField) ||
            viceContentFields.any(data.containsKey);
      }).length;
    }

    final DateTime deadline = DateTime.now().add(timeout);
    int left = await plaintextLeft();
    while (left > 0 && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 500));
      left = await plaintextLeft();
    }
    expect(left, 0, reason: 'vices still holding plaintext');

    final Map<String, dynamic> sealedCoffee = (await coffee.get(
      const GetOptions(source: Source.server),
    )).data()!;
    expect(
      await sealer.open(
        (sealedCoffee[sealedField] as Blob).bytes,
        context: sealContext('vices', coffee.id),
      ),
      <String, Object>{'name': 'Coffee', 'unit': 'drink'},
    );
    expect(sealedCoffee['archived'], false);

    final Map<String, dynamic> activity =
        (await db
                .collection('activities')
                .where('ownerID', isEqualTo: uid)
                .get(const GetOptions(source: Source.server)))
            .docs
            .single
            .data();
    expect(activity['quantity'], 2);
    expect(activity.containsKey(sealedField), isFalse);
  });
}
