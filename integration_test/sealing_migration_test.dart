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
    final DateTime now = DateTime.now();
    final Map<String, Object> at = <String, Object>{
      'timestampValue': now.toUtc().toIso8601String(),
    };
    Map<String, Object> text(String value) => <String, Object>{
      'stringValue': value,
    };
    final Map<String, Object> owner = text(uid);

    // Legacy plaintext, which the rules no longer take from a client. More
    // vices than one page, so the run crosses a page boundary.
    const int viceCount = 520;
    final DocumentReference<Map<String, dynamic>> coffee = db
        .collection('vices')
        .doc();
    await createAllBypassingRules('vices', <String, Map<String, Object>>{
      coffee.id: <String, Object>{
        'name': text('Coffee'),
        'unit': text('drink'),
        'ownerID': owner,
        'createdAt': at,
        'archived': <String, Object>{'booleanValue': false},
        'category': text('caffeine'),
      },
      for (int n = 1; n < viceCount; n++)
        db.collection('vices').doc().id: <String, Object>{
          'name': text('Habit $n'),
          'unit': text('item'),
          'ownerID': owner,
          'createdAt': at,
          'archived': <String, Object>{'booleanValue': true},
          'category': text('other'),
        },
    });
    final DocumentReference<Map<String, dynamic>> plain = db
        .collection('activities')
        .doc();
    final DocumentReference<Map<String, dynamic>> triggered = db
        .collection('activities')
        .doc();
    await createAllBypassingRules('activities', <String, Map<String, Object>>{
      plain.id: <String, Object>{
        'viceID': text(coffee.id),
        'quantity': <String, Object>{'integerValue': '2'},
        'ownerID': owner,
        'createdAt': at,
      },
      triggered.id: <String, Object>{
        'viceID': text(coffee.id),
        'quantity': <String, Object>{'integerValue': '3'},
        'amount': <String, Object>{'doubleValue': 2.5},
        'ownerID': owner,
        'createdAt': at,
        'triggers': <String, Object>{
          'arrayValue': <String, Object>{
            'values': <Object>[text('social')],
          },
        },
      },
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
      <String, Object>{
        'name': 'Coffee',
        'unit': 'drink',
        'category': 'caffeine',
      },
    );
    expect(sealedCoffee['archived'], false);

    // Activities run after vices, so wait for the triggered one too.
    Map<String, dynamic> sealedEntry = (await triggered.get(
      const GetOptions(source: Source.server),
    )).data()!;
    while (!sealedEntry.containsKey(sealedField) &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 500));
      sealedEntry = (await triggered.get(
        const GetOptions(source: Source.server),
      )).data()!;
    }
    expect(sealedEntry.containsKey('triggers'), isFalse);
    expect((sealedEntry['quantity'], sealedEntry['amount']), (3, 2.5));
    expect(
      await sealer.open(
        (sealedEntry[sealedField] as Blob).bytes,
        context: sealContext('activities', triggered.id),
      ),
      <String, Object>{
        'triggers': <Object?>['social'],
      },
    );

    final Map<String, dynamic> activity = (await plain.get(
      const GetOptions(source: Source.server),
    )).data()!;
    expect(activity['quantity'], 2);
    expect(activity.containsKey(sealedField), isFalse);
  });
}
