import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/category.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/main.dart';

import 'support.dart';

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('a vice stored without a category gets one guessed from its '
      'name, which the habit editor shows', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, 'e2e-category@example.com');
    await createBypassingRules('vices', 'legacy-booze', <String, Object>{
      'name': <String, Object>{'stringValue': 'Booze'},
      'unit': <String, Object>{'stringValue': 'drink'},
      'ownerID': <String, Object>{
        'stringValue': FirebaseAuth.instance.currentUser!.uid,
      },
      'createdAt': <String, Object>{
        'timestampValue': DateTime.now().toUtc().toIso8601String(),
      },
      'archived': <String, Object>{'booleanValue': false},
    });

    final DocumentReference<Map<String, dynamic>> stored = FirebaseFirestore
        .instance
        .collection('vices')
        .doc('legacy-booze');
    // The emulator's copy, read again whenever the last read has answered.
    Object? category;
    Future<void>? reading;
    await pumpUntilTrue(tester, () {
      reading ??= stored.get(const GetOptions(source: Source.server)).then((
        DocumentSnapshot<Map<String, dynamic>> snapshot,
      ) {
        category = snapshot.data()?['category'];
        reading = null;
      });
      return category == ViceCategory.alcohol.name;
    }, () => 'the migration to store category alcohol, saw $category');

    await openFromMenu(tester, Homepage.habitsItem);
    await tap(tester, find.text('Booze'));
    await pumpUntilRouteSettled(tester, historyTitle('Booze'));
    await tap(tester, find.byTooltip('Edit habit'));
    await pumpUntilRouteSettled(tester, find.text('Edit Habit'));
    expect(find.text(ViceCategory.alcohol.label), findsOneWidget);
  });
}
