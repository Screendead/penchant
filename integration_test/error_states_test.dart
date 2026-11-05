import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/main.dart';
import 'package:tracker/manage_data.dart';
import 'package:tracker/providers/vice_list_provider.dart';

import 'support.dart';

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('a vice list the rules deny shows why, with a Retry that '
      'listens again', (WidgetTester tester) async {
    // The app never asks for another account's vices, so the first listen
    // does, to get a real permission-denied from the emulator's rules.
    String? askAs = 'someone-else';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          viceListForUserProvider.overrideWith((ref, String uid) {
            final String owner = askAs ?? uid;
            return FirebaseFirestore.instance
                .collection('vices')
                .where('ownerID', isEqualTo: owner)
                .orderBy('createdAt', descending: true)
                .snapshots()
                .map(Vice.fromQuerySnapshot);
          }),
        ],
        child: const MyApp(),
      ),
    );
    await register(tester, 'e2e-denied-read@example.com');

    await openFromDrawer(tester, 'Manage Data');
    final String denied = loadErrorMessage(
      'your habits',
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
    );
    await pumpUntil(tester, find.text(denied));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await screenshot(tester, 'denied-vice-list');

    askAs = null;
    // Today, under the Manage Data route, reads the same denied list.
    await tap(
      tester,
      find.descendant(
        of: find.byType(ManageData),
        matching: find.widgetWithText(TextButton, 'Retry'),
      ),
    );
    await pumpUntil(tester, find.text('No habits yet. Tap + to add one.'));
    expect(find.text(denied), findsNothing);
  });
}
