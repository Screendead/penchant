import 'package:cloud_firestore/cloud_firestore.dart' hide Settings;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/main.dart';
import 'package:tracker/vice_form.dart';

import '../test/fake_sealer.dart';
import 'support.dart';

const GetOptions _server = GetOptions(source: Source.server);

Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _owned(
  String collection,
) async {
  await FirebaseFirestore.instance.waitForPendingWrites().timeout(timeout);
  final QuerySnapshot<Map<String, dynamic>> found = await FirebaseFirestore
      .instance
      .collection(collection)
      .where('ownerID', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
      .get(_server);
  return found.docs;
}

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('with a key, habits and entries are stored sealed, and read and '
      'edit as before', (WidgetTester tester) async {
    final FakeSealer sealer = FakeSealer();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sealerProvider.overrideWithValue(sealer)],
        child: const MyApp(),
      ),
    );
    await register(tester, 'e2e-sealed@example.com');
    await addVicesThroughManageData(tester, const <String>['Coffee', 'Tea']);
    await recordActivity(tester, 'Coffee', 2);
    await expectTallies(tester, const <String>{
      'Coffee (2 drinks)',
      'Tea (0 drinks)',
    });

    final List<QueryDocumentSnapshot<Map<String, dynamic>>> vices =
        await _owned('vices');
    expect(vices, hasLength(2));
    for (final QueryDocumentSnapshot<Map<String, dynamic>> vice in vices) {
      expect(vice.data().keys.toSet(), <String>{
        sealedField,
        'ownerID',
        'createdAt',
        'archived',
      });
    }
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> activities =
        await _owned('activities');
    // Only the triggers are sealed; the quantity stays plaintext.
    expect(activities.single.data().keys.toSet(), <String>{
      sealedField,
      'quantity',
      'ownerID',
      'viceID',
      'createdAt',
    });
    expect(
      await sealer.open(
        (activities.single.data()[sealedField] as Blob).bytes,
        context: sealContext('activities', activities.single.id),
      ),
      <String, Object?>{'triggers': <Object?>[]},
    );
    expect(
      activities.single.data()['viceID'],
      isIn(vices.map((QueryDocumentSnapshot<Object?> v) => v.id)),
    );

    await openFromMenu(tester, Homepage.habitsItem);
    await tap(tester, find.text('Coffee'));
    await pumpUntilRouteSettled(tester, historyTitle('Coffee'));
    await tap(tester, find.byTooltip('Edit habit'));
    await pumpUntilRouteSettled(tester, find.text('Edit Habit'));
    await enterText(tester, 'Habit Name', 'Espresso');
    await tap(tester, find.byType(DropdownButtonFormField<Unit>));
    await tap(tester, find.text(Unit.hour.plural).last);
    await tap(tester, find.widgetWithText(TextButton, 'Save'));
    await pumpUntil(tester, find.byType(EditVice), present: false);
    await pumpUntil(tester, find.text('Espresso'));

    final Map<String, Map<String, Object?>> opened =
        <String, Map<String, Object?>>{
          for (final QueryDocumentSnapshot<Map<String, dynamic>> vice
              in await _owned('vices'))
            vice.id: await sealer.open(
              (vice.data()[sealedField] as Blob).bytes,
              context: sealContext('vices', vice.id),
            ),
        };
    expect(
      opened.values.map(
        (Map<String, Object?> fields) => (fields['name'], fields['unit']),
      ),
      unorderedEquals(<(Object?, Object?)>[
        ('Espresso', 'hour'),
        ('Tea', 'drink'),
      ]),
    );
    for (final Map<String, Object?> fields in opened.values) {
      expect(fields['category'], isA<String>());
    }
    for (final QueryDocumentSnapshot<Map<String, dynamic>> vice in await _owned(
      'vices',
    )) {
      expect(vice.data().containsKey('name'), isFalse);
    }

    await closeMenuPage(tester);
    await expectTallies(tester, const <String>{
      'Espresso (2 hours)',
      'Tea (0 drinks)',
    });
  });
}
